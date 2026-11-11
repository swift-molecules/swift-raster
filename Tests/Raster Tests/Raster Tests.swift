import Foundation
import Testing

#if Geometry
    import Angle
    import Numeric
    import Raster
#else
    public import Raster

    extension Double: @retroactive Exponential.`Protocol` {
        public static func exp(_ x: Double) -> Double { Foundation.exp(x) }
        public static func expm1(_ x: Double) -> Double { Foundation.expm1(x) }
        public static func exp2(_ x: Double) -> Double { Foundation.exp2(x) }
        public static func log(_ x: Double) -> Double { Foundation.log(x) }
        public static func log1p(_ x: Double) -> Double { Foundation.log1p(x) }
        public static func log2(_ x: Double) -> Double { Foundation.log2(x) }
        public static func log10(_ x: Double) -> Double { Foundation.log10(x) }
    }
#endif

enum `Raster Tests` {}

extension `Raster Tests` {
    /// An 8-bit level on a display's gamma-encoded scale: the type says what the number means.
    fileprivate struct Encoded: Hashable {
        var level: UInt8
    }

    /// Light on a linear scale, with coverage, colour already multiplied by it.
    fileprivate struct Light: Hashable {
        var amount: Double
        var coverage: Double
    }

    fileprivate struct Failure: Swift::Error, Equatable {}

    fileprivate static func mix(_ from: Double, _ to: Double, _ parameter: Double) -> Double {
        from + (to - from) * parameter
    }

    fileprivate static func mix(_ from: Light, _ to: Light, _ parameter: Double) -> Light {
        Light(amount: mix(from.amount, to.amount, parameter), coverage: mix(from.coverage, to.coverage, parameter))
    }

    fileprivate static func mix(_ from: Encoded, _ to: Encoded, _ parameter: Double) -> Encoded {
        Encoded(level: UInt8(mix(Double(from.level), Double(to.level), parameter).rounded()))
    }

    /// A raster whose pixel at (x, y) is `10 * y + x`, so every pixel names its own position.
    fileprivate static func grid(_ width: Cardinal, _ height: Cardinal) -> Raster<Double> {
        Raster(width: width, height: height) { x, y in Double(10 * Int(bitPattern: y) + Int(bitPattern: x)) }
    }

    /// A raster of varied values, the same every time.
    fileprivate static func varied(_ width: Cardinal, _ height: Cardinal) -> Raster<Double> {
        Raster(width: width, height: height) { x, y in
            Double((Int(bitPattern: x) * 7 + Int(bitPattern: y) * 13 + Int(bitPattern: x) * Int(bitPattern: y) * 5) % 17)
        }
    }

    fileprivate static func close(_ first: Raster<Double>, _ second: Raster<Double>, within tolerance: Double = 1e-12) -> Bool {
        first.zip(second) { abs($0 - $1) <= tolerance }?.reduce(true) { $0 && $1 } ?? false
    }

    fileprivate static func mean(_ raster: Raster<Double>) -> Double {
        raster.reduce(0, +) / Double(raster.pixels.count)
    }
}

extension `Raster Tests` {
    @Suite
    struct Storage {
        @Test
        func `A raster holds width times height pixels, row by row`() throws {
            let raster = try Raster(width: 3, height: 2, pixels: ["a", "b", "c", "d", "e", "f"])
            #expect(raster.width == 3 && raster.height == 2)
            #expect(raster[x: 0, y: 0] == "a")
            #expect(raster[x: 2, y: 0] == "c")
            #expect(raster[x: 0, y: 1] == "d")
            #expect(Array(raster.row(1)) == ["d", "e", "f"])
            #expect(throws: Raster<String>.Error.count) { try Raster(width: 3, height: 2, pixels: ["a"]) }
            #expect(throws: Raster<String>.Error.count) {
                try Raster(width: 4_294_967_296, height: 4_294_967_296, pixels: [String]())
            }
        }

        @Test
        func `A raster is built from one pixel or from a function of position, in row order`() {
            #expect(Raster(width: 2, height: 2, repeating: 7).pixels == [7, 7, 7, 7])
            var visited: [String] = []
            let raster = Raster(width: 2, height: 2) { x, y in
                visited.append("\(x),\(y)")
                return Int(bitPattern: x) + 10 * Int(bitPattern: y)
            }
            #expect(raster.pixels == [0, 1, 10, 11])
            #expect(visited == ["0,0", "1,0", "0,1", "1,1"])
        }

        @Test
        func `A raster with no columns or no rows is valid and empty`() throws {
            let flat = try Raster(width: 5, height: 0, pixels: [Int]())
            #expect(flat.isEmpty && flat.width == 5 && flat.height == 0)
            #expect(Raster(width: 0, height: 3, repeating: 1).isEmpty)
            #expect(flat != Raster(width: 0, height: 5, repeating: 0))
            #expect(flat.map { $0 + 1 } == flat)
        }

        @Test
        func `A pixel is replaced in place and equality compares size and pixels`() {
            var raster = `Raster Tests`.grid(3, 2)
            let before = raster
            raster[x: 1, y: 1] = 99
            #expect(raster.pixels == [0, 1, 2, 10, 99, 12])
            #expect(raster != before)
            raster[x: 1, y: 1] = 11
            #expect(raster == before)
            #expect(Raster(width: 2, height: 3, repeating: 0) != Raster(width: 3, height: 2, repeating: 0))
        }

        @Test
        func `Cropping keeps a region and refuses one that leaves the raster`() throws {
            let raster = `Raster Tests`.grid(4, 3)
            let part = try raster.cropped(to: Raster.Region(x: 1, y: 1, width: 2, height: 2))
            #expect(part.pixels == [11, 12, 21, 22])
            #expect(try raster.cropped(to: Raster.Region(x: 0, y: 0, width: 4, height: 3)) == raster)
            #expect(try raster.cropped(to: Raster.Region(x: 4, y: 3, width: 0, height: 0)).isEmpty)
            #expect(throws: Raster<Double>.Error.bounds) {
                try raster.cropped(to: Raster.Region(x: 3, y: 0, width: 2, height: 1))
            }
            #expect(throws: Raster<Double>.Error.bounds) {
                try raster.cropped(to: Raster.Region(x: 0, y: 2, width: 1, height: 2))
            }
            #expect(throws: Raster<Double>.Error.bounds) {
                try raster.cropped(to: Raster.Region(x: 1, y: 0, width: 18_446_744_073_709_551_615, height: 1))
            }
        }

        @Test
        func `Replacing a region puts another raster there and changes nothing else`() throws {
            let raster = `Raster Tests`.grid(4, 3)
            let patch = Raster(width: 2, height: 2, repeating: -1.0)
            let replaced = try raster.replacing(x: 2, y: 1, with: patch)
            #expect(replaced.pixels == [0, 1, 2, 3, 10, 11, -1, -1, 20, 21, -1, -1])
            #expect(try replaced.cropped(to: Raster.Region(x: 2, y: 1, width: 2, height: 2)) == patch)
            let back = try replaced.replacing(
                x: 2,
                y: 1,
                with: raster.cropped(to: Raster.Region(x: 2, y: 1, width: 2, height: 2))
            )
            #expect(back == raster)
            #expect(throws: Raster<Double>.Error.bounds) { try raster.replacing(x: 3, y: 0, with: patch) }
            #expect(throws: Raster<Double>.Error.bounds) { try raster.replacing(x: 0, y: 2, with: patch) }
        }
    }
}

extension `Raster Tests` {
    @Suite
    struct Traversal {
        @Test
        func `Mapping visits every pixel in row order, keeps the size and may change the pixel type`() {
            let encoded = Raster(width: 2, height: 2) { x, y in
                Encoded(level: UInt8(100 * y.rawValue + 50 * x.rawValue))
            }
            let light = encoded.map { Light(amount: Double($0.level) / 255, coverage: 1) }
            #expect(light.width == 2 && light.height == 2)
            let amounts: [Double] = [0, 50, 100, 150].map { $0 / 255 }
            #expect(light.pixels.map(\.amount) == amounts)
            #expect(light.map { Encoded(level: UInt8(($0.amount * 255).rounded())) } == encoded)
        }

        @Test
        func `Mapping stops at the first typed failure`() {
            var visited: [Double] = []
            func transform(_ value: Double) throws(Failure) -> Double {
                visited.append(value)
                if value == 2 { throw Failure() }
                return value
            }
            #expect(throws: Failure()) { try `Raster Tests`.grid(3, 2).map(transform) }
            #expect(visited == [0, 1, 2])
        }

        @Test
        func `Zipping combines two rasters pixel by pixel and answers nil when their sizes differ`() {
            let first = `Raster Tests`.grid(3, 2)
            let second = Raster(width: 3, height: 2, repeating: "x")
            let zipped = first.zip(second) { "\(Int($0))\($1)" }
            #expect(zipped?.pixels == ["0x", "1x", "2x", "10x", "11x", "12x"])
            #expect(first.zip(Raster(width: 2, height: 3, repeating: 0.0), +) == nil)
            #expect(first.zip(Raster(width: 3, height: 1, repeating: 0.0), +) == nil)
            #expect(first.zip(first, -) == Raster(width: 3, height: 2, repeating: 0))
            func refuse(_ first: Double, _ second: Double) throws(Failure) -> Double { throw Failure() }
            #expect(throws: Failure()) { try first.zip(first, refuse) }
        }

        @Test
        func `Reducing folds the pixels in row order`() {
            let raster = `Raster Tests`.grid(2, 2)
            #expect(raster.reduce("") { $0 + "\(Int($1))," } == "0,1,10,11,")
            #expect(raster.reduce(into: [Double]()) { $0.append($1) } == raster.pixels)
            #expect(raster.reduce(0, +) == 22)
            #expect(Raster<Double>(width: 0, height: 0, repeating: 1).reduce(5, +) == 5)
            func refuse(_ sum: Double, _ pixel: Double) throws(Failure) -> Double { throw Failure() }
            #expect(throws: Failure()) { try raster.reduce(0, refuse) }
        }
    }
}

extension `Raster Tests` {
    @Suite
    struct Sampling {
        @Test
        func `Sampling a pixel centre gives that pixel without interpolating, under both samplings`() {
            let raster = `Raster Tests`.grid(3, 3)
            var calls = 0
            func counting(_ from: Double, _ to: Double, _ parameter: Double) -> Double {
                calls += 1
                return .nan
            }
            let positions: [(x: Ordinal, y: Ordinal)] = [(0, 0), (1, 0), (2, 0), (0, 1), (1, 1), (2, 1), (0, 2), (1, 2), (2, 2)]
            for (x, y) in positions {
                let centre = Point(x: Double(x.rawValue) + 0.5, y: Double(y.rawValue) + 0.5)
                #expect(raster.sample(at: centre, .nearest, edge: .extend, mixing: counting) == raster[x: x, y: y])
                #expect(raster.sample(at: centre, .bilinear, edge: .extend, mixing: counting) == raster[x: x, y: y])
            }
            #expect(calls == 0)
        }

        @Test
        func `Nearest sampling gives the pixel whose square holds the point, the lower edges included`() {
            let raster = `Raster Tests`.grid(3, 2)
            func nearest(_ x: Double, _ y: Double) -> Double {
                raster.sample(at: Point(x: x, y: y), .nearest, edge: .constant(-1), mixing: `Raster Tests`.mix)
            }
            #expect(nearest(0, 0) == 0)
            #expect(nearest(0.999, 0.999) == 0)
            #expect(nearest(1, 0) == 1)
            #expect(nearest(2.999, 1.999) == 12)
            #expect(nearest(3, 1) == -1)
            #expect(nearest(-0.001, 0) == -1)
            #expect(nearest(0, 2) == -1)
        }

        @Test
        func `Bilinear sampling is linear between neighbouring centres and the mean where four pixels meet`() {
            let raster = `Raster Tests`.varied(4, 4)
            func bilinear(_ x: Double, _ y: Double) -> Double {
                raster.sample(at: Point(x: x, y: y), .bilinear, edge: .extend, mixing: `Raster Tests`.mix)
            }
            let (a, b, c, d) = (raster[x: 1, y: 1], raster[x: 2, y: 1], raster[x: 1, y: 2], raster[x: 2, y: 2])
            #expect(bilinear(2, 1.5) == (a + b) / 2)
            #expect(bilinear(1.75, 1.5) == a + (b - a) / 4)
            #expect(bilinear(1.5, 2) == (a + c) / 2)
            #expect(bilinear(2, 2) == (a + b + c + d) / 4)
            let step = 1.0 / 1024
            #expect(abs(bilinear(2.5 - step, 2.5 - step) - d) < 0.05)
            #expect(abs(bilinear(2.5 + step, 2.5 + step) - d) < 0.05)
        }

        @Test
        func `Each edge says which pixel stands for a position outside the raster`() throws {
            let raster = try Raster(width: 3, height: 1, pixels: ["a", "b", "c"])
            func outside(_ edge: Raster<String>.Edge) -> String {
                (-6..<9).map { column in
                    raster.sample(at: Point(x: Double(column) + 0.5, y: 0.5), .nearest, edge: edge) { first, _, _ in first }
                }
                .joined()
            }
            #expect(outside(.extend) == "aaaaaaabccccccc")
            #expect(outside(.wrap) == "abcabcabcabcabc")
            #expect(outside(.mirror) == "abccbaabccbaabc")
            #expect(outside(.constant("-")) == "------abc------")
        }

        @Test
        func `An edge applies to rows as it does to columns, and to bilinear neighbours`() {
            let raster = `Raster Tests`.grid(2, 2)
            func bilinear(_ x: Double, _ y: Double, _ edge: Raster<Double>.Edge) -> Double {
                raster.sample(at: Point(x: x, y: y), .bilinear, edge: edge, mixing: `Raster Tests`.mix)
            }
            #expect(bilinear(0, 0, .extend) == 0)
            #expect(bilinear(0, 0, .mirror) == 0)
            #expect(bilinear(0, 0.5, .wrap) == 0.5)
            #expect(bilinear(0.5, 0, .wrap) == 5)
            #expect(bilinear(0, 0, .wrap) == 5.5)
            #expect(bilinear(0, 0, .constant(100)) == 75)
            #expect(bilinear(2, 2, .constant(100)) == 77.75)
        }

        @Test
        func `Only a constant edge can answer for an empty raster`() {
            let empty = Raster(width: 0, height: 4, repeating: 0.0)
            let sample = empty.sample(at: Point(x: 1.25, y: 1.5), .bilinear, edge: .constant(3), mixing: `Raster Tests`.mix)
            #expect(sample == 3)
        }
    }
}

extension `Raster Tests` {
    @Suite
    struct Warping {
        @Test
        func `Warping by the identity returns the raster under both samplings`() {
            let raster = `Raster Tests`.varied(5, 4)
            let identity = Matrix<2, 3, Double>(rows: [[1, 0, 0], [0, 1, 0]])
            for sampling in [Raster<Double>.Sampling.nearest, .bilinear] {
                let warped = raster.warped(width: 5, height: 4, sampling, edge: .extend, mixing: `Raster Tests`.mix) { $0 }
                #expect(warped == raster)
                let mapped = raster.warped(by: identity, width: 5, height: 4, sampling, edge: .extend, mixing: `Raster Tests`.mix)
                #expect(mapped == raster)
            }
        }

        @Test
        func `The map gives the source point each destination pixel shows`() {
            let raster = `Raster Tests`.grid(3, 2)
            let shifted = Matrix<2, 3, Double>(rows: [[1, 0, -1], [0, 1, 0]])
            let moved = raster.warped(by: shifted, width: 3, height: 2, .bilinear, edge: .constant(-1), mixing: `Raster Tests`.mix)
            #expect(moved.pixels == [-1, 0, 1, -1, 10, 11])
            let halved = Matrix<2, 3, Double>(rows: [[0.5, 0, 0], [0, 0.5, 0]])
            let doubled = raster.warped(by: halved, width: 6, height: 4, .nearest, edge: .extend, mixing: `Raster Tests`.mix)
            #expect(doubled.pixels == [0, 0, 1, 1, 2, 2, 0, 0, 1, 1, 2, 2, 10, 10, 11, 11, 12, 12, 10, 10, 11, 11, 12, 12])
        }

        @Test
        func `A quarter turn about the centre permutes the pixels of a square exactly`() {
            let raster = `Raster Tests`.grid(3, 3)
            let turn = Matrix<2, 3, Double>(rows: [[0, 1, 0], [-1, 0, 3]])
            let turned = raster.warped(by: turn, width: 3, height: 3, .bilinear, edge: .extend, mixing: `Raster Tests`.mix)
            #expect(turned.pixels == [20, 10, 0, 21, 11, 1, 22, 12, 2])
            var back = turned
            for _ in 0..<3 {
                back = back.warped(by: turn, width: 3, height: 3, .bilinear, edge: .extend, mixing: `Raster Tests`.mix)
            }
            #expect(back == raster)
        }

        @Test
        func `Warping to a window is cropping, and any function of the plane is a warp`() throws {
            let raster = `Raster Tests`.varied(6, 5)
            let window = Matrix<2, 3, Double>(rows: [[1, 0, 2], [0, 1, 1]])
            let warped = raster.warped(by: window, width: 3, height: 2, .bilinear, edge: .extend, mixing: `Raster Tests`.mix)
            #expect(try warped == raster.cropped(to: Raster.Region(x: 2, y: 1, width: 3, height: 2)))
            let flipped = raster.warped(width: 6, height: 5, .nearest, edge: .extend, mixing: `Raster Tests`.mix) { point in
                Point(x: 6 - point.x, y: point.y)
            }
            #expect(Array(flipped.row(2)) == raster.row(2).reversed())
            func refuse(_ point: Point<2, Double>) throws(Failure) -> Point<2, Double> { throw Failure() }
            func plain(_ from: Double, _ to: Double, _ parameter: Double) throws(Failure) -> Double { from }
            #expect(throws: Failure()) {
                try raster.warped(width: 1, height: 1, .nearest, edge: .extend, mixing: plain, from: refuse)
            }
        }
    }
}

extension `Raster Tests` {
    @Suite
    struct Resampling {
        fileprivate static let filters: [Raster<Double>.Filter] = [.nearest, .box, .triangle]

        @Test
        func `Resampling to the same size returns the raster under every filter`() {
            let raster = `Raster Tests`.varied(7, 5)
            for filter in Self.filters {
                #expect(raster.resampled(width: 7, height: 5, filter, mixing: `Raster Tests`.mix) == raster)
            }
        }

        @Test
        func `A constant raster stays exactly constant at any size under every filter`() {
            let raster = Raster(width: 7, height: 5, repeating: 0.1)
            for filter in Self.filters {
                for (width, height) in [(3, 2), (13, 11), (1, 1), (7, 20)] as [(Cardinal, Cardinal)] {
                    let resampled = raster.resampled(width: width, height: height, filter, mixing: `Raster Tests`.mix)
                    #expect(resampled == Raster(width: width, height: height, repeating: 0.1))
                }
            }
        }

        @Test
        func `Shrinking with the box filter by a whole factor gives each block's mean`() {
            let raster = `Raster Tests`.varied(6, 4)
            let shrunk = raster.resampled(width: 3, height: 2, .box, mixing: `Raster Tests`.mix)
            let means = Raster(width: 3, height: 2) { x, y in
                let left = Ordinal(2 * x.rawValue)
                let top = Ordinal(2 * y.rawValue)
                let right = Ordinal(2 * x.rawValue + 1)
                let bottom = Ordinal(2 * y.rawValue + 1)
                let upper: Double = raster[x: left, y: top] + raster[x: right, y: top]
                let lower: Double = raster[x: left, y: bottom] + raster[x: right, y: bottom]
                return (upper + lower) / 4
            }
            #expect(`Raster Tests`.close(shrunk, means))
            let one = raster.resampled(width: 1, height: 1, .box, mixing: `Raster Tests`.mix)
            #expect(abs(one.pixels[0] - `Raster Tests`.mean(raster)) < 1e-12)
        }

        @Test
        func `Enlarging by a whole factor repeats pixels under the nearest and box filters`() {
            let raster = `Raster Tests`.grid(2, 2)
            let repeated: [Double] = [0, 0, 0, 1, 1, 1, 0, 0, 0, 1, 1, 1, 10, 10, 10, 11, 11, 11, 10, 10, 10, 11, 11, 11]
            #expect(raster.resampled(width: 6, height: 4, .nearest, mixing: `Raster Tests`.mix).pixels == repeated)
            #expect(raster.resampled(width: 6, height: 4, .box, mixing: `Raster Tests`.mix).pixels == repeated)
        }

        @Test
        func `Enlarging with the triangle filter is bilinear sampling at each new centre, the border extended`() {
            let raster = `Raster Tests`.varied(4, 3)
            let enlarged = raster.resampled(width: 10, height: 9, .triangle, mixing: `Raster Tests`.mix)
            let sampled = Raster(width: 10, height: 9) { x, y in
                let point = Point(x: (Double(x.rawValue) + 0.5) * 4 / 10, y: (Double(y.rawValue) + 0.5) * 3 / 9)
                return raster.sample(at: point, .bilinear, edge: .extend, mixing: `Raster Tests`.mix)
            }
            #expect(`Raster Tests`.close(enlarged, sampled))
        }

        @Test
        func `Shrinking with the triangle filter weighs neighbours by distance over a wider reach`() throws {
            let raster = try Raster(width: 4, height: 1, pixels: [0.0, 0, 8, 8])
            let shrunk = raster.resampled(width: 2, height: 1, .triangle, mixing: `Raster Tests`.mix)
            #expect(`Raster Tests`.close(shrunk, try Raster(width: 2, height: 1, pixels: [8.0 / 7, 48.0 / 7])))
        }

        @Test
        func `No filter leaves the range of the pixels it averages`() {
            let raster = `Raster Tests`.varied(9, 7)
            for filter in Self.filters {
                for (width, height) in [(4, 3), (20, 15), (9, 2)] as [(Cardinal, Cardinal)] {
                    let resampled = raster.resampled(width: width, height: height, filter, mixing: `Raster Tests`.mix)
                    #expect(resampled.pixels.allSatisfy { $0 >= 0 && $0 <= 16 })
                }
            }
        }

        @Test
        func `Resampling to no columns or no rows gives an empty raster`() {
            let raster = `Raster Tests`.grid(3, 3)
            let none = raster.resampled(width: 0, height: 4, .box, mixing: `Raster Tests`.mix)
            #expect(none.isEmpty && none.width == 0 && none.height == 4)
            let empty = Raster(width: 0, height: 0, repeating: 0.0)
            #expect(empty.resampled(width: 3, height: 0, .triangle, mixing: `Raster Tests`.mix).isEmpty)
        }

        @Test
        func `Eight-bit encoded pixels resample with their own interpolation`() throws {
            let raster = try Raster(width: 4, height: 1, pixels: [0, 100, 200, 255].map { Encoded(level: $0) })
            let shrunk = raster.resampled(width: 2, height: 1, .box, mixing: `Raster Tests`.mix)
            #expect(shrunk.pixels.map(\.level) == [50, 228])
        }
    }
}

extension `Raster Tests` {
    @Suite
    struct Convolution {
        fileprivate static let edges: [Raster<Double>.Edge] = [.extend, .wrap, .mirror, .constant(0.1)]

        @Test
        func `A kernel has an odd number of non-negative weights and is normalised when built`() throws {
            let kernel = try Raster<Double>.Kernel(weights: [1.0, 2, 1])
            #expect(kernel.weights == [0.25, 0.5, 0.25])
            #expect(kernel.radius == 1)
            #expect(throws: Raster<Double>.Kernel<Double>.Error.empty) { try Raster<Double>.Kernel(weights: [Double]()) }
            #expect(throws: Raster<Double>.Kernel<Double>.Error.even) { try Raster<Double>.Kernel(weights: [1.0, 1]) }
            #expect(throws: Raster<Double>.Kernel<Double>.Error.weight) { try Raster<Double>.Kernel(weights: [1.0, -1, 1]) }
            #expect(throws: Raster<Double>.Kernel<Double>.Error.weight) { try Raster<Double>.Kernel(weights: [1.0, .nan, 1]) }
            #expect(throws: Raster<Double>.Kernel<Double>.Error.weight) { try Raster<Double>.Kernel(weights: [Double.infinity]) }
            #expect(throws: Raster<Double>.Kernel<Double>.Error.zero) { try Raster<Double>.Kernel(weights: [0.0, 0, 0]) }
            #expect(Raster<Double>.Kernel<Double>.identity.weights == [1])
            #expect(Raster<Double>.Kernel<Double>.box(radius: 2).weights == [0.2, 0.2, 0.2, 0.2, 0.2])
            #expect(Raster<Double>.Kernel<Double>.box(radius: 0) == .identity)
        }

        @Test
        func `A Gaussian kernel is symmetric, peaks at its centre, sums to one and reaches three deviations`() throws {
            let kernel = try Raster<Double>.Kernel<Double>.gaussian(deviation: 1.5)
            #expect(kernel.radius == 5)
            #expect(kernel.weights == kernel.weights.reversed())
            #expect(abs(kernel.weights.reduce(0, +) - 1) < 1e-15)
            #expect(zip(kernel.weights.prefix(5), kernel.weights.dropFirst().prefix(5)).allSatisfy { $0 < $1 })
            #expect(abs(kernel.weights[4] / kernel.weights[5] - Foundation.exp(-1 / 4.5)) < 1e-15)
            #expect(try Raster<Double>.Kernel<Double>.gaussian(deviation: 2, radius: 1).weights.count == 3)
            #expect(try Raster<Double>.Kernel<Double>.gaussian(deviation: 0) == .identity)
            #expect(throws: Raster<Double>.Kernel<Double>.Error.weight) {
                try Raster<Double>.Kernel<Double>.gaussian(deviation: -1)
            }
            #expect(throws: Raster<Double>.Kernel<Double>.Error.weight) {
                try Raster<Double>.Kernel<Double>.gaussian(deviation: .nan)
            }
        }

        @Test
        func `Convolving with the one-weight kernel returns the raster without interpolating`() {
            let raster = `Raster Tests`.varied(5, 4)
            func never(_ from: Double, _ to: Double, _ parameter: Double) -> Double { .nan }
            #expect(raster.convolved(horizontal: .identity, vertical: .identity, edge: .wrap, mixing: never) == raster)
        }

        @Test
        func `The response to a single bright pixel is the kernel, across and down`() throws {
            var raster = Raster(width: 7, height: 7, repeating: 0.0)
            raster[x: 3, y: 3] = 1
            let across = try Raster<Double>.Kernel(weights: [1.0, 2, 5])
            let down = try Raster<Double>.Kernel(weights: [3.0, 1, 0])
            let blurred = raster.convolved(horizontal: across, vertical: down, edge: .extend, mixing: `Raster Tests`.mix)
            let expected = Raster(width: 7, height: 7) { x, y in
                let column = 3 - Int(bitPattern: x) + 1
                let row = 3 - Int(bitPattern: y) + 1
                guard (0..<3).contains(column), (0..<3).contains(row) else { return 0.0 }
                return across.weights[column] * down.weights[row]
            }
            #expect(`Raster Tests`.close(blurred, expected, within: 1e-15))
        }

        @Test
        func `A constant raster stays exactly constant under every kernel and edge that shows the same constant`() throws {
            let raster = Raster(width: 6, height: 5, repeating: 0.1)
            let gaussian = try Raster<Double>.Kernel<Double>.gaussian(deviation: 1.7)
            for edge in Self.edges {
                let blurred = raster.convolved(horizontal: gaussian, vertical: .box(radius: 4), edge: edge, mixing: `Raster Tests`.mix)
                #expect(blurred == raster)
            }
        }

        @Test
        func `Each edge supplies the pixels a kernel reaches for beyond the border`() throws {
            let raster = try Raster(width: 4, height: 1, pixels: [3.0, 0, 0, 9])
            func blurred(_ edge: Raster<Double>.Edge) -> Raster<Double> {
                raster.convolved(horizontal: .box(radius: 1), vertical: .identity, edge: edge, mixing: `Raster Tests`.mix)
            }
            #expect(`Raster Tests`.close(blurred(.extend), try Raster(width: 4, height: 1, pixels: [2.0, 1, 3, 6])))
            #expect(`Raster Tests`.close(blurred(.mirror), try Raster(width: 4, height: 1, pixels: [2.0, 1, 3, 6])))
            #expect(`Raster Tests`.close(blurred(.wrap), try Raster(width: 4, height: 1, pixels: [4.0, 1, 3, 4])))
            #expect(`Raster Tests`.close(blurred(.constant(6)), try Raster(width: 4, height: 1, pixels: [3.0, 1, 3, 5])))
            let column = try Raster(width: 1, height: 4, pixels: [3.0, 0, 0, 9])
            let down = column.convolved(horizontal: .identity, vertical: .box(radius: 1), edge: .wrap, mixing: `Raster Tests`.mix)
            #expect(`Raster Tests`.close(down, try Raster(width: 1, height: 4, pixels: [4.0, 1, 3, 4])))
            let wide = column.convolved(horizontal: .box(radius: 1), vertical: .identity, edge: .constant(0), mixing: `Raster Tests`.mix)
            #expect(`Raster Tests`.close(wide, try Raster(width: 1, height: 4, pixels: [1.0, 0, 0, 3])))
        }

        @Test
        func `With the wrapping edge a convolution keeps the mean`() throws {
            let raster = `Raster Tests`.varied(8, 6)
            let gaussian = try Raster<Double>.Kernel<Double>.gaussian(deviation: 1.2)
            let blurred = raster.convolved(horizontal: gaussian, vertical: .box(radius: 2), edge: .wrap, mixing: `Raster Tests`.mix)
            #expect(abs(`Raster Tests`.mean(blurred) - `Raster Tests`.mean(raster)) < 1e-12)
            #expect(blurred != raster)
        }

        @Test
        func `Convolving across then down equals down then across, and no result leaves the range of the pixels`() throws {
            let raster = `Raster Tests`.varied(8, 6)
            let across = try Raster<Double>.Kernel<Double>.gaussian(deviation: 0.9)
            let down = Raster<Double>.Kernel<Double>.box(radius: 1)
            for edge in Self.edges {
                let both = raster.convolved(horizontal: across, vertical: down, edge: edge, mixing: `Raster Tests`.mix)
                let first = raster.convolved(horizontal: across, vertical: .identity, edge: edge, mixing: `Raster Tests`.mix)
                    .convolved(horizontal: .identity, vertical: down, edge: edge, mixing: `Raster Tests`.mix)
                let second = raster.convolved(horizontal: .identity, vertical: down, edge: edge, mixing: `Raster Tests`.mix)
                    .convolved(horizontal: across, vertical: .identity, edge: edge, mixing: `Raster Tests`.mix)
                #expect(both == first)
                #expect(`Raster Tests`.close(first, second))
                #expect(both.pixels.allSatisfy { $0 >= 0 && $0 <= 16 })
            }
        }

        @Test
        func `Pixels of several channels and eight-bit pixels blur with their own interpolation`() throws {
            var light = Raster(width: 3, height: 1, repeating: Light(amount: 0, coverage: 0))
            light[x: 1, y: 0] = Light(amount: 0.6, coverage: 0.9)
            let blurred = light.convolved(horizontal: .box(radius: 1), vertical: .identity, edge: .extend, mixing: `Raster Tests`.mix)
            #expect(blurred.pixels.allSatisfy { abs($0.amount - 0.2) < 1e-15 && abs($0.coverage - 0.3) < 1e-15 })
            let encoded = try Raster(width: 3, height: 1, pixels: [0, 90, 255].map { Encoded(level: $0) })
            let soft = encoded.convolved(horizontal: .box(radius: 1), vertical: .identity, edge: .extend, mixing: `Raster Tests`.mix)
            #expect(soft.pixels.map(\.level) == [30, 115, 200])
        }

        @Test
        func `A convolution stops at the first typed failure and leaves an empty raster as it is`() {
            func refuse(_ from: Double, _ to: Double, _ parameter: Double) throws(Failure) -> Double { throw Failure() }
            #expect(throws: Failure()) {
                try `Raster Tests`.grid(3, 3).convolved(horizontal: .box(radius: 1), vertical: .identity, edge: .extend, mixing: refuse)
            }
            let empty = Raster(width: 0, height: 2, repeating: 0.0)
            #expect(empty.convolved(horizontal: .box(radius: 1), vertical: .identity, edge: .extend, mixing: `Raster Tests`.mix) == empty)
        }
    }
}

extension `Raster Tests` {
    @Suite
    struct `Two rasters of one size are compared by their mean error` {}
}

extension `Raster Tests`.`Two rasters of one size are compared by their mean error` {
    private static func squared(_ a: Double, _ b: Double) -> Double { (a - b) * (a - b) }

    @Test
    func `the mean error is the sum over pixels divided by their number`() throws {
        let a = try Raster<Double>(width: 2, height: 2, pixels: [0, 1, 2, 3])
        let b = try Raster<Double>(width: 2, height: 2, pixels: [0, 3, 2, 7])
        #expect(a.mean(against: b, Self.squared) == 5)
        #expect(a.mean(against: a, Self.squared) == 0)
        #expect(a.mean(against: Raster<Double>(width: 4, height: 1, repeating: 0), Self.squared) == nil)
        let empty = Raster<Double>(width: 0, height: 0, repeating: 0)
        #expect(empty.mean(against: empty, Self.squared) == nil)
    }

    @Test
    func `the ratio is ten log ten of the peak squared over the mean squared error`() throws {
        let a = try Raster<Double>(width: 2, height: 1, pixels: [0, 0])
        let b = try Raster<Double>(width: 2, height: 1, pixels: [25.5, 25.5])
        #expect(a.psnr(against: b, peak: 255, squared: Self.squared) == 20)
        #expect(a.psnr(against: b, peak: 2550, squared: Self.squared) == 40)
        #expect(a.psnr(against: a, peak: 255, squared: Self.squared) == .infinity)
        #expect(a.psnr(against: Raster<Double>(width: 1, height: 2, repeating: 0), peak: 255, squared: Self.squared) == nil)
        let empty = Raster<Double>(width: 0, height: 0, repeating: 0)
        #expect(empty.psnr(against: empty, peak: 255, squared: Self.squared) == .infinity)
    }
}

extension `Raster Tests` {
    @Suite
    struct `Triangles are sampled at pixel centres, nearest first` {}
}

extension `Raster Tests`.`Triangles are sampled at pixel centres, nearest first` {
    fileprivate typealias Triangle = InlineArray<3, Point<3, Double>>
    fileprivate typealias Corner = (x: Double, y: Double, z: Double)

    /// What a caller might keep of a fragment.
    fileprivate struct Hit: Equatable {
        var triangle: Ordinal
        var weights: [Double]
        var depth: Double
    }

    fileprivate static func hits(_ triangles: [Triangle], _ width: Cardinal, _ height: Cardinal) -> Raster<Hit?> {
        Raster<Hit?>.fragments(of: triangles, width: width, height: height, empty: nil) { triangle, weights, depth in
            Hit(triangle: triangle, weights: [weights[0], weights[1], weights[2]], depth: depth)
        }
    }

    fileprivate static func triangle(_ a: Corner, _ b: Corner, _ c: Corner) -> Triangle {
        [Point(x: a.x, y: a.y, z: a.z), Point(x: b.x, y: b.y, z: b.z), Point(x: c.x, y: c.y, z: c.z)]
    }

    /// Which triangle takes each pixel, and −1 where none does.
    fileprivate static func owners(_ triangles: [Triangle], _ width: Cardinal, _ height: Cardinal) -> Raster<Int> {
        Raster<Int>.fragments(of: triangles, width: width, height: height, empty: -1) { triangle, _, _ in
            Int(bitPattern: triangle)
        }
    }

    /// How many of the triangles, each sampled alone, take each pixel.
    fileprivate static func claims(_ triangles: [Triangle], _ width: Cardinal, _ height: Cardinal) -> Raster<Int> {
        var counts = Raster<Int>(width: width, height: height, repeating: 0)
        triangles.forEach { triangle in
            let alone = Raster<Int>.fragments(of: [triangle], width: width, height: height, empty: 0) { _, _, _ in 1 }
            counts = counts.zip(alone, +) ?? counts
        }
        return counts
    }

    fileprivate static let orders: [[Int]] = [[0, 1, 2], [1, 2, 0], [2, 0, 1], [0, 2, 1], [2, 1, 0], [1, 0, 2]]

    @Test
    func `a triangle takes the centres inside it and, of those on an edge, only the ones on a left or top edge`() throws {
        let corners: [Corner] = [(0, 0, 0), (4, 0, 0), (0, 4, 0)]
        let expected = try Raster<Int>(width: 4, height: 4, pixels: [0, 0, 0, -1, 0, 0, -1, -1, 0, -1, -1, -1, -1, -1, -1, -1])
        Self.orders.forEach { order in
            let listed = Self.triangle(corners[order[0]], corners[order[1]], corners[order[2]])
            #expect(Self.owners([listed], 4, 4) == expected, "corners in order \(order)")
        }
        // A square from centre (0.5, 0.5) to centre (2.5, 2.5): its left and top edges take their centres,
        // its right and bottom edges do not.
        let square = [
            Self.triangle((0.5, 0.5, 0), (2.5, 0.5, 0), (2.5, 2.5, 0)),
            Self.triangle((0.5, 0.5, 0), (2.5, 2.5, 0), (0.5, 2.5, 0)),
        ]
        let taken = Self.owners(square, 4, 4).map { $0 >= 0 }
        #expect(taken.pixels == [true, true, false, false, true, true, false, false] + [Bool](repeating: false, count: 8))
    }

    @Test
    func `two triangles that share an edge take every centre on it exactly once, however their corners are listed`() {
        let corners: [Corner] = [(0, 0, 0), (4, 0, 0), (4, 4, 0), (0, 4, 0)]
        Self.orders.forEach { first in
            Self.orders.forEach { second in
                let upper = [corners[0], corners[1], corners[2]]
                let lower = [corners[0], corners[2], corners[3]]
                let pair = [
                    Self.triangle(upper[first[0]], upper[first[1]], upper[first[2]]),
                    Self.triangle(lower[second[0]], lower[second[1]], lower[second[2]]),
                ]
                #expect(Self.claims(pair, 4, 4).pixels == [Int](repeating: 1, count: 16), "orders \(first) and \(second)")
            }
        }
    }

    @Test
    func `an edge that passes a centre within rounding still gives the centre to exactly one of its two triangles`() {
        // Measured from one end and then from the other, each of these edges puts the centre (2.5, 2.5) on the
        // same side twice: only measuring from one agreed end keeps the two triangles apart.
        let edges: [(Corner, Corner)] = [
            ((0.3462122000578501, 0.5889611903918418, 0), (4.940028190970191, 4.665017635259735, 0)),
            ((1.3186557819456897, 4.416919132207562, 0), (5.467602313784753, -2.3154073682662206, 0)),
            ((0.5357735150568349, 3.1371661120279466, 0), (8.115358458420076, 0.6784605064531084, 0)),
            ((2.0914127379031187, 0.4029065060006931, 0), (3.118113254499278, 5.672495583716502, 0)),
        ]
        let apexes: [(Corner, Corner)] = [((5, 0, 0), (0, 5, 0)), ((5, 5, 0), (0, 0, 0)), ((5, 2, 0), (0, 3, 0)), ((5, 2, 0), (0, 3, 0))]
        edges.indices.forEach { index in
            let (start, end) = edges[index]
            let (one, other) = apexes[index]
            let pairs = [
                [Self.triangle(start, end, one), Self.triangle(end, start, other)],
                [Self.triangle(start, end, one), Self.triangle(start, end, other)],
                [Self.triangle(one, end, start), Self.triangle(other, start, end)],
            ]
            pairs.forEach { pair in
                #expect(Self.claims(pair, 5, 5)[x: 2, y: 2] == 1, "edge \(index)")
            }
        }
    }

    @Test
    func `the triangles of a mesh neither share a centre nor leave one out`() {
        func corner(_ column: Int, _ row: Int) -> Corner {
            let wobble = sin(Double(column) * 12.9898 + Double(row) * 78.233) * 43758.5453
            let other = sin(Double(column) * 39.3468 + Double(row) * 11.1351) * 24634.6345
            return (1.3 + 3.1 * Double(column) + 0.9 * (wobble - wobble.rounded(.down)), 0.7 + 3.3 * Double(row) + 0.9 * (other - other.rounded(.down)), 0)
        }
        var mesh: [Triangle] = []
        (0..<5).forEach { row in
            (0..<5).forEach { column in
                let quad = [corner(column, row), corner(column + 1, row), corner(column + 1, row + 1), corner(column, row + 1)]
                mesh.append(Self.triangle(quad[0], quad[1], quad[2]))
                mesh.append((column + row).isMultiple(of: 2) ? Self.triangle(quad[0], quad[2], quad[3]) : Self.triangle(quad[3], quad[2], quad[0]))
            }
        }
        let counts = Self.claims(mesh, 20, 20)
        #expect(counts.pixels.allSatisfy { $0 <= 1 })
        var inside = 0
        (3..<15).forEach { y in
            (3..<15).forEach { x in
                #expect(counts[x: Ordinal(UInt(x)), y: Ordinal(UInt(y))] == 1, "pixel (\(x), \(y))")
                inside += 1
            }
        }
        #expect(inside == 144)
    }

    @Test
    func `where triangles overlap the smaller depth wins, and of equal depths the earlier triangle`() throws {
        let far = Self.triangle((0, 0, 0.8), (16, 0, 0.8), (0, 16, 0.8))
        let middle = Self.triangle((0, 0, 0.5), (16, 0, 0.5), (0, 16, 0.5))
        let near = Self.triangle((0, 0, 0.2), (4, 0, 0.2), (0, 4, 0.2))
        let picture = Self.owners([far, middle, near], 4, 4)
        let expected = try Raster<Int>(width: 4, height: 4, pixels: [2, 2, 2, 1, 2, 2, 1, 1, 2, 1, 1, 1, 1, 1, 1, 1])
        #expect(picture == expected)
        #expect(Self.owners([near, middle, far], 4, 4) == expected.map { 2 - $0 })
        #expect(Self.owners([middle, middle], 4, 4).pixels.allSatisfy { $0 == 0 })

        // A slope whose depth is x / 8 against a level sheet at 0.5: the slope is nearer left of x = 4.
        let slope = Self.triangle((0, 0, 0), (16, 0, 2), (0, 16, 0))
        let crossed = Self.owners([middle, slope], 8, 1)
        #expect(crossed.pixels == [1, 1, 1, 1, 0, 0, 0, 0])
    }

    @Test
    func `a fragment's weights are the centre's barycentric weights on the corners as listed, and its depth their mix`() {
        let corners: [Corner] = [(1, 1, 2), (9, 2, 4), (3, 8, 10)]
        Self.orders.forEach { order in
            let listed = [corners[order[0]], corners[order[1]], corners[order[2]]]
            let hits = Self.hits([Self.triangle(listed[0], listed[1], listed[2])], 10, 10)
            var count = 0
            hits.pixels.indices.forEach { index in
                guard let hit = hits.pixels[index] else { return }
                count += 1
                let centre = (x: Double(index % 10) + 0.5, y: Double(index / 10) + 0.5)
                let weights = hit.weights
                #expect(weights.allSatisfy { $0 >= 0 })
                #expect(abs(weights[0] + weights[1] + weights[2] - 1) < 1e-12)
                #expect(abs(weights[0] * listed[0].x + weights[1] * listed[1].x + weights[2] * listed[2].x - centre.x) < 1e-9)
                #expect(abs(weights[0] * listed[0].y + weights[1] * listed[1].y + weights[2] * listed[2].y - centre.y) < 1e-9)
                #expect(abs(weights[0] * listed[0].z + weights[1] * listed[1].z + weights[2] * listed[2].z - hit.depth) < 1e-12)
                #expect(hit.triangle == 0)
            }
            #expect(count == 24, "corners in order \(order)")
        }
        // A corner that lies on a centre and is taken has weight one there, exactly.
        let cornered = Self.hits([Self.triangle((2.5, 2.5, 7), (6.5, 2.5, 1), (2.5, 6.5, 3))], 8, 8)
        #expect(cornered[x: 2, y: 2] == Hit(triangle: 0, weights: [1, 0, 0], depth: 7))
    }

    @Test
    func `a pixel no triangle takes is the empty pixel, a pixel one takes is asked for once in row order, and a failure ends it`() {
        let none = Raster<Int>.fragments(of: [Triangle](), width: 3, height: 2, empty: 7) { _, _, _ in 0 }
        #expect(none.pixels == [7, 7, 7, 7, 7, 7])
        var asked = 0
        let some = Raster<Int>.fragments(of: [Self.triangle((0, 0, 0), (3, 0, 0), (0, 3, 0))], width: 3, height: 3, empty: 0) { _, _, _ in
            asked += 1
            return asked
        }
        #expect(some.pixels == [1, 2, 0, 3, 0, 0, 0, 0, 0])
        #expect(throws: `Raster Tests`.Failure.self) {
            try Raster<Int>.fragments(of: [Self.triangle((0, 0, 0), (9, 0, 0), (0, 9, 0))], width: 3, height: 2, empty: 0) {
                (_, _, _) throws(`Raster Tests`.Failure) -> Int in throw `Raster Tests`.Failure()
            }
        }
        let empty = Raster<Int>.fragments(of: [Self.triangle((0, 0, 0), (9, 0, 0), (0, 9, 0))], width: 0, height: 5, empty: 0) { _, _, _ in 1 }
        #expect(empty.isEmpty && empty.height == 5)
    }

    @Test
    func `a triangle off the raster is clipped, and one without area or with a coordinate that is not finite takes nothing but keeps its number`() {
        let list = [
            Self.triangle((0, 0, 0), (.nan, 0, 0), (0, 9, 0)),
            Self.triangle((0, 0, 0), (9, 0, 0), (0, 9, -.infinity)),
            Self.triangle((0, 0, 0), (4, 4, 0), (8, 8, 0)),
            Self.triangle((-1e30, -1e30, 1), (1e30, -1e30, 1), (0, 1e30, 1)),
            Self.triangle((-90, -90, 0), (-80, -90, 0), (-90, -80, 0)),
            Self.triangle((90, 90, 0), (95, 90, 0), (90, 95, 0)),
        ]
        #expect(Self.owners(list, 5, 4).pixels == [Int](repeating: 3, count: 20))
    }

    @Test
    func `sampling a region gives that region of the whole raster`() throws {
        let list = [
            Self.triangle((1.2, 0.7, 0.4), (11.6, 3.1, 0.9), (4.4, 10.8, 0.1)),
            Self.triangle((0.3, 9.2, 0.5), (10.1, 0.4, 0.5), (11.3, 11.7, 0.5)),
        ]
        let whole = Self.hits(list, 12, 12)
        let region = Raster<Hit?>.Region(x: 3, y: 2, width: 6, height: 7)
        let part = Raster<Hit?>.fragments(of: list, in: region, empty: nil) { triangle, weights, depth in
            Hit(triangle: triangle, weights: [weights[0], weights[1], weights[2]], depth: depth)
        }
        #expect(try whole.cropped(to: region) == part)
        #expect(part.pixels.contains { $0?.triangle == 0 } && part.pixels.contains { $0?.triangle == 1 })
    }
}

#if Geometry
    extension `Raster Tests` {
        @Suite
        struct `A path covers of each pixel the area that lies inside it` {}
    }

    extension `Raster Tests`.`A path covers of each pixel the area that lies inside it` {
        fileprivate typealias Geo = Geometry<Double, Void>
        fileprivate typealias Corner = (x: Double, y: Double)

        fileprivate static func at(_ x: Double, _ y: Double) -> Geo.Point<2> { .init([x, y]) }

        /// A closed subpath of straight lines through the corners.
        fileprivate static func ring(_ corners: [Corner]) -> Geo.Path.Subpath {
            var segments: [Geo.Path.Segment] = []
            corners.indices.dropFirst().forEach { index in
                segments.append(.line(.init(start: at(corners[index - 1].x, corners[index - 1].y), end: at(corners[index].x, corners[index].y))))
            }
            return .init(startPoint: at(corners[0].x, corners[0].y), segments: segments, isClosed: true)
        }

        fileprivate static func path(_ rings: [Corner]...) -> Geo.Path { .init(subpaths: rings.map(ring)) }

        fileprivate static func box(_ left: Double, _ top: Double, _ right: Double, _ bottom: Double) -> [Corner] {
            [(left, top), (right, top), (right, bottom), (left, bottom)]
        }

        fileprivate static func circle(_ x: Double, _ y: Double, radius: Double) -> Geo.Path.Subpath {
            let arc = Geo.Arc(center: at(x, y), radius: .init(radius), startAngle: .zero, endAngle: Radian(_unchecked: 2 * Double.pi))
            return .init(startPoint: at(x + radius, y), segments: [.arc(arc)], isClosed: true)
        }

        fileprivate static func cover(
            _ path: Geo.Path,
            _ rule: Winding.Rule,
            _ width: Cardinal,
            _ height: Cardinal,
            tolerance: Double = 0.01
        ) throws -> Raster<Double> {
            try Raster<Double>.coverage(of: path, rule: rule, width: width, height: height, tolerance: .init(tolerance))
        }

        /// The length of pixel `pixel` along one axis that lies between two bounds.
        fileprivate static func overlap(_ low: Double, _ high: Double, _ pixel: Ordinal) -> Double {
            let start = Double(Int(bitPattern: pixel))
            return max(0, min(high, start + 1) - max(low, start))
        }

        /// The area of each pixel inside a box, from the box's bounds.
        fileprivate static func area(of box: [Corner], _ width: Cardinal, _ height: Cardinal) -> Raster<Double> {
            Raster(width: width, height: height) { x, y in overlap(box[0].x, box[2].x, x) * overlap(box[0].y, box[2].y, y) }
        }

        /// The share of an n × n grid of points in each pixel that the test holds.
        fileprivate static func sampled(_ width: Cardinal, _ height: Cardinal, grid: Int, _ holds: (Double, Double) -> Bool) -> Raster<Double> {
            Raster(width: width, height: height) { x, y in
                var inside = 0
                (0..<grid).forEach { row in
                    (0..<grid).forEach { column in
                        let point = (Double(Int(bitPattern: x)) + (Double(column) + 0.5) / Double(grid), Double(Int(bitPattern: y)) + (Double(row) + 0.5) / Double(grid))
                        if holds(point.0, point.1) { inside += 1 }
                    }
                }
                return Double(inside) / Double(grid * grid)
            }
        }

        fileprivate static func sum(_ raster: Raster<Double>) -> Double { raster.reduce(0, +) }

        /// The distance from a point to the nearest point of the straight run through the corners.
        fileprivate static func distance(_ x: Double, _ y: Double, to corners: [Corner]) -> Double {
            var best = Double.infinity
            corners.indices.dropFirst().forEach { index in
                let a = corners[index - 1]
                let b = corners[index]
                let chord = (x: b.x - a.x, y: b.y - a.y)
                let squared = chord.x * chord.x + chord.y * chord.y
                let along = squared > 0 ? min(max(((x - a.x) * chord.x + (y - a.y) * chord.y) / squared, 0), 1) : 0
                let away = (x: x - a.x - along * chord.x, y: y - a.y - along * chord.y)
                best = min(best, (away.x * away.x + away.y * away.y).squareRoot())
            }
            return best
        }

        @Test(arguments: Winding.Rule.allCases)
        func `a rectangle along the axes covers of each pixel exactly the area it overlaps`(rule: Winding.Rule) throws {
            let box = Self.box(1.25, 0.5, 4.5, 2.75)
            let expected = Self.area(of: box, 6, 4)
            #expect(try Self.cover(Self.path(box), rule, 6, 4) == expected)
            #expect(try Self.cover(Self.path(box.reversed()), rule, 6, 4) == expected)
            #expect(expected[x: 1, y: 0] == 0.375 && expected[x: 4, y: 2] == 0.375 && expected[x: 2, y: 1] == 1 && expected[x: 5, y: 1] == 0)

            let uneven = Self.box(0.1, 0.2, 2.3, 1.7)
            #expect(`Raster Tests`.close(try Self.cover(Self.path(uneven), rule, 4, 3), Self.area(of: uneven, 4, 3), within: 1e-15))
        }

        @Test(arguments: Winding.Rule.allCases)
        func `a pixel wholly inside is exactly one and a pixel wholly outside exactly zero`(rule: Winding.Rule) throws {
            let corners: [Corner] = [(3.1, 20.4), (18.7, 2.2), (37.3, 17.9), (21.6, 38.8)]
            /// How far a point is on the inner side of the line through corner `index` and the next.
            func side(_ index: Int, _ x: Double, _ y: Double) -> Double {
                let a = corners[index]
                let b = corners[(index + 1) % 4]
                return (b.x - a.x) * (y - a.y) - (b.y - a.y) * (x - a.x)
            }
            let coverage = try Self.cover(Self.path(corners), rule, 40, 40)
            let narrow = try Raster<Float>.coverage(of: Self.path(corners), rule: rule, width: 40, height: 40, tolerance: 0.01)
            var counts = (inside: 0, outside: 0, edge: 0)
            (0..<40).forEach { row in
                (0..<40).forEach { column in
                    let squares = [(0.0, 0.0), (1.0, 0.0), (0.0, 1.0), (1.0, 1.0)].map { (Double(column) + $0.0, Double(row) + $0.1) }
                    let within = (0..<4).allSatisfy { index in squares.allSatisfy { side(index, $0.0, $0.1) > 1e-9 } }
                    let beyond = (0..<4).contains { index in squares.allSatisfy { side(index, $0.0, $0.1) < -1e-9 } }
                    let value = coverage[x: Ordinal(UInt(column)), y: Ordinal(UInt(row))]
                    let single = narrow[x: Ordinal(UInt(column)), y: Ordinal(UInt(row))]
                    if within {
                        #expect(value == 1 && single == 1, "pixel (\(column), \(row))")
                        counts.inside += 1
                    } else if beyond {
                        #expect(value == 0 && single == 0, "pixel (\(column), \(row))")
                        counts.outside += 1
                    } else {
                        #expect(value >= 0 && value <= 1 && single >= 0 && single <= 1)
                        #expect(abs(Double(single) - value) < 1e-6)
                        counts.edge += 1
                    }
                }
            }
            #expect(counts.inside > 500 && counts.outside > 500 && counts.edge > 80)
        }

        @Test(arguments: Winding.Rule.allCases)
        func `inside and outside stay exact however the rows are cut, and no pixel leaves zero to one`(rule: Winding.Rule) throws {
            /// A number in 0..<1 that depends on `index` alone.
            func scatter(_ index: Int) -> Double {
                let value = sin(Double(index) * 12.9898) * 43758.5453
                return value - value.rounded(.down)
            }
            // A band from x ≈ 1 to x ≈ 21 whose left and right borders zigzag, with corners at uneven heights
            // in every row. In the top row, where heights lie between 0 and 1, the heights of the bands a row is
            // cut into do not add up to one without rounding.
            var left: [Corner] = []
            var right: [Corner] = []
            (0...90).forEach { step in
                left.append((0.5 + 1.4 * scatter(step), Double(step) / 3 - 2 + 0.3 * scatter(step + 500)))
                right.append((20.5 + 2.4 * scatter(step + 1000), Double(step) / 3 - 2 + 0.3 * scatter(step + 1500)))
            }
            let band = Self.ring(left + right.reversed())
            // A line there and back, and a sliver, inside the band: sides that lie on each other.
            let hair = Self.ring([(3.3, 2.1), (17.9, 26.4)])
            let twice = Self.ring([(4.1, 25.3), (18.2, 3.7), (18.2, 3.7), (4.1, 25.3), (18.2, 3.7)])
            let shapes = [band, hair, twice]
            let coverage = try Self.cover(Geo.Path(subpaths: shapes), rule, 26, 30)
            let narrow = try Raster<Float>.coverage(of: Geo.Path(subpaths: shapes), rule: rule, width: 26, height: 30, tolerance: 0.01)
            #expect(coverage.pixels.allSatisfy { $0 >= 0 && $0 <= 1 })
            #expect(narrow.pixels.allSatisfy { $0 >= 0 && $0 <= 1 })
            (0..<27).forEach { row in
                (2..<20).forEach { column in
                    #expect(coverage[x: Ordinal(UInt(column)), y: Ordinal(UInt(row))] == 1, "pixel (\(column), \(row))")
                }
                (23..<26).forEach { column in
                    #expect(coverage[x: Ordinal(UInt(column)), y: Ordinal(UInt(row))] == 0, "pixel (\(column), \(row))")
                }
            }
            #expect(try Self.cover(Geo.Path(subpaths: shapes.reversed()), rule, 26, 30) == coverage)
        }

        @Test(arguments: Winding.Rule.allCases)
        func `band heights that do not add up without rounding still give exactly one and exactly zero`(rule: Winding.Rule) throws {
            // The top row is cut at two heights. Added as they come, 0.323 + 0.599 + 0.078 is one unit in the
            // last place short of 1; and 0.074 + 0.485 + 0.441, taken away again in another grouping, leaves one over.
            try [(0.323, 0.922), (0.074, 0.559)].forEach { first, second in
                let step = Self.ring([(-1, -1), (5, -1), (5, first), (6, first), (6, 3), (-1, 3)])
                let apart = Self.ring([(9.2, second), (10.5, 2.5), (8.4, 2.2)])
                let coverage = try Self.cover(Geo.Path(subpaths: [step, apart]), rule, 12, 3)
                #expect(coverage[x: 2, y: 0] == 1, "cut at \(first) and \(second)")
                #expect(coverage[x: 7, y: 0] == 0, "cut at \(first) and \(second)")
                #expect(abs(coverage[x: 5, y: 0] - (1 - first)) < 1e-15)
            }
        }

        @Test(arguments: Winding.Rule.allCases)
        func `the coverage adds up to the area, within the tolerance times the length of the curves`(rule: Winding.Rule) throws {
            let radius = 20.3
            let disc = Geo.Path(subpaths: [Self.circle(32.1, 30.7, radius: radius)])
            let area = Double.pi * radius * radius
            let coarse = abs(Self.sum(try Self.cover(disc, rule, 64, 64, tolerance: 0.05)) - area)
            let fine = abs(Self.sum(try Self.cover(disc, rule, 64, 64, tolerance: 0.0005)) - area)
            #expect(coarse <= 0.05 * 2 * Double.pi * radius)
            #expect(fine <= 0.0005 * 2 * Double.pi * radius)
            #expect(coarse > 0.01, "the coarse outline is a polygon, visibly smaller than the disc")

            let triangle = Self.path([(2.3, 1.1), (17.9, 4.6), (6.2, 15.7)])
            let cross: Double = (17.9 - 2.3) * (15.7 - 1.1) - (4.6 - 1.1) * (6.2 - 2.3)
            let exact: Double = abs(cross) / 2
            #expect(abs(Self.sum(try Self.cover(triangle, rule, 20, 20)) - exact) < 1e-9)
        }

        @Test
        func `where shapes overlap, the rule decides: nonzero covers their union and evenodd leaves out what is covered twice`() throws {
            let first = Self.box(1.25, 1.5, 5.5, 4.25)
            let second = Self.box(3.5, 2.75, 7.25, 6.5)
            let shared = Self.box(3.5, 2.75, 5.5, 4.25)
            let a = Self.area(of: first, 9, 8)
            let b = Self.area(of: second, 9, 8)
            let both = Self.area(of: shared, 9, 8)
            let union = Raster<Double>(width: 9, height: 8) { x, y in a[x: x, y: y] + b[x: x, y: y] - both[x: x, y: y] }
            let once = Raster<Double>(width: 9, height: 8) { x, y in a[x: x, y: y] + b[x: x, y: y] - 2 * both[x: x, y: y] }
            #expect(`Raster Tests`.close(try Self.cover(Self.path(first, second), .nonzero, 9, 8), union))
            #expect(`Raster Tests`.close(try Self.cover(Self.path(first, second), .evenodd, 9, 8), once))
            // Run the other way round, the second box takes the winding number back to zero where they overlap.
            #expect(`Raster Tests`.close(try Self.cover(Self.path(first, second.reversed()), .nonzero, 9, 8), once))
            #expect(union[x: 4, y: 3] == 1 && once[x: 4, y: 3] == 0 && once[x: 3, y: 2] == 0.875)
        }

        @Test(arguments: Winding.Rule.allCases)
        func `contours that cross inside a pixel are filled by area all the same`(rule: Winding.Rule) throws {
            // Two triangles that meet at (4.3, 3.4), drawn as one contour that crosses itself there.
            let bow = Self.path([(0.3, 0.4), (8.3, 6.4), (8.3, 0.4), (0.3, 6.4)])
            let coverage = try Self.cover(bow, rule, 9, 7)
            #expect(abs(Self.sum(coverage) - 24) < 1e-9)
            let reference = Self.sampled(9, 7, grid: 16) { x, y in bow.contains(Self.at(x, y), rule: rule) }
            #expect(`Raster Tests`.close(coverage, reference, within: 0.07))

            // A five-pointed star drawn in one stroke: its middle has winding number two.
            let points: [Corner] = (0..<5).map { index in
                let angle = Double(index) * 4 * Double.pi / 5 - Double.pi / 2
                return (16.2 + 15 * cos(angle), 16.7 + 15 * sin(angle))
            }
            let star = Self.path(points)
            let inner = 15 * sin(Double.pi / 10) / cos(Double.pi / 5)
            let pentagon = 5.0 / 2 * inner * inner * sin(2 * Double.pi / 5)
            let tips = 5 * 15 * inner * sin(Double.pi / 5) - pentagon
            let filled = Self.sum(try Self.cover(star, rule, 33, 33))
            #expect(abs(filled - (rule == .nonzero ? tips + pentagon : tips)) < 1e-9)
        }

        @Test
        func `the stroke outline of swift-geometry, whose pieces overlap, covers the stroked region under nonzero`() throws {
            let run: [Corner] = [(6.3, 5.6), (16.3, 5.6), (16.3, 11.6), (8.3, 14.6), (15.3, 17.6), (15.3, 8.6), (3.3, 19.6)]
            var segments: [Geo.Path.Segment] = []
            run.indices.dropFirst().forEach { index in
                segments.append(.line(.init(start: Self.at(run[index - 1].x, run[index - 1].y), end: Self.at(run[index].x, run[index].y))))
            }
            let line = Geo.Path(subpaths: [.init(startPoint: Self.at(run[0].x, run[0].y), segments: segments, isClosed: false)])
            let outline = try line.stroked(.init(width: .init(3), join: .round, cap: .round), tolerance: 0.001)
            let coverage = try Self.cover(outline, .nonzero, 24, 24, tolerance: 0.001)
            var counts = (inside: 0, outside: 0)
            (0..<24).forEach { row in
                (0..<24).forEach { column in
                    let away = Self.distance(Double(column) + 0.5, Double(row) + 0.5, to: run)
                    let value = coverage[x: Ordinal(UInt(column)), y: Ordinal(UInt(row))]
                    #expect(value >= 0 && value <= 1)
                    if away < 1.5 - 0.72 {
                        #expect(value == 1, "pixel (\(column), \(row))")
                        counts.inside += 1
                    } else if away > 1.5 + 0.72 {
                        #expect(value == 0, "pixel (\(column), \(row))")
                        counts.outside += 1
                    }
                }
            }
            #expect(counts.inside > 40 && counts.outside > 150)
            let reference = Self.sampled(24, 24, grid: 16) { x, y in Self.distance(x, y, to: run) < 1.5 }
            #expect(`Raster Tests`.close(coverage, reference, within: 0.07))
            #expect(abs(Self.sum(coverage) - Self.sum(reference)) < 0.005 * Self.sum(reference))

            // A corner with a miter join: two quadrilaterals and the join overlap, and together make an L.
            let bend = Geo.Path(subpaths: [
                .init(
                    startPoint: Self.at(2.5, 2.5),
                    segments: [
                        .line(.init(start: Self.at(2.5, 2.5), end: Self.at(8.5, 2.5))),
                        .line(.init(start: Self.at(8.5, 2.5), end: Self.at(8.5, 8.5))),
                    ],
                    isClosed: false
                )
            ])
            let mitred = try bend.stroked(.init(width: .init(2), join: .miter(limit: 4), cap: .butt), tolerance: 0.01)
            let across = Self.area(of: Self.box(2.5, 1.5, 9.5, 3.5), 11, 10)
            let down = Self.area(of: Self.box(7.5, 1.5, 9.5, 8.5), 11, 10)
            let corner = Self.area(of: Self.box(7.5, 1.5, 9.5, 3.5), 11, 10)
            let expected = Raster<Double>(width: 11, height: 10) { x, y in across[x: x, y: y] + down[x: x, y: y] - corner[x: x, y: y] }
            #expect(`Raster Tests`.close(try Self.cover(mitred, .nonzero, 11, 10), expected, within: 1e-9))
        }

        @Test(arguments: Winding.Rule.allCases)
        func `two shapes that only share a border cover together what their union covers`(rule: Winding.Rule) throws {
            let corners: [Corner] = [(1.3, 0.9), (10.7, 2.2), (9.4, 10.6), (0.8, 8.1)]
            let upper = try Self.cover(Self.path([corners[0], corners[1], corners[2]]), rule, 12, 12)
            let lower = try Self.cover(Self.path([corners[0], corners[2], corners[3]]), rule, 12, 12)
            let whole = try Self.cover(Self.path(corners), rule, 12, 12)
            let added = upper.zip(lower, +) ?? upper
            #expect(`Raster Tests`.close(added, whole))
            #expect(whole[x: 5, y: 5] == 1 && upper[x: 5, y: 5] > 0 && lower[x: 5, y: 5] > 0)
        }

        @Test(arguments: Winding.Rule.allCases)
        func `a path partly or wholly off the raster is clipped to it`(rule: Winding.Rule) throws {
            let partly = try Self.cover(Self.path(Self.box(-3.5, -10, 2.5, 1.5)), rule, 4, 3)
            #expect(partly.pixels == [1, 1, 0.5, 0, 0.5, 0.5, 0.25, 0, 0, 0, 0, 0])
            let zeros = [Double](repeating: 0, count: 12)
            #expect(try Self.cover(Self.path(Self.box(10, 10, 20, 20)), rule, 4, 3).pixels == zeros)
            #expect(try Self.cover(Self.path(Self.box(-50, -50, -40, 40)), rule, 4, 3).pixels == zeros)
            #expect(try Self.cover(Self.path(Self.box(-50, -50, 40, -40)), rule, 4, 3).pixels == zeros)
            #expect(try Self.cover(Self.path(Self.box(-1e30, -1e30, 1e30, 1e30)), rule, 4, 3).pixels == [Double](repeating: 1, count: 12))
            #expect(try Self.cover(Self.path([(-1e300, -1e300), (1e300, -1e300), (0.5, 1e300)]), rule, 4, 3).pixels.allSatisfy { $0 >= 0 && $0 <= 1 })
            // A subpath with a corner that is not finite is left out; the others still fill.
            let broken = Self.path([(0, 0), (.nan, 0), (0, 3)], [(0, 0), (.infinity, 0), (0, 3)], Self.box(1, 1, 3, 2))
            #expect(try Self.cover(broken, rule, 4, 3).pixels == [0, 0, 0, 0, 0, 1, 1, 0, 0, 0, 0, 0])
        }

        @Test(arguments: Winding.Rule.allCases)
        func `a path that encloses nothing covers nothing`(rule: Winding.Rule) throws {
            let zeros = [Double](repeating: 0, count: 20)
            #expect(try Self.cover(Geo.Path(subpaths: []), rule, 5, 4).pixels == zeros)
            let bare = Geo.Path(subpaths: [.init(startPoint: Self.at(2, 2), segments: [], isClosed: true)])
            #expect(try Self.cover(bare, rule, 5, 4).pixels == zeros)
            #expect(try Self.cover(Self.path([(0.5, 0.5), (4.5, 3.5)]), rule, 5, 4).pixels == zeros)
            #expect(try Self.cover(Self.path([(0.5, 1.5), (4.5, 1.5), (2.5, 1.5)]), rule, 5, 4).pixels == zeros)
            let empty = try Self.cover(Self.path(Self.box(0, 0, 9, 9)), rule, 0, 4)
            #expect(empty.isEmpty && empty.height == 4)
        }

        @Test(arguments: Winding.Rule.allCases)
        func `the coverage does not depend on the order of the subpaths or on where each one starts`(rule: Winding.Rule) throws {
            let rings: [Geo.Path.Subpath] = [
                Self.ring([(0.3, 0.4), (8.3, 6.4), (8.3, 0.4), (0.3, 6.4)]),
                Self.ring(Self.box(2.2, 1.7, 9.1, 7.3)),
                Self.ring([(5.1, 0.2), (11.6, 5.9), (5.4, 11.3), (0.6, 5.5)]),
                Self.circle(6.3, 5.8, radius: 4.1),
                Self.ring(Self.box(2.2, 1.7, 9.1, 7.3).reversed()),
            ]
            let coverage = try Self.cover(Geo.Path(subpaths: rings), rule, 12, 12)
            #expect(try Self.cover(Geo.Path(subpaths: rings.reversed()), rule, 12, 12) == coverage)
            #expect(try Self.cover(Geo.Path(subpaths: [rings[3], rings[0], rings[4], rings[2], rings[1]]), rule, 12, 12) == coverage)
            let turned = Self.ring([(8.3, 0.4), (0.3, 6.4), (0.3, 0.4), (8.3, 6.4)])
            #expect(try Self.cover(Geo.Path(subpaths: [turned] + rings.dropFirst()), rule, 12, 12) == coverage)
            #expect(Self.sum(coverage) > 30)
        }

        @Test(arguments: Winding.Rule.allCases)
        func `the coverage of a region is that region of the whole raster's coverage`(rule: Winding.Rule) throws {
            let shape = Geo.Path(subpaths: [
                Self.ring([(0.3, 0.4), (14.3, 9.4), (14.3, 0.4), (0.3, 9.4)]),
                Self.circle(7.7, 6.1, radius: 5.2),
            ])
            let whole = try Self.cover(shape, rule, 16, 12)
            let region = Raster<Double>.Region(x: 3, y: 2, width: 9, height: 7)
            let part = try Raster<Double>.coverage(of: shape, rule: rule, in: region, tolerance: 0.01)
            let cropped = try whole.cropped(to: region)
            #expect(part.width == 9 && part.height == 7)
            #expect(`Raster Tests`.close(part, cropped))
            let agree = part.zip(cropped) { ($0 == 1) == ($1 == 1) && ($0 == 0) == ($1 == 0) }
            #expect(agree?.reduce(true) { $0 && $1 } == true)
            #expect(cropped.pixels.contains(1) && cropped.pixels.contains(0))

            // Nothing of the path lies outside the region that encloses its bounding box.
            let bounds = try #require(shape.boundingBox)
            let enclosing = Raster<Double>.Region(enclosing: bounds, width: 16, height: 12)
            let within = try Raster<Double>.coverage(of: shape, rule: rule, in: enclosing, tolerance: 0.01)
            #expect(abs(Self.sum(within) - Self.sum(whole)) < 1e-9)
            #expect(Int(bitPattern: enclosing.width) < 16)
        }

        @Test
        func `the region that encloses a rectangle is the whole pixels it touches, kept on the raster`() {
            typealias Region = Raster<Double>.Region
            func region(_ left: Double, _ top: Double, _ right: Double, _ bottom: Double) -> Region {
                Region(enclosing: Geo.Rectangle(llx: .init(left), lly: .init(top), urx: .init(right), ury: .init(bottom)), width: 8, height: 6)
            }
            #expect(region(2.3, 1.2, 6.1, 4) == Region(x: 2, y: 1, width: 5, height: 3))
            #expect(region(-5, -5, 2.5, 100) == Region(x: 0, y: 0, width: 3, height: 6))
            #expect(region(3, 2, 3, 2) == Region(x: 3, y: 2, width: 0, height: 0))
            #expect(region(20, 1, 30, 2).width == 0 && region(1, -9, 2, -3).height == 0)
            #expect(region(.nan, .nan, .nan, .nan) == Region(x: 0, y: 0, width: 0, height: 0))
            #expect(region(-1e30, -1e30, 1e30, 1e30) == Region(x: 0, y: 0, width: 8, height: 6))
        }

        @Test
        func `a tolerance that is not positive and finite is refused`() {
            let box = Self.path(Self.box(1, 1, 3, 3))
            #expect(throws: Geo.Path.Error.tolerance) { try Self.cover(box, .nonzero, 4, 4, tolerance: 0) }
            #expect(throws: Geo.Path.Error.tolerance) { try Self.cover(box, .evenodd, 4, 4, tolerance: .nan) }
        }
    }
#endif
