// swift-tools-version: 6.1

import CompilerPluginSupport
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
        .package(url: "https://github.com/apple/swift-collections.git", from: "1.1.0"),
        // Same range as swift-json-schema so consumers resolve one swift-syntax.
        .package(url: "https://github.com/swiftlang/swift-syntax.git", "600.0.1"..<"700.0.0"),
    ],
    targets: [
        .macro(
            name: "MCPHostMacrosPlugin",
            dependencies: [
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
            ]
        ),
        .target(
            name: "MCPHostCore",
            dependencies: [
                "MCPHostMacrosPlugin",
                .product(name: "OrderedCollections", package: "swift-collections"),
                .product(name: "JSONSchema", package: "swift-json-schema"),
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
            dependencies: ["MCPHostCore", .product(name: "OrderedCollections", package: "swift-collections")]
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
            dependencies: ["MCPHostCore", .product(name: "OrderedCollections", package: "swift-collections")]
        ),
        .testTarget(
            name: "MCPHostMacrosTests",
            dependencies: [
                "MCPHostMacrosPlugin",
                .product(name: "SwiftSyntaxMacrosTestSupport", package: "swift-syntax"),
            ]
        ),
        .testTarget(
            name: "MCPHostContractTests",
            dependencies: ["MCPHostCore", "MCPHostTesting"],
            resources: [.copy("Resources/mcp-schema")]
        ),
    ]
)
