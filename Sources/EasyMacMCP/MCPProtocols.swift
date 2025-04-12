import Foundation

/// Protocol defining requirements for MCP request types
public protocol MCPRequestProtocol: Codable, Sendable {
    /// Returns the helper ID associated with this request
    var helperId: String { get }

    /// Returns the message ID for this request if applicable
    var messageId: String? { get }
}

/// Protocol defining requirements for MCP response types
public protocol MCPResponseProtocol: Codable, Sendable {
    /// Returns the helper ID associated with this response
    var helperId: String { get }

    /// Returns the message ID for this response
    var messageId: String { get }
}
