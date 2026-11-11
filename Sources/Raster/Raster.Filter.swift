extension Raster {
    public enum Filter: Hashable, Sendable {
        case nearest
        case box
        case triangle
    }
}

extension Raster.Filter {
    @inlinable
    internal func chains<Scalar: BinaryFloatingPoint>(from source: Int, to target: Int) -> [Raster.Chain<Scalar>] {
        let scale = Scalar(source) / Scalar(target)
        let half: Scalar = 1 / 2
        return (0..<target).map { index in
            let start = Scalar(index) * scale
            let end = Scalar(index + 1) * scale
            let centre = (Scalar(index) + half) * scale
            switch self {
            case .nearest:
                return Raster.Chain(first: Swift.min(Swift.max(Int(centre.rounded(.down)), 0), source - 1), weights: [1])

            case .box:
                let first = Swift.min(Swift.max(Int(start.rounded(.down)), 0), source - 1)
                let last = Swift.min(Swift.max(Int(end.rounded(.up)) - 1, first), source - 1)
                let weights = (first...last).map { Swift.max(Swift.min(end, Scalar($0 + 1)) - Swift.max(start, Scalar($0)), 0) }
                return Raster.Chain(first: first, weights: weights)

            case .triangle:
                let radius = Swift.max(scale, 1)
                let first = Swift.min(Swift.max(Int((centre - radius - half).rounded(.up)), 0), source - 1)
                let last = Swift.min(Swift.max(Int((centre + radius - half).rounded(.down)), first), source - 1)
                let weights = (first...last).map { Swift.max(1 - abs(Scalar($0) + half - centre) / radius, 0) }
                return Raster.Chain(first: first, weights: weights)
            }
        }
    }
}
