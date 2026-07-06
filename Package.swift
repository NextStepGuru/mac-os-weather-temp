// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "WeatherBar",
    platforms: [
        .macOS(.v13)
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-testing.git", from: "0.10.0")
    ],
    targets: [
        .executableTarget(
            name: "WeatherBar"
        ),
        .testTarget(
            name: "WeatherBarTests",
            dependencies: [
                "WeatherBar",
                .product(name: "Testing", package: "swift-testing")
            ]
        )
    ]
)
