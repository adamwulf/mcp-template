import Foundation

/// Errors that can occur during response handling
public enum ResponseError: Error, Equatable {
    case timeout
    case requestCancelled
    case invalidResponse
}

/// A manager that coordinates requests and responses between the helper and the app
/// Matches responses from the app to pending requests from the helper based on helperId and messageId
public actor ResponseManager<Response: MCPResponseProtocol> {
    // Map from "{helperId}:{messageId}" to continuation
    private var pendingRequests: [String: CheckedContinuation<Response, Error>] = [:]

    public init() {}

    /// Wait for a response with the given helperId and messageId
    /// - Parameters:
    ///   - helperId: The helper ID that originated the request
    ///   - messageId: The message ID to match with the response
    ///   - timeout: The timeout in seconds (default: 5.0)
    /// - Returns: The matched response
    /// - Throws: ResponseError if the request times out or is cancelled
    public func waitForResponse(helperId: String, messageId: String, timeout: TimeInterval = 5.0) async throws -> Response {
        let requestKey = "\(helperId):\(messageId)"

        return try await withCheckedThrowingContinuation { continuation in
            pendingRequests[requestKey] = continuation

            // Setup timeout
            Task {
                try await Task.sleep(for: .seconds(timeout))
                await timeoutRequest(helperId: helperId, messageId: messageId)
            }
        }
    }

    /// Handle a response received from the app
    /// - Parameter response: The response to process
    public func handleResponse(_ response: Response) async {
        let messageId = response.messageId

        let requestKey = "\(response.helperId):\(messageId)"
        guard let continuation = pendingRequests.removeValue(forKey: requestKey) else {
            return // No waiting continuation for this response
        }

        continuation.resume(returning: response)
    }

    /// Cancel a pending request
    /// - Parameters:
    ///   - helperId: The helper ID of the request to cancel
    ///   - messageId: The message ID of the request to cancel
    public func cancelRequest(helperId: String, messageId: String) async {
        let requestKey = "\(helperId):\(messageId)"
        guard let continuation = pendingRequests.removeValue(forKey: requestKey) else {
            return // Already handled or doesn't exist
        }

        continuation.resume(throwing: ResponseError.requestCancelled)
    }

    /// Handle timeout for a request
    /// - Parameters:
    ///   - helperId: The helper ID of the request that timed out
    ///   - messageId: The message ID of the request that timed out
    private func timeoutRequest(helperId: String, messageId: String) async {
        let requestKey = "\(helperId):\(messageId)"
        guard let continuation = pendingRequests.removeValue(forKey: requestKey) else {
            return // Already handled
        }

        continuation.resume(throwing: ResponseError.timeout)
    }
}
