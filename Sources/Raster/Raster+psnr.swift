public import Exponential

extension Raster {
    /// The mean over all pixels of `error(mine, theirs)`, or `nil` for rasters of different sizes or with no pixels.
    @inlinable
    public func mean<Scalar: BinaryFloatingPoint, Failure: Swift::Error>(
        against other: Self,
        _ error: (Pixel, Pixel) throws(Failure) -> Scalar
    ) throws(Failure) -> Scalar? {
        guard width == other.width, height == other.height, !pixels.isEmpty else { return nil }
        var sum: Scalar = 0
        for index in pixels.indices { sum += try error(pixels[index], other.pixels[index]) }
        return sum / Scalar(pixels.count)
    }

    /// Peak signal-to-noise ratio in decibels: ten times the base-ten logarithm of `peak` squared over the
    /// mean squared error, where `squared` gives one pixel pair's squared error averaged over its channels.
    /// Rasters with no error at all give +∞, and so do two empty rasters; rasters of different sizes,
    /// which the ratio cannot compare, give `nil`.
    @inlinable
    public func psnr<Scalar: BinaryFloatingPoint & Exponential.`Protocol`, Failure: Swift::Error>(
        against other: Self,
        peak: Scalar,
        squared: (Pixel, Pixel) throws(Failure) -> Scalar
    ) throws(Failure) -> Scalar? {
        guard width == other.width, height == other.height else { return nil }
        guard let mean = try mean(against: other, squared), mean > 0 else { return .infinity }
        return 10 * Scalar.log10(peak * peak / mean)
    }
}
