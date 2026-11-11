extension Raster {
    public enum Edge {
        case extend
        case wrap
        case mirror
        case constant(Pixel)
    }
}

extension Raster.Edge: Equatable where Pixel: Equatable {}
extension Raster.Edge: Hashable where Pixel: Hashable {}
extension Raster.Edge: Sendable where Pixel: Sendable {}

extension Raster.Edge {
    @inlinable
    internal func position(_ position: Int, in count: Int) -> Int {
        switch self {
        case .extend, .constant:
            return Swift.min(Swift.max(position, 0), count - 1)

        case .wrap:
            let remainder = position % count
            return remainder < 0 ? remainder + count : remainder

        case .mirror:
            let period = 2 * count
            let remainder = position % period
            let positive = remainder < 0 ? remainder + period : remainder
            return positive < count ? positive : period - 1 - positive
        }
    }
}
