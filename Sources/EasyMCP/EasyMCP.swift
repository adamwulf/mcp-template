// The Swift Programming Language
// https://docs.swift.org/swift-book

import Foundation
import MCP
import Logging

/// Main class for handling MCP (Model Control Protocol) communications
@available(macOS 14.0, *)
public final class EasyMCP: @unchecked Sendable {
    // Internal MCP instance
    private var server: MCP.Server?
    // Transport instance
    private var transport: (any MCP.Transport)?
    // Server task
    private var serverTask: Task<Void, Swift.Error>?
    // Flag to track if server is running
    private var isRunning = false
    // Logger instance
    private let logger = Logger(label: "com.milestonemade.easymcp")

    /// Initializes a new EasyMCP instance
    public init() {
        // Initialize the MCP server with basic capabilities
        server = MCP.Server(
            name: "EasyMCP",
            version: "0.1.0",
            capabilities: MCP.Server.Capabilities(
                tools: .init(listChanged: true)
            )
        )
    }

    /// Start the MCP server with stdio transport
    public func start() async throws {
        guard !isRunning else {
            logger.logfmt(.info, ["msg": "Server is already running"])
            return
        }

        guard let server = server else {
            throw NSError(domain: "EasyMCP", code: 1, userInfo: [NSLocalizedDescriptionKey: "Server not initialized"])
        }

        // Create a transport for stdin/stdout communication
        let stdioTransport = MCP.StdioTransport(logger: logger)
        self.transport = stdioTransport

        // Register tool handlers
        await registerTools()

        // Start the server
        serverTask = Task<Void, Swift.Error> {
            do {
                try await server.start(transport: stdioTransport)
                isRunning = true
                logger.logfmt(.info, ["msg": "EasyMCP server started"])
            } catch {
                logger.logfmt(.error, ["msg": "Error starting EasyMCP server", "error": "\(error)"])
                throw error
            }
        }
    }

    public func waitUntilComplete() async throws {
        try await serverTask?.value
        await server?.waitUntilComplete()
    }


    /// Stop the MCP server
    public func stop() async {
        guard isRunning, let server = server else {
            return
        }

        await server.stop()
        serverTask?.cancel()
        isRunning = false
        logger.logfmt(.info, ["msg": "EasyMCP server stopped"])
    }

    /// Register MCP tools
    private func registerTools() async {
        guard let server = server else { return }

        // Register the tools/list handler
        await server.withMethodHandler(MCP.ListTools.self) { _ in
            // Define our hello tool
            let helloWorldTool = MCP.Tool(
                name: "helloWorld",
                description: "Returns a friendly greeting message",
                inputSchema: ["type": "object", "properties": [:]]  // No input parameters needed for this simple example
            )

            let helloPersonTool = MCP.Tool(
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
            )

            return MCP.ListTools.Result(tools: [helloWorldTool, helloPersonTool])
        }

        // Register the tools/call handler
        await server.withMethodHandler(MCP.CallTool.self) { [weak self] params in
            guard let self = self else {
                return MCP.CallTool.Result(
                    content: [.text("Service unavailable")],
                    isError: true
                )
            }

            switch params.name {
            case "helloWorld":
                let response = self.helloworld()
                return MCP.CallTool.Result(
                    content: [.text(response)],
                    isError: false
                )
            case "helloPerson":
                guard
                    let args = params.arguments,
                    let name = args["name"]?.stringValue
                else {
                    return MCP.CallTool.Result(
                        content: [.text("Missing parameter 'name' for tool: \(params.name)")],
                        isError: true
                    )
                }
                let response = self.hello(name)
                return MCP.CallTool.Result(
                    content: [.text(response)],
                    isError: false
                )
            default:
                return MCP.CallTool.Result(
                    content: [.text("Tool not found: \(params.name)")],
                    isError: true
                )
            }
        }
    }

    /// A simple example method
    public func helloworld() -> String {
        return "Hello iOS Folks! MCP SDK is configured and ready."
    }

    public func hello(_ name: String) -> String {
        return "Hello \(name)! MCP SDK is configured and ready."
    }
}
