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

    /// Close the pipe
    public func close() async {
        stopReading()
        await readPipe.close()
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

    /// Stop reading responses
    public func stopReading() {
        isReading = false
        readingTask?.cancel()
        readingTask = nil
    }

    /// Read a single response from the pipe
    /// - Returns: The response as a String
    public func readLine() async throws -> String? {
        return try await readPipe.readLine()
    }
    
    /// Read and decode a single response from the pipe
    /// - Returns: The decoded Response or nil if end of stream or decoding fails
    public func readResponse<Response: Decodable>() async throws -> Response? {
        guard let string = try await readPipe.readLine() else {
            return nil
        }

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
            return try decoder.decode(type, from: Data(string.utf8))
        } catch {
            logger?.error("Error decoding response: \(error.localizedDescription)")
            throw Error.decodeError(error)
        }
    }
} 