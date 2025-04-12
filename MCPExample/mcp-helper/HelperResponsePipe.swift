//
//  HelperResponsePipe.swift
//  MCPExample
//
//  Created by Adam Wulf on 4/6/25.
//

import Foundation
import EasyMacMCP
import Logging

/// Actor that wraps a ReadPipe for receiving responses from the Mac app
actor HelperResponsePipe {
    enum Error: Swift.Error {
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
    init(url: URL, logger: Logger? = nil) throws {
        self.readPipe = try ReadPipe(url: url)
        self.logger = logger
    }

    /// Open the pipe for reading
    func open() async throws {
        try await readPipe.open()
    }

    /// Close the pipe
    func close() async {
        stopReading()
        await readPipe.close()
    }

    /// Start continuously reading responses from the pipe
    /// - Parameter responseHandler: Callback for handling received responses
    func startReading(responseHandler: @escaping (MCPResponse) -> Void) async {
        guard !isReading else { return }
        isReading = true

        readingTask?.cancel()

        readingTask = Task {
            do {
                while isReading && !Task.isCancelled {
                    if let response = try await readResponse() {
                        responseHandler(response)
                    }
                }
            } catch {
                logger?.error("Error in read loop: \(error.localizedDescription)")
                isReading = false
            }
        }
    }

    /// Stop reading responses
    func stopReading() {
        isReading = false
        readingTask?.cancel()
        readingTask = nil
    }

    /// Read a single response from the pipe
    /// - Returns: The decoded MCPResponse or nil if end of stream
    func readResponse() async throws -> MCPResponse? {
        guard let string = try await readPipe.readLine() else {
            return nil
        }

        do {
            let decoder = JSONDecoder()
            return try decoder.decode(MCPResponse.self, from: Data(string.utf8))
        } catch {
            logger?.error("Error decoding response: \(error.localizedDescription)")
            throw Error.decodeError(error)
        }
    }
}
