import Foundation
import ArgumentParser
import EasyMCP

@main
struct MCPExample: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "mcpexample",
        abstract: "MCP Example CLI - a simple interface for MCP (Model Control Protocol)",
        version: "0.1.0",
        subcommands: [
            RunCommand.self
        ]
    )
}

@available(macOS 14.0, *)
struct RunCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "run",
        abstract: "Start the MCP server to handle MCP protocol communications"
    )

    func run() async throws {
        let mcp = EasyMCP()

        // Set up signal handling to gracefully exit
        let signalSource = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
        signal(SIGINT, SIG_IGN)
        signalSource.setEventHandler {
            Task {
                await mcp.stop()
                RunCommand.exit()
            }
        }
        signalSource.resume()

        // Start the server and keep it running
        try await mcp.start()

        // Register a simple tool with no input
        try await mcp.register(tool: Tool(
            name: "helloWorld",
            description: "Returns a friendly greeting message",
            inputSchema: ["type": "object", "properties": [:]]  // No input parameters needed for this simple example
        )) { input in
            return Result(content: [.text(helloworld())], isError: false)
        }

        // Register a simple tool that accepts a single parameter
        try await mcp.register(tool: Tool(
            name: "helloPerson",
            description: "Returns a friendly greeting message",
            inputSchema: [
                "type": "object",
                "properties": [
                    "name": [
                        "type": "string",
                        "description": "Name to search for (will match given name or family name)",
                    ]
                ]
            ]
        )) { input in
            return Result(content: [.text(hello(input["name"]?.stringValue ?? "world"))], isError: false)
        }

        // Wait until the server is finished processing all input
        try await mcp.waitUntilComplete()
    }

    /// A simple example method
    public func helloworld() -> String {
        return "Hello iOS Folks! MCP SDK is configured and ready."
    }

    public func hello(_ name: String) -> String {
        return "Hello \(name)! MCP SDK is configured and ready."
    }
}
