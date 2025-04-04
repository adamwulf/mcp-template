import Foundation
import ArgumentParser
import EasyMCP
import Logging

@main
struct MCPHelper: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "mcp-helper",
        abstract: "MCP Helper CLI - a simple interface for MCP (Model Control Protocol)",
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

    // Unique identifier for this helper instance
    private let helperId: String

    init() {
        helperId = UUID().uuidString
    }

    /// Sends an MCPRequest through the pipe
    private func sendRequest(_ request: MCPRequest) async {
        await PipeManager.sendToolRequest(request)
    }

    func run() async throws {
        // Send initialize message
        await sendRequest(.initialize(helperId: helperId))

        // build server
        let logger = Logger(label: "com.milestonemade.easymcp")
        let mcp = EasyMCP(logger: logger)

        try await Task.sleep(for: .seconds(3))

        // Use the new PipeTestHelpers to test pipe functionality
        Task {
            await PipeTestHelpers.testWritePipeAsync(
                message: "Hello World from mcp-helper through PipeTestHelpers!"
            )
        }

        // Set up signal handling to gracefully exit
        let signalSource = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
        signal(SIGINT, SIG_IGN)
        signalSource.setEventHandler {
            Task {
                // Send deinitialize message before stopping
                await self.sendRequest(.deinitialize(helperId: self.helperId))
                await mcp.stop()
                RunCommand.exit()
            }
        }
        signalSource.resume()

        // Register a simple tool with no input
        try await mcp.register(tool: Tool(
            name: "helloWorld",
            description: "Returns a friendly greeting message"
        )) { _ in
            // Send the helloWorld request to the main app
            Task {
                await self.sendRequest(.helloWorld(helperId: self.helperId, messageId: UUID().uuidString))
            }
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
            let name = input["name"]?.stringValue ?? "world"
            // Send the helloPerson request to the main app
            Task {
                await self.sendRequest(.helloPerson(helperId: self.helperId, messageId: UUID().uuidString, name: name))
            }
            return Result(content: [.text(hello(name))], isError: false)
        }

        // Start the server and keep it running
        try await mcp.start()

        Task {
            try await Task.sleep(for: .seconds(30))

            do {
                // Register a simple tool with no input
                try await mcp.register(tool: Tool(
                    name: "helloEveryone",
                    description: "Returns a friendly greeting message to everyone around"
                )) { _ in
                    return Result(content: [.text(helloworld())], isError: false)
                }
            } catch {
                logger.error("failed registering extra tool: \(error)")
            }
        }

        // Wait until the server is finished processing all input
        try await mcp.waitUntilComplete()

        await sendRequest(.deinitialize(helperId: helperId))
    }

    /// A simple example method
    public func helloworld() -> String {
        return "Hello iOS Folks! MCP SDK is configured and ready."
    }

    public func hello(_ name: String) -> String {
        return "Hello \(name)! MCP SDK is configured and ready."
    }
}
