import Foundation
import MCP

/// Protocol defining requirements for MCP request types
public protocol MCPRequestProtocol: Codable, Sendable, CaseIterable {
    /// Returns the helper ID associated with this request
    var helperId: String { get }

    /// Returns the message ID for this request if applicable
    var messageId: String { get }

    /// Returns the tool metadata for this specific request case
    var toolMetadata: ToolMetadata? { get }

    /// Initialize a request from MCP call parameters
    /// - Parameters:
    ///   - helperId: The helper ID for the request
    ///   - messageId: A unique message ID for this request
    ///   - parameters: The MCP call parameters
    /// - Returns: An initialized request
    /// - Throws: Error if the parameters are invalid or can't be converted
    static func create(helperId: String, messageId: String, parameters: MCP.CallTool.Parameters) throws -> Self
}

/// Metadata for MCP tools
public struct ToolMetadata: Sendable {
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
    func asResult() -> MCP.CallTool.Result
}
