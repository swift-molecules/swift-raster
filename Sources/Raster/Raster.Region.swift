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
