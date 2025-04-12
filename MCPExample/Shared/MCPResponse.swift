import Foundation
import EasyMacMCP

/// Represents responses sent from the main app back to the helper
public enum MCPResponse: MCPResponseProtocol {
    /// A tool with no parameters that returns a greeting
    case helloWorld(helperId: String, messageId: String, result: String)

    /// A tool that accepts a name and returns a personalized greeting
    case helloPerson(helperId: String, messageId: String, result: String)

    /// An error response containing the error message
    case error(helperId: String, messageId: String, message: String)

    /// Returns the helperId for this response
    public var helperId: String {
        switch self {
        case .helloWorld(let helperId, _, _):
            return helperId
        case .helloPerson(let helperId, _, _):
            return helperId
        case .error(let helperId, _, _):
            return helperId
        }
    }

    /// Returns the messageId for this response
    public var messageId: String {
        switch self {
        case .helloWorld(_, let messageId, _):
            return messageId
        case .helloPerson(_, let messageId, _):
            return messageId
        case .error(_, let messageId, _):
            return messageId
        }
    }
} 