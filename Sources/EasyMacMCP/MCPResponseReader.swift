import Foundation

/// A reader for MCP responses that dispatches them to a ResponseManager
public actor MCPResponseReader<Response: MCPResponseProtocol> {
    private let pipe: PipeReadable
    private let responseManager: ResponseManager<Response>
    private var readTask: Task<Void, Never>?
    private var isReading = false
    private let responseDecoder: (String) -> Response?

    /// Initializes a new response reader
    /// - Parameters:
    ///   - pipe: The pipe to read responses from
    ///   - responseManager: The response manager to dispatch responses to
    ///   - responseDecoder: A closure that decodes a string into a Response
    public init(
        pipe: PipeReadable,
        responseManager: ResponseManager<Response>,
        responseDecoder: @escaping (String) -> Response?
    ) {
        self.pipe = pipe
        self.responseManager = responseManager
        self.responseDecoder = responseDecoder
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
                        if let response = responseDecoder(line) {
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
}
