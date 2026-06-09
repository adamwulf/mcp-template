import Foundation
import Logging

/// Actor that wraps a ReadPipe for receiving responses from the Mac app
public actor HelperResponsePipe {
    public enum Error: Swift.Error {
        case decodeError(_ error: Swift.Error)
        case readError(_ error: Swift.Error)
    }

    private let readPipe: ReadPipe
    private let logger: Logger?
    private var readingTask: Task<Void, Never>?
    private var isReading = false

    /// Initialize with a pipe URL specific to this helper
    /// - Parameters:
    ///   - url: URL to the helper-specific response pipe
    ///   - logger: Optional logger for debugging
    public init(url: URL, logger: Logger? = nil) throws {
        self.readPipe = try ReadPipe(url: url)
        self.logger = logger
    }

    /// Open the pipe for reading
    public func open() async throws {
        try await readPipe.open()
    }

    /// Close the pipe. Stops any in-flight reading Task first so the
    /// underlying ReadPipe can tear down without racing against dispatch_io
    /// — see `ReadPipe.signalReaderWake()` for the rationale.
    public func close() async {
        await stopReading()
        await readPipe.close()
    }

    /// Wake any in-flight `readLine()` so a cancelled consumer Task can
    /// exit. Pass-through to the underlying ReadPipe. See
    /// `ReadPipe.signalReaderWake()` for details.
    public func signalReaderWake() async {
        await readPipe.signalReaderWake()
    }

    /// Start continuously reading responses from the pipe
    /// - Parameter responseHandler: Callback for handling received responses
    public func startReading<Response: MCPResponseProtocol & Decodable>(responseHandler: @escaping (Response) -> Void) async {
        guard !isReading else { return }
        isReading = true

        readingTask?.cancel()

        readingTask = Task {
            do {
                while isReading && !Task.isCancelled {
                    if let line = try await readPipe.readLine() {
                        if let response = try? parseResponse(from: line, as: Response.self) {
                            responseHandler(response)
                        } else {
                            logger?.error("Failed to parse response: \(line)")
                        }
                    }
                }
            } catch {
                logger?.error("Error in read loop: \(error.localizedDescription)")
                isReading = false
            }
        }
    }

    /// Stop reading responses. Cancels the reader Task, wakes any in-flight
    /// `readLine()` via the underlying ReadPipe's keepalive sentinel, then
    /// awaits the Task to exit. This sequence is required to avoid
    /// deadlocking the subsequent `readPipe.close()` against dispatch_io
    /// (see `ReadPipe.signalReaderWake()`).
    public func stopReading() async {
        isReading = false
        let task = readingTask
        readingTask = nil
        task?.cancel()
        await readPipe.signalReaderWake()
        _ = await task?.value
    }

    /// Read a single response from the pipe
    /// - Returns: The response as a String
    public func readLine() async throws -> String? {
        let line = try await readPipe.readLine()
        if let line = line {
            logger?.info("HELPER_RESPONSE_PIPE: Read line from pipe: \(line)")
        }
        return line
    }

    /// Read and decode a single response from the pipe
    /// - Returns: The decoded Response or nil if end of stream or decoding fails
    public func readResponse<Response: Decodable>() async throws -> Response? {
        guard let string = try await readPipe.readLine() else {
            return nil
        }

        logger?.info("HELPER_RESPONSE_PIPE: Raw response: \(string)")
        return try parseResponse(from: string, as: Response.self)
    }

    /// Parse a response string to a specific type
    /// - Parameters:
    ///   - string: The string to parse
    ///   - type: The type to decode to
    /// - Returns: The decoded response
    /// - Throws: Error if parsing fails
    private func parseResponse<T: Decodable>(from string: String, as type: T.Type) throws -> T {
        do {
            let decoder = JSONDecoder()
            let result = try decoder.decode(type, from: Data(string.utf8))

            // Try to log message ID if it's a response protocol
            if let response = result as? any MCPResponseProtocol {
                logger?.info("HELPER_RESPONSE_PIPE: Successfully decoded response with messageId: \(response.messageId), helperId: \(response.helperId)")
            } else {
                logger?.info("HELPER_RESPONSE_PIPE: Successfully decoded \(T.self)")
            }

            return result
        } catch {
            logger?.error("HELPER_RESPONSE_PIPE: Error decoding response: \(error.localizedDescription)")
            throw Error.decodeError(error)
        }
    }
}
