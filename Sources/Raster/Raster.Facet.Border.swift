extension Raster.Facet {
    /// A triangle's edge, walked with the triangle's inside on the side where `side(x:y:)` is positive.
    @usableFromInline
    internal struct Border {
        @usableFromInline
        internal let anchor: (x: Scalar, y: Scalar)
        @usableFromInline
        internal let run: (x: Scalar, y: Scalar)
        /// Whether the edge is walked from its later end, so that the measure from the earlier end is negated.
        @usableFromInline
        internal let reversed: Bool
        /// Whether a centre exactly on the edge belongs to this triangle: on an edge with the inside to its
        /// right or, when the edge lies along a row, with the inside below it.
        @usableFromInline
        internal let owns: Bool

        @inlinable
        internal init(from start: (x: Scalar, y: Scalar), to end: (x: Scalar, y: Scalar)) {
            reversed = end.y < start.y || (end.y == start.y && end.x < start.x)
            anchor = reversed ? end : start
            run = reversed ? (start.x - end.x, start.y - end.y) : (end.x - start.x, end.y - start.y)
            let along = (x: end.x - start.x, y: end.y - start.y)
            owns = along.y < 0 || (along.y == 0 && along.x > 0)
        }
    }
}

extension Raster.Facet.Border {
    /// Positive on the triangle's side of the edge, negative on the other, zero on the edge's line.
    @inlinable
    internal func side(x: Scalar, y: Scalar) -> Scalar {
        let measure = run.x * (y - anchor.y) - run.y * (x - anchor.x)
        return reversed ? -measure : measure
    }
}
