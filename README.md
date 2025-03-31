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
- [x] Command line "hello world" example tool
- [x] Command line stdio for direct MCP interaction via the `run` command
- [ ] App Store safe command line stdio → standalone Mac app communication
- [ ] SSE server in a Package → example command line app for SSE-based MCP

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

// Register a tool
try await mcp.register(tool: Tool(
    name: "helloPerson",
    description: "Returns a friendly greeting message",
    inputSchema: [
        "type": "object",
        "properties": [
            "name": [
                "type": "string",
                "description": "Name of the person to say hello to",
            ]
        ],
        "required": ["name"]
    ]
)) { input in
    // It's an async closure, so you can await whatever you need to for long running tasks
    await someOtherAsyncStuffIfYouWant()
    // Return your result and flag if it is/not an error
    return Result(content: [.text(hello(input["name"]?.stringValue ?? "world"))], isError: false)
}

// Start the MCP server for full MCP interaction
try await mcp.start()
try await mcp.waitUntilComplete()
```

### Command Line Example

The package includes a command line executable called `mcpexample` that demonstrates basic usage:

```bash
# Run the basic hello example
mcpexample hello

# Start the MCP server to handle MCP protocol communications
mcpexample run
```

## Project Structure

### Targets

1. **EasyMCP** (Library)
   - Minimal template implementation of an MCP server
   - Demonstrates basic integration with the MCP protocol
   - Shows how to leverage the official `mcp-swift-sdk`
   - Includes a simple tool example (helloworld)

2. **mcpexample** (Executable)
   - Simple command-line example using the EasyMCP library
   - Includes both a hello command and a run command
   - The run command starts a full MCP server using stdio transport
   - Uses `ArgumentParser` for CLI argument handling

3. **EasyMCPTests** (Test Target)
   - Template tests for the EasyMCP library functionality
   - Includes a basic test for the hello function

### Dependencies

- [swift-argument-parser](https://github.com/apple/swift-argument-parser) (1.3.0+) - Used for CLI argument handling
- [mcp-swift-sdk](https://github.com/adamwulf/mcp-swift-sdk) (branch: "feature/wait-for-complete") - Custom fork of the MCP implementation that adds the ability to wait for the mcp server to finish

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

It may also be helpful to use [the MCP Inspector](https://modelcontextprotocol.io/docs/tools/inspector) to diagnose and debug a custom MCP server.

``` bash
$ npx @modelcontextprotocol/inspector
```

## Testing your MCP command line executable

To test and debug your MCP server using the MCP Inspector:

1. Build your command line executable in Xcode
2. Locate the executable by going to Xcode → Product → Show Build Folder in Finder
3. Copy the absolute path of the executable from that directory
4. Use the [MCP Inspector](https://modelcontextprotocol.io/docs/tools/inspector) to test your server
5. Open Terminal and run:
   ```bash
   npx @modelcontextprotocol/inspector <absolute_path_to_your_executable> run
   ```
6. Open your browser to the port shown in the output:
   ```
   🔍 MCP Inspector is up and running at http://localhost:5173 🚀
   ```
7. Press the Connect button in the MCP Inspector interface
8. Open Activity Monitor and search for your executable name
9. Verify only the inspector and a single instance of your tool is running
10. In Xcode → Debug → Attach to Process → Find your executable name at the top and attach
11. In Terminal, run `tail -n 20 -f ~/Library/Logs/Claude/mcp*.log`
12. Now you can interact with your server through the inspector while hitting breakpoints in Xcode!

This setup provides a powerful debugging environment where you can:
- Test your MCP server's functionality through the Inspector's UI
- Set breakpoints in your code to trace execution
- Inspect variables and state during operation
- Debug resource, prompt, and tool implementations in real-time

For more debugging tips, visit [MCP Debugging](https://modelcontextprotocol.io/docs/tools/debugging) at Anthropic's modelcontextprotocol.io site.

## License

MIT licensed.

## Acknowledgments

- [loopwork-ai](https://github.com/loopwork-ai) for the MCP Swift SDK 
