//
//  HostRequestPipe.swift
//  MCPExample
//
//  Created by Adam Wulf on 4/6/25.
//

import Foundation
import Logging

/// Actor that wraps a ReadPipe for receiving requests from MCP helpers
public actor HostRequestPipe<Request: MCPRequestProtocol>: MCPRequestPipeReadable {
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
    ///   - readPipe: The pipe to read from
    ///   - logger: Optional logger for debugging
    public init(readPipe: ReadPipe, logger: Logger? = nil) {
        self.readPipe = readPipe
        self.logger = logger
    }

    /// Open the pipe for reading
    public func open() async throws {
        try await readPipe.open()
    }

    /// Close the pipe
    public func close() async {
        await stopReading()
        await readPipe.close()
    }

    /// Start continuously reading requests from the pipe
    /// - Parameter requestHandler: Callback for handling received requests
    public func startReading(requestHandler: @Sendable @escaping (Request) async -> Void) async {
        guard !isReading else { return }
        isReading = true

        readingTask?.cancel()

        readingTask = Task {
            do {
                while isReading && !Task.isCancelled {
                    if let request = try await readRequest() {
                        await requestHandler(request)
                    }
                }
            } catch {
                logger?.error("Error in read loop: \(error.localizedDescription)")
                isReading = false
            }
        }
    }

    /// Stop reading requests
    public func stopReading() async {
        isReading = false
        readingTask?.cancel()
        readingTask = nil
    }

    /// Read a single request from the pipe
    /// - Returns: The decoded MCPRequest or nil if end of stream
    func readRequest() async throws -> Request? {
        guard let string = try await readPipe.readLine() else {
            return nil
        }

        logger?.info("HOST_REQUEST_PIPE: Raw request: \(string)")

        do {
            let decoder = JSONDecoder()
            let request = try decoder.decode(Request.self, from: Data(string.utf8))
            logger?.info("HOST_REQUEST_PIPE: Successfully decoded request from helper \(request.helperId) with messageId: \(request.messageId)")
            return request
        } catch {
            logger?.error("HOST_REQUEST_PIPE: Error decoding request: \(error.localizedDescription)")
            throw Error.decodeError(error)
        }
    }
}
