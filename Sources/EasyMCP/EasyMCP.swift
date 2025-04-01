// The Swift Programming Language
// https://docs.swift.org/swift-book

import Foundation
import MCP
import Logging

public typealias Tool = MCP.Tool
public typealias Result = MCP.CallTool.Result

/// Main class for handling MCP (Model Control Protocol) communications
@available(macOS 14.0, *)
public final class EasyMCP: @unchecked Sendable {

    enum Error: Swift.Error {
        case serverHasNotStarted
    }

    private struct ToolMeta {
        let tool: MCP.Tool
        let handler: ([String: Value]) async throws -> Result
    }

    // Internal MCP instance
    private var server: MCP.Server?
    // Transport instance
    private var transport: (any MCP.Transport)?
    // Server task
    private var serverTask: Task<Void, Swift.Error>?
    // Flag to track if server is running
    private var isRunning = false
    // Logger instance
    private let logger: Logger?
    // Tools
    private var tools: [String: ToolMeta] = [:]

    /// Initializes a new EasyMCP instance
    public init(logger: Logger? = nil) {
        self.logger = logger
        // Initialize the MCP server with basic capabilities
        server = MCP.Server(
            name: "EasyMCP",
            version: "0.1.0",
            capabilities: MCP.Server.Capabilities(
                prompts: .init(listChanged: false),
                resources: .init(subscribe: false, listChanged: false),
                tools: .init(listChanged: true)
            )
        )
    }

    // MARK: - Server Lifecycle

    /// Start the MCP server with stdio transport
    public func start() async throws {
        guard !isRunning else {
            logger?.logfmt(.info, ["msg": "Server is already running"])
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
                logger?.logfmt(.info, ["msg": "EasyMCP server started"])
            } catch {
                logger?.logfmt(.error, ["msg": "Error starting EasyMCP server", "error": "\(error)"])
                throw error
            }
        }
    }

    public func waitUntilComplete() async throws {
        try await serverTask?.value
        await server?.waitUntilCompleted()
    }

    /// Stop the MCP server
    public func stop() async {
        guard isRunning, let server = server else {
            return
        }

        await server.stop()
        serverTask?.cancel()
        isRunning = false
        logger?.logfmt(.info, ["msg": "EasyMCP server stopped"])
    }

    // MARK: - Tools

    // Register a tool with the server. The server must already be started to register a tool.
    public func register(tool: Tool, handler: @escaping ([String: Value]) async throws -> Result) async throws {
        guard let server = server else { return }
        if tool.inputSchema == nil {
            let inputSchema: Value = ["type": "object", "properties": [:]]
            let toolWithSchema = Tool(name: tool.name, description: tool.description, inputSchema: inputSchema)
            tools[tool.name] = ToolMeta(tool: toolWithSchema, handler: handler)
        } else {
            tools[tool.name] = ToolMeta(tool: tool, handler: handler)
        }

        if isRunning {
            try await server.notify(ToolListChangedNotification.message())
        }
    }

    // MARK: - Private

    /// Register MCP handlers to list and call tools
    private func registerTools() async {
        guard let server = server else { return }

        // Register the tools/list handler
        await server.withMethodHandler(MCP.ListTools.self) { [weak self] _ in
            guard let self = self else {
                return MCP.ListTools.Result(tools: [])
            }
            return MCP.ListTools.Result(tools: self.tools.values.map({ $0.tool }))
        }

        // Register the tools/call handler
        await server.withMethodHandler(MCP.CallTool.self) { [weak self] params in
            guard let self = self else {
                return MCP.CallTool.Result(
                    content: [.text("Service unavailable")],
                    isError: true
                )
            }

            guard let toolMeta = tools[params.name] else {
                return MCP.CallTool.Result(
                    content: [.text("Tool not found: \(params.name)")],
                    isError: true
                )
            }

            return try await toolMeta.handler(params.arguments ?? [:])
        }

        await server.withMethodHandler(MCP.ListPrompts.self) { [weak self] _ in
            guard let self = self else {
                return ListPrompts.Result(prompts: [])
            }
            return ListPrompts.Result(prompts: [])
        }

        await server.withMethodHandler(MCP.ListResources.self) { [weak self] _ in
            guard let self = self else {
                return ListResources.Result(resources: [])
            }
            return ListResources.Result(resources: [])
        }

    }
}
