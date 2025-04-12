//
//  HelperPipes.swift
//  MCPExample
//
//  Created by Adam Wulf on 4/3/25.
//
import Foundation
import EasyMacMCP
import Logging

actor HelperPipes {

    enum Error: Swift.Error {
        case encodeError(_ error: Swift.Error)
        case decodeError(_ error: Swift.Error)
        case sendError(_ error: Swift.Error)
        case readError(_ error: Swift.Error)
    }

    let writePipe: WritePipe
    let readPipe: ReadPipe
    private let logger: Logger?

    init(writePipe: WritePipe, readPipe: ReadPipe, logger: Logger? = nil) {
        self.writePipe = writePipe
        self.readPipe = readPipe
        self.logger = logger
    }

    public func open() async throws {
        try await writePipe.open()
        try await readPipe.open()
    }

    public func close() async throws {
        await writePipe.close()
        await readPipe.close()
    }

    public func sendToolRequest(_ tool: MCPRequest) async throws {
        let encoder = JSONEncoder()
        let jsonData: Data
        do {
            jsonData = try encoder.encode(tool)
        } catch {
            logger?.error("Error encoding tool: \(error.localizedDescription)")
            throw Error.encodeError(error)
        }

        // Ensure we have a newline at the end for parsing on the other side
        var data = jsonData
        data.append(10) // newline character

        do {
            try await writePipe.write(data)
        } catch {
            logger?.error("Error sending tool request: \(error.localizedDescription)")
            throw Error.sendError(error)
        }
    }

    /// Reads an ExampleToolResponse from the app-to-helper pipe
    /// - Parameter pipe: The ReadPipe to use
    /// - Returns: The decoded ExampleToolResponse
    func readToolResponse() async throws -> MCPResponse {
        guard let string = try await readPipe.readLine() else {
            throw Error.readError(ReadPipeError.eof)
        }
        do {
            let decoder = JSONDecoder()
            return try decoder.decode(MCPResponse.self, from: Data(string.utf8))
        } catch {
            logger?.error("Error reading response: \(error.localizedDescription)")
            throw Error.readError(error)
        }
    }
}
