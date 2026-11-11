import Foundation
public import Raster
import Testing

extension Double: @retroactive Exponential.`Protocol` {
    public static func exp(_ x: Double) -> Double { Foundation.exp(x) }
    public static func expm1(_ x: Double) -> Double { Foundation.expm1(x) }
    public static func exp2(_ x: Double) -> Double { Foundation.exp2(x) }
    public static func log(_ x: Double) -> Double { Foundation.log(x) }
    public static func log1p(_ x: Double) -> Double { Foundation.log1p(x) }
    public static func log2(_ x: Double) -> Double { Foundation.log2(x) }
    public static func log10(_ x: Double) -> Double { Foundation.log10(x) }
}

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
            #expect(Raster(width: 0, height: 0, repeating: 1.0).reduce(5, +) == 5)
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
