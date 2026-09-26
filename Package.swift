// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "swift-mcp-host",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "MCPHostCore", targets: ["MCPHostCore"]),
        .library(name: "MCPHostHTTP", targets: ["MCPHostHTTP"]),
        .library(name: "MCPHostStream", targets: ["MCPHostStream"]),
        .library(name: "MCPHostTesting", targets: ["MCPHostTesting"]),
    ],
    dependencies: [
        // Exact pins: see docs/decisions.md#toolchain before moving either.
        .package(url: "https://github.com/ajevans99/swift-json-schema", exact: "0.14.1"),
        .package(url: "https://github.com/hummingbird-project/hummingbird", exact: "2.26.0"),
    ],
    targets: [
        .target(
            name: "MCPHostCore",
            dependencies: [
                .product(name: "JSONSchemaBuilder", package: "swift-json-schema"),
            ]
        ),
        .target(
            name: "MCPHostHTTP",
            dependencies: [
                "MCPHostCore",
                .product(name: "Hummingbird", package: "hummingbird"),
            ]
        ),
        .target(
            name: "MCPHostStream",
            dependencies: ["MCPHostCore"]
        ),
        .target(
            name: "MCPHostTesting",
            dependencies: [
                "MCPHostCore",
                .product(name: "JSONSchema", package: "swift-json-schema"),
            ]
        ),
        .testTarget(
            name: "MCPHostCoreTests",
            dependencies: ["MCPHostCore"]
        ),
        .testTarget(
            name: "MCPHostContractTests",
            dependencies: ["MCPHostCore", "MCPHostTesting"],
            resources: [.copy("Resources/mcp-schema")]
        ),
    ]
)
