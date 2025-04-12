//
//  HostRequestPipe.swift
//  MCPExample
//
//  Created by Adam Wulf on 4/6/25.
//

import Foundation
import EasyMacMCP
import Logging

/// Actor that wraps a ReadPipe for receiving requests from MCP helpers
actor HostRequestPipe {
    enum Error: Swift.Error {
        case decodeError(_ error: Swift.Error)
        case readError(_ error: Swift.Error)
    }

    private let readPipe: ReadPipe
    private let logger: Logger?
    private var readingTask: Task<Void, Never>?
    private var isReading = false

    /// Initialize with the central request pipe URL
    /// - Parameters:
    ///   - url: URL to the central request pipe
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

    /// Start continuously reading requests from the pipe
    /// - Parameter requestHandler: Callback for handling received requests
    func startReading(requestHandler: @escaping (MCPRequest) -> Void) async {
        guard !isReading else { return }
        isReading = true

        readingTask?.cancel()

        readingTask = Task {
            do {
                while isReading && !Task.isCancelled {
                    if let request = try await readRequest() {
                        requestHandler(request)
                    }
                }
            } catch {
                logger?.error("Error in read loop: \(error.localizedDescription)")
                isReading = false
            }
        }
    }

    /// Stop reading requests
    func stopReading() {
        isReading = false
        readingTask?.cancel()
        readingTask = nil
    }

    /// Read a single request from the pipe
    /// - Returns: The decoded MCPRequest or nil if end of stream
    func readRequest() async throws -> MCPRequest? {
        guard let string = try await readPipe.readLine() else {
            return nil
        }

        logger?.info("HOST_REQUEST_PIPE: Raw request: \(string)")

        do {
            let decoder = JSONDecoder()
            let request = try decoder.decode(MCPRequest.self, from: Data(string.utf8))
            logger?.info("HOST_REQUEST_PIPE: Successfully decoded request from helper \(request.helperId) with messageId: \(request.messageId)")
            return request
        } catch {
            logger?.error("HOST_REQUEST_PIPE: Error decoding request: \(error.localizedDescription)")
            throw Error.decodeError(error)
        }
    }
}
