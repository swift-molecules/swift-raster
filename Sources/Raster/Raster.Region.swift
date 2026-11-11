#if Geometry
    public import Geometry
#endif

extension Raster {
    public struct Region: Hashable, Sendable {
        public var x: Ordinal
        public var y: Ordinal
        public var width: Cardinal
        public var height: Cardinal

        @inlinable
        public init(x: Ordinal, y: Ordinal, width: Cardinal, height: Cardinal) {
            self.x = x
            self.y = y
            self.width = width
            self.height = height
        }
    }
}

#if Geometry
    extension Raster.Region {
        /// The smallest region of whole pixels, inside a raster of the given size, whose squares hold every
        /// part of `rectangle` that lies on that raster. A rectangle off the raster, or with a bound that is
        /// not a number, gives a region without pixels.
        @inlinable
        public init<Scalar: BinaryFloatingPoint, Space>(
            enclosing rectangle: Geometry<Scalar, Space>.Rectangle,
            width: Cardinal,
            height: Cardinal
        ) {
            let columns = Raster.origin(Ordinal(width))
            let rows = Raster.origin(Ordinal(height))
            let left = Raster.whole(rectangle.llx.underlying, .down, from: 0, to: columns)
            let right = Raster.whole(rectangle.urx.underlying, .up, from: left, to: columns)
            let top = Raster.whole(rectangle.lly.underlying, .down, from: 0, to: rows)
            let bottom = Raster.whole(rectangle.ury.underlying, .up, from: top, to: rows)
            self.init(
                x: Ordinal(UInt(left)),
                y: Ordinal(UInt(top)),
                width: Cardinal(UInt(right - left)),
                height: Cardinal(UInt(bottom - top))
            )
        }
    }
#endif
