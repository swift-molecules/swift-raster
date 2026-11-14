// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "swift-raster",
    platforms: [.macOS(.v27), .iOS(.v27), .tvOS(.v27), .watchOS(.v27), .visionOS(.v27)],
    products: [.library(name: "Raster", targets: ["Raster"])],
    traits: [
        .trait(name: "Geometry", description: "Coverage of a swift-geometry path")
    ],
    dependencies: [
        .package(url: "https://github.com/swift-atoms/swift-angle.git", branch: "main"),
        .package(url: "https://github.com/swift-atoms/swift-cardinal.git", branch: "main"),
        .package(url: "https://github.com/swift-atoms/swift-direction.git", branch: "main"),
        .package(url: "https://github.com/swift-atoms/swift-exponential.git", branch: "main"),
        .package(
            url: "https://github.com/swift-atoms/swift-geometry.git",
            branch: "main",
            traits: [.trait(name: "Affine", condition: .when(traits: ["Geometry"]))]
        ),
        .package(url: "https://github.com/swift-atoms/swift-matrix.git", branch: "main"),
        .package(url: "https://github.com/swift-atoms/swift-numeric.git", branch: "main"),
        .package(url: "https://github.com/swift-atoms/swift-ordinal.git", branch: "main"),
        .package(url: "https://github.com/swift-atoms/swift-point.git", branch: "main"),
    ],
    targets: [
        .target(
            name: "Raster",
            dependencies: [
                .product(name: "Cardinal", package: "swift-cardinal"),
                .product(name: "Direction", package: "swift-direction", condition: .when(traits: ["Geometry"])),
                .product(name: "Exponential", package: "swift-exponential"),
                .product(name: "Geometry", package: "swift-geometry", condition: .when(traits: ["Geometry"])),
                .product(name: "Matrix", package: "swift-matrix"),
                .product(name: "Numeric", package: "swift-numeric", condition: .when(traits: ["Geometry"])),
                .product(name: "Ordinal", package: "swift-ordinal"),
                .product(name: "Point", package: "swift-point"),
            ]
        ),
        .testTarget(
            name: "Raster Tests",
            dependencies: [
                .target(name: "Raster"),
                .product(name: "Angle", package: "swift-angle", condition: .when(traits: ["Geometry"])),
                .product(name: "Numeric", package: "swift-numeric"),
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)

for target in package.targets where ![.system, .binary, .plugin, .macro].contains(target.type) {
    target.swiftSettings =
        (target.swiftSettings ?? []) + [
            .strictMemorySafety(),
            .enableUpcomingFeature("ExistentialAny"),
            .enableUpcomingFeature("InternalImportsByDefault"),
            .enableUpcomingFeature("MemberImportVisibility"),
            .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
            .enableUpcomingFeature("InferIsolatedConformances"),
            .enableExperimentalFeature("Lifetimes"),
            .treatAllWarnings(as: .error),
        ]
}
