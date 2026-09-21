// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Yue2Studio",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Yue2Studio", targets: ["Yue2Studio"])
    ],
    dependencies: [
        .package(url: "https://github.com/ml-explore/mlx-swift.git", from: "0.21.0"),
        .package(url: "https://github.com/huggingface/swift-transformers.git", from: "1.1.0")
    ],
    targets: [
        .executableTarget(
            name: "Yue2Studio",
            dependencies: [
                .product(name: "MLX", package: "mlx-swift"),
                .product(name: "MLXNN", package: "mlx-swift"),
                .product(name: "MLXRandom", package: "mlx-swift"),
                .product(name: "MLXFast", package: "mlx-swift"),
                .product(name: "MLXFFT", package: "mlx-swift"),
                .product(name: "Tokenizers", package: "swift-transformers"),
                .product(name: "Hub", package: "swift-transformers")
            ],
            path: "Sources",
            resources: [
                .copy("Resources")
            ],
            linkerSettings: [
                .linkedLibrary("sqlite3"),
                .linkedFramework("Accelerate"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("AudioToolbox"),
                .linkedFramework("Metal"),
                .linkedFramework("MetalKit")
            ]
        ),
        .testTarget(
            name: "Yue2StudioTests",
            dependencies: ["Yue2Studio"],
            path: "Tests"
        )
    ]
)
