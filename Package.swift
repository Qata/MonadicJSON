// swift-tools-version:5.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "MonadicJSON",
    platforms: [
        .macOS(.v10_10), .iOS(.v8), .watchOS(.v2), .tvOS(.v9),
    ],
    products: [
        // Products define the executables and libraries produced by a package, and make them visible to other packages.
        .library(
            name: "MonadicJSON",
            targets: ["MonadicJSON"]
        ),
    ],
    dependencies: [
        // Dev deps
        .package(url: "https://github.com/typelift/SwiftCheck", from: "0.12.0"),
    ],
    targets: [
        // Targets are the basic building blocks of a package. A target can define a module or a test suite.
        // Targets can depend on other targets in this package, and on products in packages which this package depends on.
        .target(
            name: "MonadicJSON",
            dependencies: [
            ],
            path: "Sources"
        ),
        .testTarget(
            name: "MonadicJSONTests",
            dependencies: [
                "MonadicJSON",
                "SwiftCheck",
            ],
            path: "Tests"
        ),
    ]
)
