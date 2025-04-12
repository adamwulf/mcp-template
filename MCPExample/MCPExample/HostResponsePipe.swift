//
//  HostResponsePipe.swift
//  MCPExample
//
//  Created by Adam Wulf on 4/6/25.
//

import Foundation
import EasyMacMCP
import Logging

/// Actor that wraps a WritePipe for sending responses from the Mac app to a specific MCP helper
actor HostResponsePipe {
    enum Error: Swift.Error {
        case encodeError(_ error: Swift.Error)
        case sendError(_ error: Swift.Error)
    }

    let helperId: String
    private let writePipe: WritePipe
    private let logger: Logger?

    /// Initialize with the helper ID and response pipe URL
    /// - Parameters:
    ///   - helperId: The unique identifier for the MCP helper
    ///   - logger: Optional logger for debugging
    init(helperId: String, logger: Logger? = nil) throws {
        self.helperId = helperId
        self.logger = logger

        let url = PipeConstants.helperResponsePipePath(helperId: helperId)
        self.writePipe = try WritePipe(url: url)
    }

    /// Open the pipe for writing
    func open() async throws {
        try await writePipe.open()
    }

    /// Close the pipe
    func close() async {
        await writePipe.close()
    }

    /// Send a response to the helper
    /// - Parameter response: The MCPResponse to send
    func sendResponse(_ response: MCPResponse) async throws {
        logger?.info("HOST_RESPONSE_PIPE: Sending response to helper \(helperId) with messageId: \(response.messageId)")

        let encoder = JSONEncoder()
        let jsonData: Data

        do {
            jsonData = try encoder.encode(response)
            if let jsonString = String(data: jsonData, encoding: .utf8) {
                logger?.info("HOST_RESPONSE_PIPE: Encoded response: \(jsonString)")
            }
        } catch {
            logger?.error("HOST_RESPONSE_PIPE: Error encoding response: \(error.localizedDescription)")
            throw Error.encodeError(error)
        }

        // Ensure we have a newline at the end for parsing on the other side
        var data = jsonData
        data.append(10) // newline character

        do {
            try await writePipe.write(data)
            logger?.info("HOST_RESPONSE_PIPE: Response successfully sent to pipe")
        } catch {
            logger?.error("HOST_RESPONSE_PIPE: Error sending response: \(error.localizedDescription)")
            throw Error.sendError(error)
        }
    }
}
