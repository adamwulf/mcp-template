import Foundation
import Logging

/// Errors that can occur during response handling
public enum ResponseError: Error, Equatable {
    case timeout
    case requestCancelled
    case invalidResponse
    case readError(Error)

    public static func == (lhs: ResponseError, rhs: ResponseError) -> Bool {
        switch (lhs, rhs) {
        case (.timeout, .timeout):
            return true
        case (.requestCancelled, .requestCancelled):
            return true
        case (.invalidResponse, .invalidResponse):
            return true
        case (.readError(let lhsError), .readError(let rhsError)):
            return lhsError.localizedDescription == rhsError.localizedDescription
        default:
            return false
        }
    }
}

/// A manager that coordinates requests and responses between the helper and the app
/// Matches responses from the app to pending requests from the helper based on helperId and messageId
public actor ResponseManager<Response: MCPResponseProtocol> {
    // Map from "{helperId}:{messageId}" to continuation
    private var pendingRequests: [String: CheckedContinuation<Response, Error>] = [:]
    // Response pipe for receiving messages from the host app
    private let responsePipe: HelperResponsePipe
    // Task for the response reader
    private var responseReaderTask: Task<Void, Never>?
    // Logger instance
    private let logger: Logger?

    public init(responsePipe: HelperResponsePipe, logger: Logger? = nil) {
        self.responsePipe = responsePipe
        self.logger = logger
    }

    /// Start reading responses from the response pipe
    public func startReading() async throws {
        responseReaderTask?.cancel()

        // Open the pipe
        try await responsePipe.open()
        logger?.info("Response pipe opened, starting to read responses")

        responseReaderTask = Task {
            do {
                while !Task.isCancelled {
                    if let line = try await responsePipe.readLine() {
                        // Try to decode the response directly to the Response type
                        if let responseData = line.data(using: .utf8) {
                            do {
                                let decoder = JSONDecoder()
                                let response = try decoder.decode(Response.self, from: responseData)
                                logger?.debug("Received response: \(response)")
                                handleResponse(response)
                            } catch {
                                logger?.error("Failed to decode response: \(error)")
                            }
                        } else {
                            logger?.error("Failed to convert response to data: \(line)")
                        }
                    }
                }
            } catch {
                logger?.error("Error in response reader: \(error)")
            }
        }
    }

    /// Stop reading from the response pipe
    public func stopReading() async {
        responseReaderTask?.cancel()
        responseReaderTask = nil

        // Close the pipe
        await responsePipe.close()
        logger?.info("Response pipe closed, stopped reading responses")
    }

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
    private func handleResponse(_ response: Response) {
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
