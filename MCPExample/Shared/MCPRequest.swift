import Foundation
import EasyMacMCP
import MCP

/// Represents tool requests sent from the helper to the main app
public enum MCPRequest: MCPRequestProtocol {

    case initialize(helperId: String)
    case deinitialize(helperId: String)

    /// A tool with no parameters that returns a greeting
    case helloWorld(helperId: String, messageId: String)
    static let HelloWorld = "mcp_mcpexample_helloWorld"

    /// A tool that accepts a name and returns a personalized greeting
    case helloPerson(helperId: String, messageId: String, name: String)
    static let HelloPerson = "mcp_mcpexample_helloPerson"

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
    public var messageId: String {
        switch self {
        case .initialize(let helperId):
            return "init_\(helperId)"
        case .deinitialize(let helperId):
            return "deinit_\(helperId)"
        case .helloWorld(_, let messageId):
            return messageId
        case .helloPerson(_, let messageId, _):
            return messageId
        }
    }

    public var isInitialize: Bool {
        guard case .initialize = self else { return false }
        return true
    }

    public var isDeinitialize: Bool {
        guard case .deinitialize = self else { return false }
        return true
    }

    /// Returns tool metadata for this request case
    public static var toolMetadata: [ToolMetadata] {
        return [
            ToolMetadata(
                name: Self.HelloWorld,
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
            ),
            ToolMetadata(
                name: Self.HelloPerson,
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
        ]
    }

    /// Create a request from MCP call parameters
    /// - Parameters:
    ///   - helperId: The helper ID for the request
    ///   - messageId: A unique message ID for this request
    ///   - parameters: The MCP call parameters
    /// - Returns: An initialized request
    /// - Throws: Error if the parameters are invalid or can't be converted
    public static func create(helperId: String, messageId: String, parameters: MCP.CallTool.Parameters) throws -> MCPRequest {
        switch parameters.name {
        case Self.HelloWorld:
            return .helloWorld(helperId: helperId, messageId: messageId)

        case Self.HelloPerson:
            let name = parameters.arguments?["name"]?.stringValue ?? "Anonymous"
            return .helloPerson(helperId: helperId, messageId: messageId, name: name)

        default:
            throw NSError(domain: "MCPRequest", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unknown tool: \(parameters.name)"])
        }
    }
}
