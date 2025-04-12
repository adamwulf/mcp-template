import Foundation

/// A wrapper for MCP tools that uses the ResponseManager to wait for responses
public class MCPTools<Request: MCPRequestProtocol, Response: MCPResponseProtocol> {
    private let writePipe: PipeWritable
    private let responseManager: ResponseManager<Response>
    private let helperId: String
    private let requestBuilder: (String, String, String?) -> Request

    /// Initializes a new MCPTools instance
    /// - Parameters:
    ///   - helperId: The helper ID to use for requests
    ///   - writePipe: The pipe to write requests to
    ///   - responseManager: The response manager to use for waiting for responses
    ///   - requestBuilder: A closure that builds requests with the specified parameters
    public init(
        helperId: String,
        writePipe: PipeWritable,
        responseManager: ResponseManager<Response>,
        requestBuilder: @escaping (String, String, String?) -> Request
    ) {
        self.helperId = helperId
        self.writePipe = writePipe
        self.responseManager = responseManager
        self.requestBuilder = requestBuilder
    }

    /// Calls the helloWorld tool
    /// - Parameter timeout: Optional timeout in seconds (default: 5.0)
    /// - Returns: The greeting string
    /// - Throws: Error if the request fails or times out
    public func helloWorld(timeout: TimeInterval = 5.0) async throws -> String {
        let messageId = UUID().uuidString
        let request = requestBuilder(helperId, messageId, nil)

        try await sendRequest(request)
        let response = try await responseManager.waitForResponse(
            helperId: helperId,
            messageId: messageId,
            timeout: timeout
        )

        // Response handling is left to the caller
        return try handleResponse(response)
    }

    /// Calls the helloPerson tool
    /// - Parameters:
    ///   - name: The name to greet
    ///   - timeout: Optional timeout in seconds (default: 5.0)
    /// - Returns: The personalized greeting string
    /// - Throws: Error if the request fails or times out
    public func helloPerson(name: String, timeout: TimeInterval = 5.0) async throws -> String {
        let messageId = UUID().uuidString
        let request = requestBuilder(helperId, messageId, name)

        try await sendRequest(request)
        let response = try await responseManager.waitForResponse(
            helperId: helperId,
            messageId: messageId,
            timeout: timeout
        )

        // Response handling is left to the caller
        return try handleResponse(response)
    }

    /// Sends a request to the app
    /// - Parameter request: The request to send
    /// - Throws: Error if sending fails
    private func sendRequest(_ request: Request) async throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted

        let data = try encoder.encode(request)
        guard let jsonString = String(data: data, encoding: .utf8) else {
            throw NSError(domain: "MCPError", code: 2, userInfo: [NSLocalizedDescriptionKey: "Encoding error"])
        }

        try await writePipe.write(jsonString)
    }

    /// Handle the response from the server
    /// - Parameter response: The response to handle
    /// - Returns: The result string
    /// - Throws: An error if handling fails
    public func handleResponse(_ response: Response) throws -> String {
        // This method should be overridden by subclasses or customized by users
        // of the library to handle their specific response types
        throw ResponseError.invalidResponse
    }
}
