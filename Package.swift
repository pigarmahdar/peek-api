// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "peek-api",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "peek-api", targets: ["PeekAPI"]),
        .executable(name: "peek-check", targets: ["PeekAPICheck"])
    ],
    targets: [
        .target(
            name: "PeekAPICore",
            path: "Sources/PeekAPICore"
        ),
        .executableTarget(
            name: "PeekAPI",
            dependencies: ["PeekAPICore"],
            path: "Sources/PeekAPI"
        ),
        .executableTarget(
            name: "PeekAPICheck",
            dependencies: ["PeekAPICore"],
            path: "Tests/PeekAPICheck"
        )
    ]
)
