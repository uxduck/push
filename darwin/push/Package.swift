// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "push",
    platforms: [
        .iOS("13.0"),
        .macOS("10.15"),
    ],
    products: [
        .library(name: "push", targets: ["push"]),
    ],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework"),
    ],
    targets: [
        .target(
            name: "push_pigeon",
            dependencies: [
                .product(name: "FlutterFramework", package: "FlutterFramework"),
            ],
            path: "Sources/push_pigeon",
            publicHeadersPath: "include",
            cSettings: [
                .headerSearchPath("include/push_pigeon"),
            ]
        ),
        .target(
            name: "push",
            dependencies: [
                "push_pigeon",
                .product(name: "FlutterFramework", package: "FlutterFramework"),
            ],
            path: "Sources/push"
        ),
    ]
)
