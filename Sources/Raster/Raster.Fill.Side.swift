#if Geometry
    extension Raster.Fill {
        /// One straight side of a polygon, stored from its upper end (the smaller y) to its lower end.
        /// `turn` is +1 when the polygon runs along it towards larger y and −1 when it runs the other way.
        @usableFromInline
        internal struct Side {
            @usableFromInline
            internal let top: (x: Scalar, y: Scalar)
            @usableFromInline
            internal let bottom: (x: Scalar, y: Scalar)
            @usableFromInline
            internal let turn: Int
            @usableFromInline
            internal let slope: Scalar
            @usableFromInline
            internal let low: Scalar
            @usableFromInline
            internal let high: Scalar

            /// `nil` for a side along a row, which bounds no area between rows.
            @inlinable
            internal init?(from start: (x: Scalar, y: Scalar), to end: (x: Scalar, y: Scalar)) {
                guard start.y != end.y else { return nil }
                if start.y < end.y {
                    top = start
                    bottom = end
                    turn = 1
                } else {
                    top = end
                    bottom = start
                    turn = -1
                }
                slope = (bottom.x - top.x) / (bottom.y - top.y)
                low = Swift.min(start.x, end.x)
                high = Swift.max(start.x, end.x)
            }
        }
    }

    extension Raster.Fill.Side {
        /// Where the side is at height `y`: its own end exactly at or beyond an end, and never outside its span.
        @inlinable
        internal func x(at y: Scalar) -> Scalar {
            if y <= top.y { return top.x }
            if y >= bottom.y { return bottom.x }
            let x = top.x + (y - top.y) * slope
            return x > low ? (x < high ? x : high) : low
        }
    }
#endif
