import Foundation
import EasyMacMCP
import MCP

/// Represents tool requests sent from the helper to the main app
public enum MCPRequest: MCPRequestProtocol {
    case initialize(helperId: String)
    case deinitialize(helperId: String)

    /// A tool with no parameters that returns a greeting
    case helloWorld(helperId: String, messageId: String)

    /// A tool that accepts a name and returns a personalized greeting
    case helloPerson(helperId: String, messageId: String, name: String)

    /// Returns the helperId for this tool request
    public var helperId: String {
        switch self {
        case .initialize(let helperId):
            return helperId
        case .deinitialize(let helperId):
            return helperId
        case .helloWorld(let helperId, _):
            return helperId
        case .helloPerson(let helperId, _, _):
            return helperId
        }
    }

    /// Returns the messageId for this tool request
    public var messageId: String? {
        switch self {
        case .initialize: return nil
        case .deinitialize: return nil
        case .helloWorld(_, let messageId):
            return messageId
        case .helloPerson(_, let messageId, _):
            return messageId
        }
    }

    /// Returns tool metadata for this request case
    public var toolMetadata: ToolMetadata? {
        switch self {
        case .initialize, .deinitialize:
            // These are internal commands, not exposed as tools
            return nil

        case .helloWorld:
            return ToolMetadata(
                name: "mcp_mcpexample_helloWorld",
                description: "Returns a friendly greeting message",
                inputSchema: [
                    "type": "object",
                    "properties": [
                        "random_string": [
                            "type": "string",
                            "description": "Dummy parameter for no-parameter tools"
                        ]
                    ],
                    "required": ["random_string"]
                ]
            )

        case .helloPerson:
            return ToolMetadata(
                name: "mcp_mcpexample_helloPerson",
                description: "Returns a friendly greeting message",
                inputSchema: [
                    "type": "object",
                    "properties": [
                        "name": [
                            "type": "string",
                            "description": "Name to search for (will match given name or family name)"
                        ]
                    ]
                ]
            )
        }
    }

    /// List of all available cases for CaseIterable conformance
    public static var allCases: [MCPRequest] {
        return [
            .helloWorld(helperId: "placeholder", messageId: "placeholder"),
            .helloPerson(helperId: "placeholder", messageId: "placeholder", name: "placeholder")
        ]
    }
}
