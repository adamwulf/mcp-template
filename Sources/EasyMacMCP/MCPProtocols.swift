import Foundation
import MCP

/// Protocol defining requirements for MCP request types
public protocol MCPRequestProtocol: Codable, Sendable {
    /// Returns the helper ID associated with this request
    var helperId: String { get }

    /// Returns the message ID for this request if applicable
    var messageId: String { get }

    /// `true` if the request represents the initialize message from a helper, `false` otherwise
    var isInitialize: Bool { get }

    /// `true` if the request represents the deinitialize message from a helper, `false` otherwise
    var isDeinitialize: Bool { get }

    /// Initialize a request from MCP call parameters
    /// - Parameters:
    ///   - helperId: The helper ID for the request
    ///   - messageId: A unique message ID for this request
    ///   - parameters: The MCP call parameters
    /// - Returns: An initialized request
    /// - Throws: Error if the parameters are invalid or can't be converted
    static func create(helperId: String, messageId: String, parameters: MCP.CallTool.Parameters) throws -> Self

    /// Create a ListTools request for requesting available tools
    /// - Parameters:
    ///   - helperId: The helper ID for the request
    ///   - messageId: A unique message ID for this request
    /// - Returns: A request instance for listing tools
    static func makeListToolsRequest(helperId: String, messageId: String) -> Self
}

/// Metadata for MCP tools
public struct ToolMetadata: Sendable, Codable {
    /// The name of the tool
    public let name: String

    /// A description of what the tool does
    public let description: String

    /// The input schema for the tool parameters
    public let inputSchema: Value?

    /// Creates a new tool metadata instance
    /// - Parameters:
    ///   - name: The name of the tool
    ///   - description: A description of what the tool does
    ///   - inputSchema: The input schema for the tool parameters
    public init(name: String, description: String, inputSchema: Value? = nil) {
        self.name = name
        self.description = description
        self.inputSchema = inputSchema
    }
}

/// Protocol defining requirements for MCP response types
public protocol MCPResponseProtocol: Codable, Sendable {
    /// Returns the helper ID associated with this response
    var helperId: String { get }

    /// Returns the message ID for this response
    var messageId: String { get }

    /// Convert this response to an MCP.CallTool.Result
    /// - Returns: A properly formatted result for the MCP tool call
    func asCallToolResult() -> MCP.CallTool.Result

    /// Create a ListTools response containing available tools
    /// - Parameters:
    ///   - helperId: The helper ID for the response
    ///   - messageId: The message ID matching the request
    ///   - tools: Array of available tool metadata
    /// - Returns: A response instance containing the tools
    static func makeListToolsResponse(helperId: String, messageId: String, tools: [ToolMetadata]) -> Self

    /// Convert this response to MCP.ListTools.Result format
    /// - Returns: A properly formatted MCP ListTools result, or nil if not a ListTools response
    func asListToolsResult() -> MCP.ListTools.Result?
}
