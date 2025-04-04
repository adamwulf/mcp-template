import Foundation

/// A wrapper for MCP tools that uses the ResponseManager to wait for responses
public class MCPTools {
    private let writePipe: PipeWritable
    private let responseManager: ResponseManager
    private let helperId: String

    /// Initializes a new MCPTools instance
    /// - Parameters:
    ///   - helperId: The helper ID to use for requests
    ///   - writePipe: The pipe to write requests to
    ///   - responseManager: The response manager to use for waiting for responses
    public init(helperId: String, writePipe: PipeWritable, responseManager: ResponseManager) {
        self.helperId = helperId
        self.writePipe = writePipe
        self.responseManager = responseManager
    }

    /// Calls the helloWorld tool
    /// - Parameter timeout: Optional timeout in seconds (default: 5.0)
    /// - Returns: The greeting string
    /// - Throws: Error if the request fails or times out
    public func helloWorld(timeout: TimeInterval = 5.0) async throws -> String {
        let messageId = UUID().uuidString
        let request = MCPRequest.helloWorld(helperId: helperId, messageId: messageId)

        try await sendRequest(request)
        let response = try await responseManager.waitForResponse(
            helperId: helperId,
            messageId: messageId,
            timeout: timeout
        )

        switch response {
        case .helloWorld(_, _, let result):
            return result
        case .error(_, _, let message):
            throw NSError(domain: "MCPError", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
        default:
            throw ResponseError.invalidResponse
        }
    }

    /// Calls the helloPerson tool
    /// - Parameters:
    ///   - name: The name to greet
    ///   - timeout: Optional timeout in seconds (default: 5.0)
    /// - Returns: The personalized greeting string
    /// - Throws: Error if the request fails or times out
    public func helloPerson(name: String, timeout: TimeInterval = 5.0) async throws -> String {
        let messageId = UUID().uuidString
        let request = MCPRequest.helloPerson(helperId: helperId, messageId: messageId, name: name)

        try await sendRequest(request)
        let response = try await responseManager.waitForResponse(
            helperId: helperId,
            messageId: messageId,
            timeout: timeout
        )

        switch response {
        case .helloPerson(_, _, let result):
            return result
        case .error(_, _, let message):
            throw NSError(domain: "MCPError", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
        default:
            throw ResponseError.invalidResponse
        }
    }

    /// Sends a request to the app
    /// - Parameter request: The request to send
    /// - Throws: Error if sending fails
    private func sendRequest(_ request: MCPRequest) async throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted

        let data = try encoder.encode(request)
        guard let jsonString = String(data: data, encoding: .utf8) else {
            throw NSError(domain: "MCPError", code: 2, userInfo: [NSLocalizedDescriptionKey: "Encoding error"])
        }

        try await writePipe.write(jsonString)
    }
}
