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
            guard
                triangle.indices.allSatisfy({ index in
                    triangle[index].x.isFinite && triangle[index].y.isFinite && triangle[index].z.isFinite
                })
            else { return nil }
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

extension Raster.Facet {
    /// Columns of the row whose centres lie at `y`, among those from `first` up to `end`, outside which the
    /// triangle takes no centre: the row's scan may be held to them and finds what it would find in all.
    ///
    /// Along a row an edge's measure only rises or only falls, in rounded arithmetic as in exact, so the
    /// centres an edge admits are all those from some column on, or all those up to one. Where the measure
    /// crosses zero is solved for, a column is kept to either side of it, and the bound is used only once
    /// the edge is seen to refuse the centre just beyond it. A bound that rounding put wrong is not used.
    @inlinable
    internal func span(y: Scalar, from first: Int, to end: Int) -> (first: Int, end: Int) {
        let half: Scalar = 1 / 2
        var low = first
        var high = end
        var edge = 0
        while edge < 3, low < high {
            let border = edges[edge]
            edge += 1
            guard border.run.y > 0 || border.run.y < 0 else {
                guard border.admits(x: Raster.real(low) + half, y: y) else { return (first, first) }
                continue
            }
            let level = border.run.x * (y - border.anchor.y)
            guard level.isFinite, border.run.y.isFinite else { continue }
            let crossing = border.anchor.x + level / border.run.y - half
            if border.reversed == (border.run.y > 0) {
                let column = Raster.whole(crossing, .down, from: low, to: high) - 1
                if column > low, !border.admits(x: Raster.real(column - 1) + half, y: y) { low = column }
            } else {
                let column = Raster.whole(crossing, .up, from: low, to: high) + 2
                if column < high, !border.admits(x: Raster.real(column) + half, y: y) { high = column }
            }
        }
        return low < high ? (low, high) : (first, first)
    }
}
