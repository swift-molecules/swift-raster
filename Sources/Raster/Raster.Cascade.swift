extension Raster {
    /// The same extended box filter applied `count` times along one axis: each pass replaces a pixel by the
    /// mean of the `2 × radius + 1` pixels around it, with the two pixels just beyond weighted by `end`.
    /// A pass costs the same whatever its radius, because its sum slides along the line.
    public struct Cascade<Scalar: BinaryFloatingPoint> {
        public let count: Cardinal
        public let radius: Cardinal
        public let end: Scalar

        @inlinable
        public init(count: Cardinal, radius: Cardinal, end: Scalar) throws(Kernel<Scalar>.Error) {
            guard end.isFinite, end >= 0, end <= 1 else { throw .weight }
            self.count = count
            self.radius = radius
            self.end = end
        }
    }
}

extension Raster.Cascade: Equatable {}
extension Raster.Cascade: Hashable {}
extension Raster.Cascade: Sendable where Scalar: Sendable {}

extension Raster.Cascade {
    /// The cascade that changes nothing.
    @inlinable
    public static var identity: Self { Self(passes: .zero, radius: .zero, end: 0) }

    /// The cascade of `count` equal passes whose variance is `deviation` squared exactly: each pass takes a
    /// share `deviation² / count` of it, with the largest whole radius whose box alone stays below that share
    /// and `end` making up the rest.
    @inlinable
    public static func gaussian(deviation: Scalar, count: Cardinal = 5) throws(Raster.Kernel<Scalar>.Error) -> Self {
        let passes = Int(bitPattern: count)
        guard deviation.isFinite, deviation >= 0, passes > 0 else { throw .weight }
        guard deviation > 0 else { return .identity }
        let share = deviation * deviation / Scalar(passes)
        let radius = Int(((12 * share + 1).squareRoot() / 2 - Scalar(1) / 2).rounded(.down))
        let reach = Scalar(radius + 1)
        let inner = Scalar(radius) * reach * Scalar(2 * radius + 1) / 3
        let end = (share * Scalar(2 * radius + 1) - inner) / (2 * reach * reach - 2 * share)
        return try Self(count: count, radius: Cardinal(UInt(radius)), end: Swift.min(Swift.max(end, 0), 1))
    }

    /// How far the whole cascade reads beyond a pixel on each side.
    @inlinable
    public var reach: Cardinal { Cardinal(UInt(passes * (width + 1))) }

    /// The number of passes as a signed word.
    @inlinable
    internal var passes: Int { Int(bitPattern: count) }

    /// The radius of each pass as a signed word.
    @inlinable
    internal var width: Int { Int(bitPattern: radius) }

    /// The variance of the whole cascade, in squared pixels.
    @inlinable
    public var variance: Scalar {
        let reach = Scalar(width + 1)
        let inner = Scalar(width) * reach * Scalar(2 * width + 1) / 3
        return Scalar(passes) * (inner + 2 * end * reach * reach) / (Scalar(2 * width + 1) + 2 * end)
    }

    /// The weights of the whole cascade as one kernel, for comparing it with another.
    @inlinable
    public var kernel: Raster.Kernel<Scalar> {
        var box = [Scalar](repeating: 1, count: 2 * width + 3)
        box[0] = end
        box[2 * width + 2] = end
        let total = Scalar(2 * width + 1) + 2 * end
        box = box.map { $0 / total }
        var weights: [Scalar] = [1]
        var pass = 0
        while pass < passes {
            var next = [Scalar](repeating: 0, count: weights.count + 2 * width + 2)
            for (i, a) in zip(weights.indices, weights) {
                for (j, b) in zip(box.indices, box) { next[i + j] += a * b }
            }
            weights = next
            pass += 1
        }
        return Raster.Kernel(normalized: weights)
    }

    @inlinable
    internal init(passes: Cardinal, radius: Cardinal, end: Scalar) {
        self.count = passes
        self.radius = radius
        self.end = end
    }
}

extension Raster where Pixel: SIMD, Pixel.Scalar: BinaryFloatingPoint {
    /// Each pixel replaced by the cascade's weighted mean of its row neighbours, then the same down the
    /// columns of the result, reading beyond the raster through `edge`.
    @inlinable
    public func smoothed(
        horizontal: Cascade<Pixel.Scalar>,
        vertical: Cascade<Pixel.Scalar>,
        edge: Edge
    ) -> Self {
        guard !isEmpty else { return self }
        return smoothed(horizontal, down: false, edge: edge).smoothed(vertical, down: true, edge: edge)
    }

    /// One axis of `smoothed(horizontal:vertical:edge:)`. The lines are first lengthened by the cascade's
    /// reach through `edge`; each pass then shortens them by its own reach, so the last gives the raster's size.
    @inlinable
    internal func smoothed(_ cascade: Cascade<Pixel.Scalar>, down: Bool, edge: Edge) -> Self {
        guard cascade.passes > 0 else { return self }
        let reach = Int(bitPattern: cascade.reach)
        let radius = cascade.width
        let end = cascade.end
        let scale = Pixel.Scalar(1) / (Pixel.Scalar(2 * radius + 1) + 2 * end)
        let lines = down ? columns : rows
        let length = down ? rows : columns
        var result = storage
        var line = [Pixel](repeating: .zero, count: length + 2 * reach)
        var next = line
        var index = 0
        while index < lines {
            var position = 0
            while position < line.count {
                let along = position - reach
                line[position] = down ? self[column: index, row: along, edge: edge] : self[column: along, row: index, edge: edge]
                position += 1
            }
            var count = line.count
            var pass = 0
            while pass < cascade.passes {
                let kept = count - 2 * (radius + 1)
                var sum = Pixel.zero
                var tap = 1
                while tap <= 2 * radius + 1 {
                    sum += line[tap]
                    tap += 1
                }
                var at = 0
                while at < kept {
                    let centre = at + radius + 1
                    next[at] = (sum + end * (line[centre - radius - 1] + line[centre + radius + 1])) * scale
                    if at + 1 < kept {
                        sum += line[centre + radius + 1] - line[centre - radius]
                    }
                    at += 1
                }
                swap(&line, &next)
                count = kept
                pass += 1
            }
            position = 0
            while position < length {
                result[down ? position * columns + index : index * columns + position] = line[position]
                position += 1
            }
            index += 1
        }
        return Self(width: width, height: height, valid: result)
    }
}
