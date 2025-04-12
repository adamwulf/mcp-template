import Foundation
import EasyMCP
import MCP
import Logging

/// A class for handling MCP communications with Mac-specific request/response protocols
@available(macOS 14.0, *)
public final class EasyMacMCP<Request: MCPRequestProtocol, Response: MCPResponseProtocol>: @unchecked Sendable {

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
    // Response pipe for receiving messages from the host app
    private let responsePipe: HelperResponsePipe
    // Response manager for matching requests and responses
    private let responseManager: ResponseManager<Response>
    // Task for the response reader
    private var responseReaderTask: Task<Void, Never>?
    // Tools with handlers
    private var tools: [String: ToolRegistration] = [:]
    // Request builder
    private let requestBuilder: (String, String, [String: Value], String) throws -> Request

    /// Initializes a new EasyMacMCP instance
    /// - Parameters:
    ///   - helperId: The unique ID for this helper
    ///   - requestPipe: The pipe to write requests to
    ///   - responsePipe: The pipe to read responses from
    ///   - requestBuilder: A function that builds a Request from helperId, messageId, arguments, and toolName
    ///   - logger: Optional logger for diagnostics
    public init(
        helperId: String,
        requestPipe: HelperRequestPipe,
        responsePipe: HelperResponsePipe,
        requestBuilder: @escaping (String, String, [String: Value], String) throws -> Request,
        logger: Logger? = nil
    ) {
        self.helperId = helperId
        self.requestPipe = requestPipe
        self.responsePipe = responsePipe
        self.requestBuilder = requestBuilder
        self.logger = logger
        self.responseManager = ResponseManager()

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
        try await responsePipe.open()

        // Start the response reader
        startResponseReader()

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

        // Stop the response reader
        responseReaderTask?.cancel()

        // Close the pipes
        await requestPipe.close()
        await responsePipe.close()

        await server.stop()
        serverTask?.cancel()
        isRunning = false
        logger?.info("EasyMacMCP server stopped")
    }

    // MARK: - Response Reader

    /// Start reading responses from the response pipe
    private func startResponseReader() {
        responseReaderTask?.cancel()

        responseReaderTask = Task {
            do {
                while !Task.isCancelled {
                    if let line = try await responsePipe.readLine() {
                        // Try to decode the response directly to the Response type
                        if let responseData = line.data(using: .utf8) {
                            do {
                                let decoder = JSONDecoder()
                                let response = try decoder.decode(Response.self, from: responseData)
                                await responseManager.handleResponse(response)
                            } catch {
                                logger?.error("Failed to decode response: \(error)")
                            }
                        } else {
                            logger?.error("Failed to convert response to data: \(line)")
                        }
                    }
                }
            } catch {
                logger?.error("Error in response reader: \(error)")
            }
        }
    }

    // MARK: - Tools

    /// Automatically register all tools from Request.allCases
    private func registerToolsFromCases() async throws {
        guard let server = server else { return }

        // Collect valid tools from Request.allCases
        let validTools = Request.allCases.compactMap { requestCase -> (String, ToolMetadata)? in
            guard let metadata = requestCase.toolMetadata else { return nil }
            return (metadata.name, metadata)
        }

        // Register each unique tool (using a dictionary to ensure uniqueness by name)
        let toolDict = Dictionary(validTools) { first, _ in first }

        for (toolName, metadata) in toolDict {
            let schema: Value = metadata.inputSchema ?? ["type": "object", "properties": [:]]

            let tool = Tool(
                name: metadata.name,
                description: metadata.description,
                inputSchema: schema
            )

            // Store the tool registration
            tools[toolName] = ToolRegistration(tool: tool, name: toolName)

            // Create a sendable copy of the tool name for the closure
            let toolNameCopy = toolName

            // Register the tool handler
            await server.withMethodHandler(MCP.CallTool.self) { [weak self] params in
                guard let self = self else {
                    return MCP.CallTool.Result(
                        content: [.text("Service unavailable")],
                        isError: true
                    )
                }

                // Only handle calls to this specific tool
                guard params.name == toolNameCopy else {
                    return MCP.CallTool.Result(
                        content: [.text("Tool not found or not handled by this server")],
                        isError: true
                    )
                }

                do {
                    // Generate a message ID for this request
                    let messageId = UUID().uuidString

                    // Create a request using the provided builder and the tool name
                    let request = try self.requestBuilder(
                        self.helperId,
                        messageId,
                        params.arguments ?? [:],
                        toolNameCopy
                    )

                    // Send the request through the pipe
                    try await self.requestPipe.sendRequest(request)

                    // Wait for the response with a timeout
                    let timeout: TimeInterval = 10.0 // 10 second timeout
                    let response = try await self.responseManager.waitForResponse(
                        helperId: self.helperId,
                        messageId: messageId,
                        timeout: timeout
                    )

                    // Convert the response to the MCP.CallTool.Result format
                    return MCP.CallTool.Result(
                        content: [.text(String(describing: response))],
                        isError: false
                    )
                } catch {
                    return MCP.CallTool.Result(
                        content: [.text("Error executing tool: \(error)")],
                        isError: true
                    )
                }
            }
        }

        // Notify clients if tools were registered and the server is running
        if !tools.isEmpty && isRunning {
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

            // Return our registered tools
            let allTools = Array(self.tools.values.map { $0.tool })
            return MCP.ListTools.Result(tools: allTools)
        }

        await server.withMethodHandler(MCP.ListPrompts.self) { _ in
            return ListPrompts.Result(prompts: [])
        }

        await server.withMethodHandler(MCP.ListResources.self) { _ in
            return ListResources.Result(resources: [])
        }
    }
}
