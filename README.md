# MCP Template

A template repository providing a barebones foundation for building Model Control Protocol (MCP) servers for macOS applications and command line tools.

## Overview

MCP Template serves as a starting point for developers looking to implement MCP servers in their projects. This template demonstrates how to use the `mcp-swift-sdk` in a minimal way, making it easier to understand the basics of MCP integration. It includes both a library template for integration into other projects and a simple command-line example to illustrate basic usage.

## Purpose

This repository is intended to be:
- A reference implementation showing how to use `mcp-swift-sdk`
- A template that can be forked or cloned as a foundation for your own MCP server implementations
- A barebones example that demonstrates core MCP concepts with minimal code

## Features

Current and planned features include:

- [x] Basic Swift package structure
- [x] Command line "hello world" example
- [ ] Command line stdio for direct MCP interaction
- [ ] Command line stdio → standalone Mac app via Bonjour for networked MCP communication
- [ ] SSE server in a Package → example command line app for SSE-based MCP

## Requirements

- Swift 6.0+
- macOS 15+
- iOS 17+ (for mobile integration)
- macCatalyst 17+ (for Catalyst apps)

## Installation

### Swift Package Manager

Add the following to your `Package.swift` file:

```swift
dependencies: [
    .package(url: "https://github.com/your-username/mcp-template.git", branch: "main"),
]
```

Then add the dependency to your target:

```swift
.target(
    name: "YourTarget",
    dependencies: [
        .product(name: "EasyMCP", package: "mcp-template")
    ]
),
```

## Usage

### Basic Example

```swift
import EasyMCP

// Create an instance of EasyMCP
let mcp = EasyMCP()

// Use MCP for AI interactions
let response = try await mcp.process("Hello, how can you help me today?")
print(response)
```

### Command Line Example

The package includes a command line executable called `mcpexample` that demonstrates basic usage:

```bash
# Run the example with a hello command
mcpexample hello
```

## Project Structure

### Targets

1. **EasyMCP** (Library)
   - Minimal template implementation of an MCP server
   - Demonstrates basic integration with the MCP protocol
   - Shows how to leverage the official `mcp-swift-sdk`

2. **mcpexample** (Executable)
   - Simple command-line example using the EasyMCP library
   - Demonstrates how to create a CLI-based MCP server
   - Uses `ArgumentParser` for CLI argument handling

3. **EasyMCPTests** (Test Target)
   - Template tests for the EasyMCP library functionality

### Dependencies

- [swift-argument-parser](https://github.com/apple/swift-argument-parser) (1.3.0+) - Used for CLI argument handling
- [mcp-swift-sdk](https://github.com/loopwork-ai/mcp-swift-sdk) (main branch) - Core MCP implementation from loopwork-ai

## Development

To use this template for your own MCP server:

1. Clone or fork the repository
2. Build the package to verify everything works:
   ```bash
   swift build
   ```
3. Run the tests:
   ```bash
   swift test
   ```
4. Modify the EasyMCP implementation to add your custom functionality
5. Extend the command line example or create your own Mac application

## License

[Insert license information here]

## Acknowledgments

- [loopwork-ai](https://github.com/loopwork-ai) for the MCP Swift SDK 