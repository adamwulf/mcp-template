import Foundation

/// A reader for MCP responses that dispatches them to a ResponseManager
public actor MCPResponseReader {
    private let pipe: PipeReadable
    private let responseManager: ResponseManager
    private var readTask: Task<Void, Never>?
    private var isReading = false

    /// Initializes a new response reader
    /// - Parameters:
    ///   - pipe: The pipe to read responses from
    ///   - responseManager: The response manager to dispatch responses to
    public init(pipe: PipeReadable, responseManager: ResponseManager) {
        self.pipe = pipe
        self.responseManager = responseManager
    }

    deinit {
        isReading = false
        readTask?.cancel()
        readTask = nil
    }

    /// Starts reading responses from the pipe
    public func startReading() async {
        guard !isReading else { return }
        isReading = true

        readTask?.cancel()

        readTask = Task {
            do {
                try await pipe.open()

                while !Task.isCancelled && isReading {
                    if let line = try await pipe.readLine() {
                        if let response = parseResponse(line) {
                            await responseManager.handleResponse(response)
                        } else {
                            Logging.printError("Failed to parse response: \(line)")
                        }
                    }
                }
            } catch {
                Logging.printError("Error reading from response pipe", error: error)
                isReading = false
            }
        }
    }

    /// Stops reading responses from the pipe
    public func stopReading() {
        isReading = false
        readTask?.cancel()
        readTask = nil
    }

    /// Parses a JSON string into an MCPResponse
    /// - Parameter jsonString: The JSON string to parse
    /// - Returns: The parsed response, or nil if parsing fails
    private func parseResponse(_ jsonString: String) -> MCPResponse? {
        guard let data = jsonString.data(using: .utf8) else { return nil }

        do {
            return try JSONDecoder().decode(MCPResponse.self, from: data)
        } catch {
            Logging.printError("Error decoding response", error: error)
            return nil
        }
    }
}
