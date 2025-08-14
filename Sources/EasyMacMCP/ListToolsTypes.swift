import Foundation
import MCP
import Logging

/// Request for listing available tools, sent from helper to Mac app
public struct ListToolsRequest: MCPRequestProtocol, Codable {
    public let helperId: String
    public let messageId: String

    public var isInitialize: Bool { false }
    public var isDeinitialize: Bool { false }

    public init(helperId: String, messageId: String) {
        self.helperId = helperId
        self.messageId = messageId
    }

    /// This won't be called for ListTools since it's handled specially
    public static func create(helperId: String, messageId: String, parameters: MCP.CallTool.Parameters) throws -> Self {
        throw NSError(
            domain: "ListToolsRequest",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "ListToolsRequest is not a callable tool"]
        )
    }
}

/// Response containing the list of available tools, sent from Mac app to helper
public struct ListToolsResponse: MCPResponseProtocol, Codable {
    public let helperId: String
    public let messageId: String
    public let tools: [ToolMetadata]

    public init(helperId: String, messageId: String, tools: [ToolMetadata]) {
        self.helperId = helperId
        self.messageId = messageId
        self.tools = tools
    }

    /// Not used for ListTools responses
    public func asResult() -> MCP.CallTool.Result {
        return MCP.CallTool.Result(content: [], isError: false)
    }

    /// Convert this response to MCP.ListTools.Result format
    public func asMCPToolsList() -> MCP.ListTools.Result {
        let mcpTools = tools.map { metadata in
            MCP.Tool(
                name: metadata.name,
                description: metadata.description,
                inputSchema: metadata.inputSchema ?? ["type": "object", "properties": [:]]
            )
        }
        return MCP.ListTools.Result(tools: mcpTools)
    }
}
