// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "mcp-template",
    platforms: [
        .macOS(.v15),
        .iOS(.v17),
        .macCatalyst(.v17)
    ],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "EasyMCP",
            targets: ["EasyMCP"]),
        .library(
            name: "EasyMacMCP",
            targets: ["EasyMacMCP"]),
        .executable(
            name: "mcpexample",
            targets: ["mcpexample"])
    ],
    dependencies: [
        // Dependencies declare other packages that this package depends on.
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.0"),
        .package(url: "https://github.com/modelcontextprotocol/swift-sdk", branch: "main")
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "EasyMCP",
            dependencies: [
                .product(name: "MCP", package: "swift-sdk")
            ]),
        .target(
            name: "EasyMacMCP",
            dependencies: [
                "EasyMCP"
            ]),
        .executableTarget(
            name: "mcpexample",
            dependencies: [
                "EasyMCP",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ]),
        .testTarget(
            name: "EasyMacMCPTests",
            dependencies: ["EasyMacMCP"]
        )
    ]
)
