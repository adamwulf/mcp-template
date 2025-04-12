import Foundation
import EasyMacMCP

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
} 