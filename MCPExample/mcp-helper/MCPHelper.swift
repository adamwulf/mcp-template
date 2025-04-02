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

    func run() async throws {
        // build server
        let logger = Logger(label: "com.milestonemade.easymcp")
        let mcp = EasyMCP(logger: logger)

        try await Task.sleep(for: .seconds(3))
        
        // Pipe test code
        Task {
            logger.info("Starting pipe test...")
            
            // Get the path to the pipe
            let pipePath = PipeConstants.testPipePath()
            logger.info("Creating write pipe at: \(pipePath.path)")
            
            // Create a write pipe
            guard let writePipe = WritePipe(url: pipePath) else {
                logger.error("Failed to create write pipe")
                return
            }
            
            // Open the pipe for writing
            guard writePipe.open() else {
                logger.error("Failed to open write pipe")
                return
            }
            
            // Write to the pipe
            let message = "Hello World from mcp-helper!"
            logger.info("Writing message: \(message)")
            
            if writePipe.write(message) {
                logger.info("Message written successfully")
            } else {
                logger.error("Failed to write message")
            }
            
            // Close the pipe
            writePipe.close()
            logger.info("Pipe test completed")
        }

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

        // Register a simple tool with no input
        try await mcp.register(tool: Tool(
            name: "helloWorld",
            description: "Returns a friendly greeting message"
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

        // Start the server and keep it running
        try await mcp.start()

        Task {
            try await Task.sleep(for: .seconds(30))
            logger.info("registering extra tool")

            do {
                // Register a simple tool with no input
                try await mcp.register(tool: Tool(
                    name: "helloEveryone",
                    description: "Returns a friendly greeting message to everyone around"
                )) { input in
                    return Result(content: [.text(helloworld())], isError: false)
                }
                logger.info("registered extra tool")
            } catch {
                logger.error("failed registering extra tool: \(error)")
            }
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
