extension Raster {
    /// A triangle made ready for sampling at pixel centres.
    ///
    /// Each edge is measured from the same end whichever triangle it belongs to, so two triangles that share
    /// an edge compute the same number for a centre, with opposite signs, and exactly one of them takes a
    /// centre that lies on the edge.
    @usableFromInline
    internal struct Facet<Scalar: BinaryFloatingPoint> {
        /// The edges opposite the first, second and third corner, in the order that keeps the inside on one side.
        @usableFromInline
        internal let edges: InlineArray<3, Border>
        /// The corners' depths, in the order of `edges`.
        @usableFromInline
        internal let depths: InlineArray<3, Scalar>
        /// Whether the second and third corner were exchanged to turn the triangle the working way round.
        @usableFromInline
        internal let exchanged: Bool
        @usableFromInline
        internal let low: (x: Scalar, y: Scalar)
        @usableFromInline
        internal let high: (x: Scalar, y: Scalar)

        /// `nil` for a triangle with a coordinate that is not finite, and for one without area.
        @inlinable
        internal init?(_ triangle: InlineArray<3, Point<3, Scalar>>) {
            let first = triangle[0]
            var second = triangle[1]
            var third = triangle[2]
            for index in 0..<3 {
                guard triangle[index].x.isFinite, triangle[index].y.isFinite, triangle[index].z.isFinite else { return nil }
            }
            let turn = (second.x - first.x) * (third.y - first.y) - (second.y - first.y) * (third.x - first.x)
            guard turn > 0 || turn < 0 else { return nil }
            exchanged = turn < 0
            if exchanged { swap(&second, &third) }
            edges = [
                Border(from: (second.x, second.y), to: (third.x, third.y)),
                Border(from: (third.x, third.y), to: (first.x, first.y)),
                Border(from: (first.x, first.y), to: (second.x, second.y)),
            ]
            depths = [first.z, second.z, third.z]
            low = (Swift.min(first.x, second.x, third.x), Swift.min(first.y, second.y, third.y))
            high = (Swift.max(first.x, second.x, third.x), Swift.max(first.y, second.y, third.y))
        }
    }
}

extension Raster.Facet {
    /// The weights on the triangle's corners as they were given, and the depth, at a point the triangle
    /// takes; `nil` at a point it does not take.
    @inlinable
    internal func sample(x: Scalar, y: Scalar) -> (weights: InlineArray<3, Scalar>, depth: Scalar)? {
        let first = edges[0].side(x: x, y: y)
        guard first > 0 || (first == 0 && edges[0].owns) else { return nil }
        let second = edges[1].side(x: x, y: y)
        guard second > 0 || (second == 0 && edges[1].owns) else { return nil }
        let third = edges[2].side(x: x, y: y)
        guard third > 0 || (third == 0 && edges[2].owns) else { return nil }
        let sum = first + second + third
        guard sum > 0 else { return nil }
        let one = first / sum
        let two = second / sum
        let three = third / sum
        let depth = one * depths[0] + two * depths[1] + three * depths[2]
        return (exchanged ? [one, three, two] : [one, two, three], depth)
    }
}
