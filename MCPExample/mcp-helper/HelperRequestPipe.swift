//
//  HelperRequestPipe.swift
//  MCPExample
//
//  Created by Adam Wulf on 4/6/25.
//

import Foundation
import EasyMacMCP
import Logging

/// Actor that wraps a WritePipe for sending requests from helpers to the Mac app
actor HelperRequestPipe {
    enum Error: Swift.Error {
        case encodeError(_ error: Swift.Error)
        case sendError(_ error: Swift.Error)
    }

    private let writePipe: WritePipe
    private let logger: Logger?

    /// Initialize with a pipe URL
    /// - Parameters:
    ///   - url: URL to the central request pipe
    ///   - logger: Optional logger for debugging
    init(url: URL, logger: Logger? = nil) throws {
        self.writePipe = try WritePipe(url: url)
        self.logger = logger
    }

    /// Open the pipe for writing
    func open() async throws {
        try await writePipe.open()
    }

    /// Close the pipe
    func close() async {
        await writePipe.close()
    }

    /// Send a request to the Mac app
    /// - Parameter request: The MCPRequest to send
    func sendRequest(_ request: MCPRequest) async throws {
        let encoder = JSONEncoder()
        let jsonData: Data

        do {
            jsonData = try encoder.encode(request)
        } catch {
            logger?.error("Error encoding request: \(error.localizedDescription)")
            throw Error.encodeError(error)
        }

        // Ensure we have a newline at the end for parsing on the other side
        var data = jsonData
        data.append(10) // newline character

        do {
            try await writePipe.write(data)
        } catch {
            logger?.error("Error sending request: \(error.localizedDescription)")
            throw Error.sendError(error)
        }
    }
}
