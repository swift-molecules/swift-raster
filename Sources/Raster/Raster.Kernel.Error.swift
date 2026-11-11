extension Raster.Kernel {
    public enum Error: Swift::Error, Equatable, Sendable {
        case empty
        case even
        case weight
        case zero
    }
}
