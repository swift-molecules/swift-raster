#if Geometry
    public import Direction
    public import Geometry
    public import Numeric
#endif

public struct Raster<Pixel> {
    public let width: Cardinal
    public let height: Cardinal
    @usableFromInline
    internal var storage: [Pixel]

    @inlinable
    public init(width: Cardinal, height: Cardinal, pixels: [Pixel]) throws(Error) {
        let (count, overflow) = Int(bitPattern: width).multipliedReportingOverflow(by: Int(bitPattern: height))
        guard !overflow, count >= 0, pixels.count == count else { throw .count }
        self.width = width
        self.height = height
        self.storage = pixels
    }
}

extension Raster: Equatable where Pixel: Equatable {}
extension Raster: Hashable where Pixel: Hashable {}
extension Raster: Sendable where Pixel: Sendable {}

extension Raster {
    @inlinable
    public init(width: Cardinal, height: Cardinal, repeating pixel: Pixel) {
        self.init(columns: Int(bitPattern: width), rows: Int(bitPattern: height), repeating: pixel)
    }

    @inlinable
    public init<Failure: Swift::Error>(
        width: Cardinal,
        height: Cardinal,
        _ pixel: (_ x: Ordinal, _ y: Ordinal) throws(Failure) -> Pixel
    ) throws(Failure) {
        self = try Self.filled(columns: Int(bitPattern: width), rows: Int(bitPattern: height)) { (x, y) throws(Failure) in
            try pixel(Ordinal(UInt(x)), Ordinal(UInt(y)))
        }
    }

    @inlinable
    public var pixels: [Pixel] { storage }

    @inlinable
    public var isEmpty: Bool { storage.isEmpty }

    @inlinable
    public subscript(x x: Ordinal, y y: Ordinal) -> Pixel {
        get {
            precondition(x < Ordinal(width) && y < Ordinal(height), "A pixel position lies inside its raster")
            return pixels[Int(bitPattern: y) * columns + Int(bitPattern: x)]
        }
        set {
            precondition(x < Ordinal(width) && y < Ordinal(height), "A pixel position lies inside its raster")
            storage[Int(bitPattern: y) * columns + Int(bitPattern: x)] = newValue
        }
    }

    @inlinable
    public func row(_ y: Ordinal) -> ArraySlice<Pixel> {
        precondition(y < Ordinal(height), "A row lies inside its raster")
        let start = Int(bitPattern: y) * columns
        return pixels[start..<(start + columns)]
    }
}

extension Raster {
    @inlinable
    public func cropped(to region: Region) throws(Error) -> Self {
        let left = Int(bitPattern: region.x)
        let top = Int(bitPattern: region.y)
        let wide = Int(bitPattern: region.width)
        let tall = Int(bitPattern: region.height)
        guard left >= 0, top >= 0, wide >= 0, tall >= 0, wide <= columns - left, tall <= rows - top else {
            throw .bounds
        }
        return Self.filled(columns: wide, rows: tall) { x, y in self[column: left + x, row: top + y] }
    }

    @inlinable
    public func replacing(x: Ordinal, y: Ordinal, with other: Self) throws(Error) -> Self {
        let region = Region(x: x, y: y, width: other.width, height: other.height)
        let left = Int(bitPattern: region.x)
        let top = Int(bitPattern: region.y)
        guard left >= 0, top >= 0, other.columns <= columns - left, other.rows <= rows - top else {
            throw .bounds
        }
        var result = self
        other.pixels.indices.forEach { index in
            result.storage[(top + index / other.columns) * columns + left + index % other.columns] = other.pixels[index]
        }
        return result
    }
}

extension Raster {
    @inlinable
    public init(tiling tiles: [Self], columns: Cardinal, gap: Cardinal = .zero, fill: Pixel) throws(Error) {
        guard !tiles.isEmpty else {
            self.init(columns: 0, rows: 0, repeating: fill)
            return
        }
        let limit = Int(bitPattern: columns)
        let space = Int(bitPattern: gap)
        guard limit > 0, space >= 0 else { throw .count }
        let across = Swift.min(limit, tiles.count)
        let down = tiles.count / across + (tiles.count % across == 0 ? 0 : 1)
        var widths = [Int](repeating: 0, count: across)
        var heights = [Int](repeating: 0, count: down)
        for index in tiles.indices {
            widths[index % across] = Swift.max(widths[index % across], tiles[index].columns)
            heights[index / across] = Swift.max(heights[index / across], tiles[index].rows)
        }
        guard let (lefts, wide) = Self.starts(of: widths, gap: space), let (tops, tall) = Self.starts(of: heights, gap: space) else {
            throw .count
        }
        let (count, overflow) = wide.multipliedReportingOverflow(by: tall)
        guard !overflow else { throw .count }
        var pixels = [Pixel](repeating: fill, count: count)
        for index in tiles.indices {
            let tile = tiles[index]
            let left = lefts[index % across]
            let top = tops[index / across]
            tile.storage.indices.forEach { position in
                pixels[(top + position / tile.columns) * wide + left + position % tile.columns] = tile.storage[position]
            }
        }
        self.init(width: Cardinal(UInt(wide)), height: Cardinal(UInt(tall)), valid: pixels)
    }

    /// Where each of some lengths starts when they follow one another a gap apart, and where the last one
    /// ends; `nil` when that does not fit a signed word.
    @inlinable
    internal static func starts(of lengths: [Int], gap: Int) -> (starts: [Int], end: Int)? {
        var starts: [Int] = []
        starts.reserveCapacity(lengths.count)
        var end = 0
        for length in lengths {
            if !starts.isEmpty {
                let (spaced, far) = end.addingReportingOverflow(gap)
                guard !far else { return nil }
                end = spaced
            }
            starts.append(end)
            let (next, far) = end.addingReportingOverflow(length)
            guard !far else { return nil }
            end = next
        }
        return (starts, end)
    }
}

extension Raster {
    @inlinable
    public func map<Result, Failure: Swift::Error>(
        _ transform: (Pixel) throws(Failure) -> Result
    ) throws(Failure) -> Raster<Result> {
        var result: [Result] = []
        result.reserveCapacity(pixels.count)
        for pixel in pixels { result.append(try transform(pixel)) }
        return Raster<Result>(width: width, height: height, valid: result)
    }

    @inlinable
    public func zip<Other, Result, Failure: Swift::Error>(
        _ other: Raster<Other>,
        _ combine: (Pixel, Other) throws(Failure) -> Result
    ) throws(Failure) -> Raster<Result>? {
        guard width == other.width, height == other.height else { return nil }
        var result: [Result] = []
        result.reserveCapacity(pixels.count)
        for index in pixels.indices { result.append(try combine(pixels[index], other.pixels[index])) }
        return Raster<Result>(width: width, height: height, valid: result)
    }

    @inlinable
    public func reduce<Result, Failure: Swift::Error>(
        _ initial: Result,
        _ next: (Result, Pixel) throws(Failure) -> Result
    ) throws(Failure) -> Result {
        var result = initial
        for pixel in pixels { result = try next(result, pixel) }
        return result
    }

    @inlinable
    public func reduce<Result, Failure: Swift::Error>(
        into initial: Result,
        _ update: (inout Result, Pixel) throws(Failure) -> Void
    ) throws(Failure) -> Result {
        var result = initial
        for pixel in pixels { try update(&result, pixel) }
        return result
    }
}

extension Raster {
    @inlinable
    public func sample<Scalar: BinaryFloatingPoint, Failure: Swift::Error>(
        at point: Point<2, Scalar>,
        _ sampling: Sampling,
        edge: Edge,
        mixing mix: (Pixel, Pixel, Scalar) throws(Failure) -> Pixel
    ) throws(Failure) -> Pixel {
        switch sampling {
        case .nearest:
            return self[column: Self.floor(point.x), row: Self.floor(point.y), edge: edge]

        case .bilinear:
            let half: Scalar = 1 / 2
            let across = point.x - half
            let down = point.y - half
            let left = Self.floor(across)
            let top = Self.floor(down)
            let right = across - Self.real(left)
            let below = down - Self.real(top)
            let upper = try self.span(column: left, row: top, fraction: right, edge: edge, mixing: mix)
            guard below > 0 else { return upper }
            let lower = try self.span(column: left, row: top + 1, fraction: right, edge: edge, mixing: mix)
            return try mix(upper, lower, below)
        }
    }

    @inlinable
    public func warped<Scalar: BinaryFloatingPoint, Failure: Swift::Error>(
        width: Cardinal,
        height: Cardinal,
        _ sampling: Sampling,
        edge: Edge,
        mixing mix: (Pixel, Pixel, Scalar) throws(Failure) -> Pixel,
        from source: (Point<2, Scalar>) throws(Failure) -> Point<2, Scalar>
    ) throws(Failure) -> Self {
        let half: Scalar = 1 / 2
        return try Self.filled(columns: Int(bitPattern: width), rows: Int(bitPattern: height)) { (x, y) throws(Failure) in
            let point = try source(Point(x: Self.real(x) + half, y: Self.real(y) + half))
            return try self.sample(at: point, sampling, edge: edge, mixing: mix)
        }
    }

    @inlinable
    public func warped<Scalar: BinaryFloatingPoint, Failure: Swift::Error>(
        by map: Matrix<2, 3, Scalar>,
        width: Cardinal,
        height: Cardinal,
        _ sampling: Sampling,
        edge: Edge,
        mixing mix: (Pixel, Pixel, Scalar) throws(Failure) -> Pixel
    ) throws(Failure) -> Self {
        let across = (map[0, 0], map[0, 1], map[0, 2])
        let down = (map[1, 0], map[1, 1], map[1, 2])
        return try warped(width: width, height: height, sampling, edge: edge, mixing: mix) { (point: Point<2, Scalar>) throws(Failure) -> Point<2, Scalar> in
            let (x, y) = (point.x, point.y)
            return Point(x: across.0 * x + across.1 * y + across.2, y: down.0 * x + down.1 * y + down.2)
        }
    }
}

extension Raster {
    @inlinable
    public func resampled<Scalar: BinaryFloatingPoint, Failure: Swift::Error>(
        width: Cardinal,
        height: Cardinal,
        _ filter: Filter,
        mixing mix: (Pixel, Pixel, Scalar) throws(Failure) -> Pixel
    ) throws(Failure) -> Self {
        let wide = Int(bitPattern: width)
        let tall = Int(bitPattern: height)
        guard wide > 0, tall > 0 else { return Self.filled(columns: wide, rows: tall) { _, _ in pixels[0] } }
        precondition(!isEmpty, "An empty raster has no pixel to resample")
        let across: [Chain<Scalar>] = filter.chains(from: columns, to: wide)
        let down: [Chain<Scalar>] = filter.chains(from: rows, to: tall)
        let narrowed = try Self.filled(columns: wide, rows: rows) { (x, y) throws(Failure) in
            try across[x].value(mixing: mix) { self[column: $0, row: y] }
        }
        return try Self.filled(columns: wide, rows: tall) { (x, y) throws(Failure) in
            try down[y].value(mixing: mix) { narrowed[column: x, row: $0] }
        }
    }

    @inlinable
    public func convolved<Scalar: BinaryFloatingPoint, Failure: Swift::Error>(
        horizontal: Kernel<Scalar>,
        vertical: Kernel<Scalar>,
        edge: Edge,
        mixing mix: (Pixel, Pixel, Scalar) throws(Failure) -> Pixel
    ) throws(Failure) -> Self {
        guard !isEmpty else { return self }
        return try smeared(horizontal.chain, down: false, edge: edge, mixing: mix)
            .smeared(vertical.chain, down: true, edge: edge, mixing: mix)
    }
}

extension Raster {
    @inlinable
    internal var columns: Int { Int(bitPattern: width) }
    @inlinable
    internal var rows: Int { Int(bitPattern: height) }

    @inlinable
    internal init(width: Cardinal, height: Cardinal, valid pixels: [Pixel]) {
        self.width = width
        self.height = height
        self.storage = pixels
    }

    @inlinable
    internal init(columns: Int, rows: Int, repeating pixel: Pixel) {
        precondition(columns >= 0 && rows >= 0, "A raster's width and height fit a signed word")
        let (count, overflow) = columns.multipliedReportingOverflow(by: rows)
        precondition(!overflow, "A raster's pixel count fits a signed word")
        self.init(
            width: Cardinal(UInt(columns)),
            height: Cardinal(UInt(rows)),
            valid: [Pixel](repeating: pixel, count: count)
        )
    }

    @inlinable
    internal static func filled<Failure: Swift::Error>(
        columns: Int,
        rows: Int,
        _ pixel: (_ column: Int, _ row: Int) throws(Failure) -> Pixel
    ) throws(Failure) -> Self {
        precondition(columns >= 0 && rows >= 0, "A raster's width and height fit a signed word")
        let (count, overflow) = columns.multipliedReportingOverflow(by: rows)
        precondition(!overflow, "A raster's pixel count fits a signed word")
        var pixels: [Pixel] = []
        pixels.reserveCapacity(count)
        for row in 0..<rows {
            for column in 0..<columns { pixels.append(try pixel(column, row)) }
        }
        return Self(width: Cardinal(UInt(columns)), height: Cardinal(UInt(rows)), valid: pixels)
    }

    @inlinable
    internal subscript(column column: Int, row row: Int) -> Pixel { storage[row * columns + column] }

    @inlinable
    internal subscript(column column: Int, row row: Int, edge edge: Edge) -> Pixel {
        if column >= 0, column < columns, row >= 0, row < rows { return storage[row * columns + column] }
        if case .constant(let pixel) = edge { return pixel }
        precondition(!isEmpty, "An empty raster has no pixel to sample")
        return storage[edge.position(row, in: rows) * columns + edge.position(column, in: columns)]
    }

    /// The average `chain` describes, taken along the rows or down the columns. Away from the border the
    /// pixels are read straight from storage.
    @inlinable
    internal func smeared<Scalar: BinaryFloatingPoint, Failure: Swift::Error>(
        _ chain: Chain<Scalar>,
        down: Bool,
        edge: Edge,
        mixing mix: (Pixel, Pixel, Scalar) throws(Failure) -> Pixel
    ) throws(Failure) -> Self {
        let step = down ? columns : 1
        let offsets = chain.offsets
        let parameters = chain.parameters
        guard let first = offsets.first, let last = offsets.last, first != 0 || last != 0 else { return self }
        let low = -first
        let high = (down ? rows : columns) - last
        return try Self.filled(columns: columns, rows: rows) { (x, y) throws(Failure) in
            let position = down ? y : x
            if position >= low, position < high {
                let base = y * columns + x
                var result = storage[base + first * step]
                for index in 1..<offsets.count {
                    result = try mix(result, storage[base + offsets[index] * step], parameters[index])
                }
                return result
            }
            return try chain.value(mixing: mix) { offset in
                down ? self[column: x, row: y + offset, edge: edge] : self[column: x + offset, row: y, edge: edge]
            }
        }
    }

    @inlinable
    internal func span<Scalar: BinaryFloatingPoint, Failure: Swift::Error>(
        column: Int,
        row: Int,
        fraction: Scalar,
        edge: Edge,
        mixing mix: (Pixel, Pixel, Scalar) throws(Failure) -> Pixel
    ) throws(Failure) -> Pixel {
        let first = self[column: column, row: row, edge: edge]
        guard fraction > 0 else { return first }
        return try mix(first, self[column: column + 1, row: row, edge: edge], fraction)
    }

    /// `value` rounded to a whole number and held between two bounds; the lower bound for a value that is not a number.
    @inlinable
    internal static func whole<Scalar: BinaryFloatingPoint>(
        _ value: Scalar,
        _ rule: FloatingPointRoundingRule,
        from lower: Int,
        to upper: Int
    ) -> Int {
        let rounded = value.rounded(rule)
        guard rounded > real(lower) else { return lower }
        guard rounded < real(upper) else { return upper }
        return word(rounded)
    }

    /// Where a region starts along one axis, as a signed word that leaves room to add the region's extent.
    @inlinable
    internal static func origin(_ position: Ordinal) -> Int {
        let limit = Int.max / 4
        let value = Int(bitPattern: position)
        return value >= 0 && value < limit ? value : limit
    }

    @inlinable
    internal static func floor<Scalar: BinaryFloatingPoint>(_ value: Scalar) -> Int {
        precondition(value.isFinite, "A sample position is finite")
        if let double = value as? Double {
            return Int(Swift.min(Swift.max(double.rounded(.down), -0x1p62), 0x1p62))
        }
        let limit = Scalar(sign: .plus, exponent: 62, significand: 1)
        return Int(Swift.min(Swift.max(value.rounded(.down), -limit), limit))
    }

    /// A whole number as a scalar; for `Double` and `Float` by the processor's own conversion, which gives
    /// the number the general one gives without going through it.
    @inlinable
    @inline(__always)
    internal static func real<Scalar: BinaryFloatingPoint>(_ value: Int) -> Scalar {
        if let double = Double(value) as? Scalar { return double }
        if let float = Float(value) as? Scalar { return float }
        return Scalar(value)
    }

    /// A scalar that holds a whole number in a word's range, as that word.
    @inlinable
    @inline(__always)
    internal static func word<Scalar: BinaryFloatingPoint>(_ value: Scalar) -> Int {
        if let double = value as? Double { return Int(double) }
        if let float = value as? Float { return Int(float) }
        return Int(value)
    }
}

extension Raster {
    /// The mean over all pixels of `error(mine, theirs)`, or `nil` for rasters of different sizes or with no pixels.
    @inlinable
    public func mean<Scalar: BinaryFloatingPoint, Failure: Swift::Error>(
        against other: Self,
        _ error: (Pixel, Pixel) throws(Failure) -> Scalar
    ) throws(Failure) -> Scalar? {
        guard width == other.width, height == other.height, !pixels.isEmpty else { return nil }
        var sum: Scalar = 0
        for index in pixels.indices { sum += try error(pixels[index], other.pixels[index]) }
        return sum / Scalar(pixels.count)
    }

    /// Peak signal-to-noise ratio in decibels: ten times the base-ten logarithm of `peak` squared over the
    /// mean squared error, where `squared` gives one pixel pair's squared error averaged over its channels.
    /// Rasters with no error at all give +∞, and so do two empty rasters; rasters of different sizes,
    /// which the ratio cannot compare, give `nil`.
    @inlinable
    public func psnr<Scalar: BinaryFloatingPoint & Exponential.`Protocol`, Failure: Swift::Error>(
        against other: Self,
        peak: Scalar,
        squared: (Pixel, Pixel) throws(Failure) -> Scalar
    ) throws(Failure) -> Scalar? {
        guard width == other.width, height == other.height else { return nil }
        guard let mean = try mean(against: other, squared), mean > 0 else { return .infinity }
        return 10 * Scalar.log10(peak * peak / mean)
    }
}

extension Raster {
    /// For each pixel of `region`, `pixel` of the nearest triangle that takes the pixel's centre, and `empty`
    /// where none does. A triangle is three points whose x and y are raster positions and whose z is depth.
    /// `pixel` is given the triangle's position in the sequence, the centre's barycentric weights on the
    /// triangle's three corners, and the depth those weights give.
    @inlinable
    public static func fragments<Scalar: BinaryFloatingPoint, Failure: Swift::Error>(
        of triangles: some Swift::Sequence<InlineArray<3, Point<3, Scalar>>>,
        in region: Region,
        empty: Pixel,
        _ pixel: (_ triangle: Ordinal, _ weights: InlineArray<3, Scalar>, _ depth: Scalar) throws(Failure) -> Pixel
    ) throws(Failure) -> Self {
        let nearest = nearest(of: triangles, in: region)
        let columns = Int(bitPattern: region.width)
        let left = origin(region.x)
        let top = origin(region.y)
        let half: Scalar = 1 / 2
        return try filled(columns: columns, rows: Int(bitPattern: region.height)) { (column, row) throws(Failure) in
            let winner = nearest.winners[row * columns + column]
            guard winner >= 0, let facet = nearest.facets[winner],
                let sample = facet.sample(x: real(left + column) + half, y: real(top + row) + half)
            else { return empty }
            return try pixel(Ordinal(UInt(winner)), sample.weights, sample.depth)
        }
    }

    /// `fragments(of:in:empty:_:)` for a pixel that needs no weights: `pixel` is given the triangle's position
    /// in the sequence and the depth at the centre. The same triangle wins each pixel, at the same depth, and
    /// the winner is not measured a second time.
    @inlinable
    public static func fragments<Scalar: BinaryFloatingPoint, Failure: Swift::Error>(
        of triangles: some Swift::Sequence<InlineArray<3, Point<3, Scalar>>>,
        in region: Region,
        empty: Pixel,
        _ pixel: (_ triangle: Ordinal, _ depth: Scalar) throws(Failure) -> Pixel
    ) throws(Failure) -> Self {
        let nearest = nearest(of: triangles, in: region)
        let columns = Int(bitPattern: region.width)
        return try filled(columns: columns, rows: Int(bitPattern: region.height)) { (column, row) throws(Failure) in
            let winner = nearest.winners[row * columns + column]
            guard winner >= 0 else { return empty }
            return try pixel(Ordinal(UInt(winner)), nearest.depths[row * columns + column])
        }
    }

    /// The triangles made ready, and for each pixel of `region`, row by row, the position in the sequence of
    /// the nearest triangle that takes the pixel's centre, or -1 where none does, with its depth there.
    @inlinable
    internal static func nearest<Scalar: BinaryFloatingPoint>(
        of triangles: some Swift::Sequence<InlineArray<3, Point<3, Scalar>>>,
        in region: Region
    ) -> (facets: [Facet<Scalar>?], winners: [Int], depths: [Scalar]) {
        let columns = Int(bitPattern: region.width)
        let rows = Int(bitPattern: region.height)
        precondition(columns >= 0 && rows >= 0, "A raster's width and height fit a signed word")
        let (count, overflow) = columns.multipliedReportingOverflow(by: rows)
        precondition(!overflow, "A raster's pixel count fits a signed word")
        let left = origin(region.x)
        let top = origin(region.y)
        let half: Scalar = 1 / 2
        var facets: [Facet<Scalar>?] = []
        var winners = [Int](repeating: -1, count: count)
        var depths = [Scalar](repeating: 0, count: count)
        guard count > 0 else { return (facets, winners, depths) }
        for triangle in triangles {
            let number = facets.count
            let facet = Facet(triangle)
            facets.append(facet)
            guard let facet else { continue }
            let firstColumn = whole(facet.low.x - half, .down, from: left, to: left + columns)
            let endColumn = whole(facet.high.x - half, .up, from: left - 1, to: left + columns - 1) + 1
            let firstRow = whole(facet.low.y - half, .down, from: top, to: top + rows)
            let endRow = whole(facet.high.y - half, .up, from: top - 1, to: top + rows - 1) + 1
            guard firstColumn < endColumn, firstRow < endRow else { continue }
            var row = firstRow
            while row < endRow {
                let base = (row - top) * columns - left
                let y: Scalar = real(row) + half
                let span = facet.span(y: y, from: firstColumn, to: endColumn)
                var column = span.first
                while column < span.end {
                    if let sample = facet.sample(x: real(column) + half, y: y),
                        winners[base + column] < 0 || sample.depth < depths[base + column]
                    {
                        winners[base + column] = number
                        depths[base + column] = sample.depth
                    }
                    column += 1
                }
                row += 1
            }
        }
        return (facets, winners, depths)
    }

    /// `fragments(of:in:empty:_:)` over the whole raster of the given size.
    @inlinable
    public static func fragments<Scalar: BinaryFloatingPoint, Failure: Swift::Error>(
        of triangles: some Swift::Sequence<InlineArray<3, Point<3, Scalar>>>,
        width: Cardinal,
        height: Cardinal,
        empty: Pixel,
        _ pixel: (_ triangle: Ordinal, _ weights: InlineArray<3, Scalar>, _ depth: Scalar) throws(Failure) -> Pixel
    ) throws(Failure) -> Self {
        try fragments(of: triangles, in: Region(x: .zero, y: .zero, width: width, height: height), empty: empty, pixel)
    }

    /// `fragments(of:in:empty:_:)` without weights, over the whole raster of the given size.
    @inlinable
    public static func fragments<Scalar: BinaryFloatingPoint, Failure: Swift::Error>(
        of triangles: some Swift::Sequence<InlineArray<3, Point<3, Scalar>>>,
        width: Cardinal,
        height: Cardinal,
        empty: Pixel,
        _ pixel: (_ triangle: Ordinal, _ depth: Scalar) throws(Failure) -> Pixel
    ) throws(Failure) -> Self {
        try fragments(of: triangles, in: Region(x: .zero, y: .zero, width: width, height: height), empty: empty, pixel)
    }
}

#if Geometry
    extension Raster where Pixel: BinaryFloatingPoint {
        /// For each pixel of `region`, the part of its square that lies inside `path` under `rule`, from 0 to 1.
        /// The path is in raster space, and curves are made straight to within `tolerance` first.
        @inlinable
        public static func coverage<Scalar: BinaryFloatingPoint & Numeric.Transcendental, Space>(
            of path: Geometry<Scalar, Space>.Path,
            rule: Winding.Rule,
            in region: Region,
            tolerance: Geometry<Scalar, Space>.Length
        ) throws(Geometry<Scalar, Space>.Path.Error) -> Self {
            let outline = try path.flattened(tolerance: tolerance)
            let columns = Int(bitPattern: region.width)
            let rows = Int(bitPattern: region.height)
            precondition(columns >= 0 && rows >= 0, "A raster's width and height fit a signed word")
            let (count, overflow) = columns.multipliedReportingOverflow(by: rows)
            precondition(!overflow, "A raster's pixel count fits a signed word")
            guard count > 0 else { return Self(width: region.width, height: region.height, valid: []) }
            var sides: [Fill<Scalar>.Side] = []
            for subpath in outline.subpaths {
                var corners: [(x: Scalar, y: Scalar)] = [(subpath.startPoint[0], subpath.startPoint[1])]
                for segment in subpath.segments {
                    guard case .line(let line) = segment else { continue }
                    corners.append((line.start[0], line.start[1]))
                    corners.append((line.end[0], line.end[1]))
                }
                guard corners.allSatisfy({ $0.x.isFinite && $0.y.isFinite }), var previous = corners.last else { continue }
                for corner in corners {
                    if let side = Fill<Scalar>.Side(from: previous, to: corner) { sides.append(side) }
                    previous = corner
                }
            }
            let pixels = Fill<Scalar>.coverage(
                of: sides,
                rule: rule,
                left: origin(region.x),
                top: origin(region.y),
                columns: columns,
                rows: rows
            )
            return Self(width: region.width, height: region.height, valid: pixels)
        }

        /// `coverage(of:rule:in:tolerance:)` over the whole raster of the given size.
        @inlinable
        public static func coverage<Scalar: BinaryFloatingPoint & Numeric.Transcendental, Space>(
            of path: Geometry<Scalar, Space>.Path,
            rule: Winding.Rule,
            width: Cardinal,
            height: Cardinal,
            tolerance: Geometry<Scalar, Space>.Length
        ) throws(Geometry<Scalar, Space>.Path.Error) -> Self {
            try coverage(
                of: path,
                rule: rule,
                in: Region(x: .zero, y: .zero, width: width, height: height),
                tolerance: tolerance
            )
        }
    }
#endif
