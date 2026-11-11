extension Raster {
    public struct Kernel<Scalar: BinaryFloatingPoint> {
        public let weights: [Scalar]

        @inlinable
        public init(weights: [Scalar]) throws(Error) {
            guard !weights.isEmpty else { throw .empty }
            guard weights.count % 2 == 1 else { throw .even }
            guard weights.allSatisfy({ $0.isFinite && $0 >= 0 }) else { throw .weight }
            let total = weights.reduce(0, +)
            guard total > 0, total.isFinite else { throw .zero }
            self.weights = weights.map { $0 / total }
        }
    }
}

extension Raster.Kernel: Equatable {}
extension Raster.Kernel: Hashable {}
extension Raster.Kernel: Sendable where Scalar: Sendable {}

extension Raster.Kernel {
    @inlinable
    public static var identity: Self { Self(normalized: [1]) }

    @inlinable
    public var radius: Cardinal { Cardinal(UInt(weights.count / 2)) }

    @inlinable
    public static func box(radius: Cardinal) -> Self {
        let count = 2 * Int(bitPattern: radius) + 1
        return Self(normalized: [Scalar](repeating: 1 / Scalar(count), count: count))
    }

    @inlinable
    internal init(normalized weights: [Scalar]) { self.weights = weights }

    @inlinable
    internal var chain: Raster.Chain<Scalar> { Raster.Chain(first: -(weights.count / 2), weights: weights) }
}

extension Raster.Kernel where Scalar: Exponential.`Protocol` {
    @inlinable
    public static func gaussian(deviation: Scalar, radius: Cardinal? = nil) throws(Error) -> Self {
        guard deviation.isFinite, deviation >= 0 else { throw .weight }
        guard deviation > 0 else { return .identity }
        let reach = radius.map { Int(bitPattern: $0) } ?? Int((3 * deviation).rounded(.up))
        let weights = (-reach...reach).map { offset in
            let distance = Scalar(offset) / deviation
            return Scalar.exp(-distance * distance / 2)
        }
        return try Self(weights: weights)
    }
}
