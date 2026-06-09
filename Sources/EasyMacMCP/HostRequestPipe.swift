//
//  HostRequestPipe.swift
//  MCPExample
//
//  Created by Adam Wulf on 4/6/25.
//

import Foundation
import Logging

/// Actor that wraps a ReadPipe for receiving requests from MCP helpers
public actor HostRequestPipe<Request: MCPRequestProtocol> {
    enum Error: Swift.Error {
        case decodeError(_ error: Swift.Error)
        case readError(_ error: Swift.Error)
    }

    private let readPipe: any PipeReadable
    private let logger: Logger?
    private var readingTask: Task<Void, Never>?
    private var isReading = false

    /// Initialize with any readable pipe
    /// - Parameters:
    ///   - readPipe: Any pipe that conforms to PipeReadable
    ///   - logger: Optional logger for debugging
    init(readPipe: any PipeReadable, logger: Logger? = nil) {
        self.readPipe = readPipe
        self.logger = logger
    }

    /// Open the pipe for reading
    func open() async throws {
        try await readPipe.open()
    }

    /// Close the pipe. Stops any in-flight reading Task first so the
    /// underlying ReadPipe can tear down without racing against dispatch_io
    /// — see `ReadPipe.signalReaderWake()` for the rationale.
    func close() async {
        await stopReading()
        await readPipe.close()
    }

    /// Start continuously reading requests from the pipe.
    ///
    /// Each request is dispatched in its own Task so handlers run concurrently and the
    /// read loop never blocks. Handler ordering is not guaranteed; MCP matches by
    /// `messageId`.
    ///
    /// - Parameter requestHandler: Callback for handling received requests
    func startReading(requestHandler: @Sendable @escaping (Request) async -> Void) async {
        guard !isReading else { return }
        isReading = true

        readingTask?.cancel()

        readingTask = Task {
            do {
                while isReading && !Task.isCancelled {
                    if let request = try await readRequest() {
                        Task { await requestHandler(request) }
                    }
                }
            } catch {
                logger?.error("Error in read loop: \(error.localizedDescription)")
                isReading = false
            }
        }
    }

    /// Stop reading requests. Cancels the reader Task, wakes any in-flight
    /// `readLine()` via the underlying ReadPipe's keepalive sentinel, then
    /// awaits the Task to exit. This sequence is required to avoid
    /// deadlocking the subsequent `readPipe.close()` against dispatch_io
    /// (see `ReadPipe.signalReaderWake()`).
    func stopReading() async {
        isReading = false
        let task = readingTask
        readingTask = nil
        task?.cancel()
        await readPipe.signalReaderWake()
        _ = await task?.value
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
