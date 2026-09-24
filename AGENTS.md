# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build and Test Commands

```bash
# Build the package
swift build

# Run tests
swift test

# Run the command line MCP server
swift run mcpexample run

# Format code using SwiftLint
./format-files.sh

# Build in Xcode (for iOS/macOS apps)
open MCPExample/MCPExample.xcworkspace
```

## Architecture Overview

This repository provides a template for building MCP (Model Control Protocol) servers in Swift with three main components:

### 1. EasyMCP Library (`Sources/EasyMCP/`)
- Core MCP server implementation using the official `mcp-swift-sdk`
- Wraps the SDK to provide a simplified interface for registering tools and handling MCP communications
- Uses stdio transport for command-line MCP servers
- Key class: `EasyMCP` - manages server lifecycle, tool registration, and MCP protocol handling

### 2. EasyMacMCP Library (`Sources/EasyMacMCP/`)
- Specialized implementation for macOS applications that need App Store compatibility
- Uses named pipes for inter-process communication between a sandboxed Mac app and a helper executable
- Enables MCP functionality in sandboxed environments where stdio access is restricted
- Key classes:
  - `EasyMCPHost` - Base class for managing pipe-based communication with helper processes
  - `MCPProtocols.swift` - Protocol definitions for request/response communication
  - Pipe classes (`*Pipe.swift`) - Handle reading/writing to named pipes

### 3. Command Line Example (`Sources/mcpexample/`)
- Demonstrates basic MCP server usage with `EasyMCP`
- Registers sample tools (`helloWorld`, `helloPerson`, `helloEveryone`) 
- Shows how to handle tool registration, server startup, and graceful shutdown
- Uses `ArgumentParser` for CLI interface

### 4. macOS App Example (`MCPExample/`)
- Xcode workspace demonstrating App Store-safe MCP integration
- Main app uses `EasyMacMCP` to communicate with a helper executable via named pipes
- Helper executable (`mcp-helper`) runs the actual MCP server using `EasyMCP`
- Shows how to build MCP functionality that works within macOS sandboxing restrictions

## Key Architectural Patterns

### Tool Registration Pattern
Tools are registered with async closures that handle the actual work:
```swift
try await mcp.register(tool: Tool(name: "toolName", description: "...", inputSchema: schema)) { input in
    // Async work here
    return Result(content: [.text("response")], isError: false)
}
```

### Pipe-Based Communication (macOS Apps)
- Request flow: Mac App ← Named Pipe ← Helper Executable ← stdio ← MCP Client
- Response flow: Mac App → Named Pipe → Helper Executable → stdio → MCP Client
- Each helper gets its own response pipe identified by `helperId`

### Platform Requirements
- macOS 15+ for main targets
- iOS 17+ / macCatalyst 17+ for cross-platform support
- Swift 6.0+ required

## Debugging MCP Servers

For command-line MCP servers, use the MCP Inspector:
```bash
# Build in Xcode first, then find the executable path
npx @modelcontextprotocol/inspector <path_to_executable> run
```

For macOS app debugging, the helper executable can be debugged separately while the main app handles the UI and pipe communication.