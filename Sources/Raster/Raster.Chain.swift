extension Raster {
    /// An average with non-negative weights, as the chain of interpolations that computes it:
    /// start from the pixel at `offsets[0]`, then mix in each next pixel at its parameter.
    @usableFromInline
    internal struct Chain<Scalar: BinaryFloatingPoint> {
        @usableFromInline
        internal var offsets: [Int] = []
        @usableFromInline
        internal var parameters: [Scalar] = []

        /// The chain of `weights` laid from `first` on. Zero weights are left out; when every weight is zero
        /// the middle one stands for all, so a chain always has a pixel to start from.
        @inlinable
        internal init(first: Int, weights: [Scalar]) {
            var total: Scalar = 0
            for (index, weight) in weights.enumerated() where weight > 0 {
                total += weight
                offsets.append(first + index)
                parameters.append(weight / total)
            }
            if offsets.isEmpty {
                offsets = [first + weights.count / 2]
                parameters = [1]
            }
        }
    }
}

extension Raster.Chain {
    @inlinable
    internal func value<Failure: Swift::Error>(
        mixing mix: (Pixel, Pixel, Scalar) throws(Failure) -> Pixel,
        pixel: (Int) -> Pixel
    ) throws(Failure) -> Pixel {
        var result = pixel(offsets[0])
        for index in offsets.indices.dropFirst() {
            result = try mix(result, pixel(offsets[index]), parameters[index])
        }
        return result
    }
}
