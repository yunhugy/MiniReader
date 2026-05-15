// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MiniReader",
    platforms: [.iOS(.v16)],
    products: [
        .executable(name: "MiniReader", targets: ["MiniReader"])
    ],
    targets: [
        .executableTarget(
            name: "MiniReader",
            path: "Sources/MiniReader"
        )
    ]
)
