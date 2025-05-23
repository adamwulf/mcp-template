import Foundation
import EasyMCP
import MCP
import Logging

/// A class for handling MCP communications with Mac-specific request/response protocols
public final class EasyMCPHelper<Request: MCPRequestProtocol, Response: MCPResponseProtocol>: @unchecked Sendable {

    public enum Error: Swift.Error {
        case serverHasNotStarted
        case encodingError
        case decodingError
        case timeout
        case noResponse
        case invalidCase
    }

    private struct ToolRegistration {
        let tool: MCP.Tool
        let name: String
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
    // Helper ID for this MCP instance
    private let helperId: String
    // Request pipe for sending messages to the host app
    private let requestPipe: HelperRequestPipe
    // Response manager for matching requests and responses
    private let responseManager: ResponseManager<Response>
    // Tools with handlers
    private var tools: [String: ToolRegistration] = [:]

    /// Initializes a new EasyMacMCP instance
    /// - Parameters:
    ///   - helperId: The unique ID for this helper
    ///   - requestPipe: The pipe to write requests to
    ///   - responsePipe: The pipe to read responses from
    ///   - logger: Optional logger for diagnostics
    public init(
        helperId: String,
        requestPipe: HelperRequestPipe,
        responsePipe: HelperResponsePipe,
        logger: Logger? = nil
    ) {
        self.helperId = helperId
        self.requestPipe = requestPipe
        self.responseManager = ResponseManager(responsePipe: responsePipe, logger: logger)
        self.logger = logger

        // Initialize the MCP server with basic capabilities
        server = MCP.Server(
            name: "EasyMacMCP",
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
            logger?.warning("Server is already running")
            return
        }

        guard let server = server else {
            throw NSError(domain: "EasyMacMCP", code: 1, userInfo: [NSLocalizedDescriptionKey: "Server not initialized"])
        }

        // Create a transport for stdin/stdout communication
        let stdioTransport = MCP.StdioTransport(logger: logger)
        self.transport = stdioTransport

        // Register tools automatically based on Request.allCases
        try await registerToolsFromCases()

        // Register standard MCP handlers
        await registerTools()

        // Open the pipes
        try await requestPipe.open()

        // Start the response manager
        try await responseManager.startReading()

        // Start the server
        serverTask = Task<Void, Swift.Error> {
            do {
                try await server.start(transport: stdioTransport)
                isRunning = true
                logger?.info("EasyMacMCP server started")
            } catch {
                logger?.error("Error starting EasyMacMCP server: \(error)")
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

        // Stop the response manager
        await responseManager.stopReading()

        // Close the pipes
        await requestPipe.close()

        await server.stop()
        serverTask?.cancel()
        isRunning = false
        logger?.info("EasyMacMCP server stopped")
    }

    // MARK: - Tools

    /// Collect available tools from Request.allCases
    private func registerToolsFromCases() async throws {
        // Clear any existing tools
        tools.removeAll()

        // Create all the tool registrations
        for metadata in Request.toolMetadata {
            let schema: Value = metadata.inputSchema ?? ["type": "object", "properties": [:]]

            let tool = Tool(
                name: metadata.name,
                description: metadata.description,
                inputSchema: schema
            )

            // Store the tool registration
            tools[metadata.name] = ToolRegistration(tool: tool, name: metadata.name)
        }

        // Notify clients if tools were registered and the server is running
        if !tools.isEmpty && isRunning {
            try await server?.notify(ToolListChangedNotification.message())
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

            // Return our registered tools
            let allTools = Array(self.tools.values.map { $0.tool })
            return MCP.ListTools.Result(tools: allTools)
        }

        // Register a single CallTool handler for all tools
        await server.withMethodHandler(MCP.CallTool.self) { [weak self] params in
            guard let self = self else {
                return MCP.CallTool.Result(
                    content: [.text("Service unavailable")],
                    isError: true
                )
            }

            // Check if we have this tool registered
            guard self.tools[params.name] != nil else {
                return MCP.CallTool.Result(
                    content: [.text("Tool not found: \(params.name)")],
                    isError: true
                )
            }

            do {
                // Generate a message ID for this request
                let messageId = UUID().uuidString
                logger?.info("HELPER: Generated message ID: \(messageId) for tool: \(params.name)")

                // Create a request using the Request.create static method
                let request = try Request.create(
                    helperId: self.helperId,
                    messageId: messageId,
                    parameters: params
                )

                // Log the request object
                if let requestData = try? JSONEncoder().encode(request),
                   let requestString = String(data: requestData, encoding: .utf8) {
                    logger?.info("HELPER: Sending request: \(requestString)")
                }

                // Send the request through the pipe
                try await self.requestPipe.sendRequest(request)
                logger?.info("HELPER: Request sent with messageId: \(messageId)")

                // Wait for the response with a timeout
                let timeout: TimeInterval = 10.0 // 10 second timeout
                logger?.info("HELPER: Waiting for response with messageId: \(messageId)")
                let response = try await self.responseManager.waitForResponse(
                    helperId: self.helperId,
                    messageId: messageId,
                    timeout: timeout
                )

                logger?.info("HELPER: Received response with messageId: \(response.messageId)")

                // Convert the response to the MCP.CallTool.Result format using the response's own method
                return response.asResult()
            } catch {
                return MCP.CallTool.Result(
                    content: [.text("Error executing tool: \(error)")],
                    isError: true
                )
            }
        }

        await server.withMethodHandler(MCP.ListPrompts.self) { _ in
            return ListPrompts.Result(prompts: [])
        }

        await server.withMethodHandler(MCP.ListResources.self) { _ in
            return ListResources.Result(resources: [])
        }
    }
}
