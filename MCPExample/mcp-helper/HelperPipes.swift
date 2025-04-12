//
//  HelperPipes.swift
//  MCPExample
//
//  Created by Adam Wulf on 4/3/25.
//
import Foundation
import EasyMacMCP

actor HelperPipes {

    enum Error: Swift.Error {
        case encodeError(_ error: Swift.Error)
        case decodeError(_ error: Swift.Error)
        case sendError(_ error: Swift.Error)
        case readError(_ error: Swift.Error)
    }

    let writePipe: WritePipe
    let readPipe: ReadPipe

    init(writePipe: WritePipe, readPipe: ReadPipe) {
        self.writePipe = writePipe
        self.readPipe = readPipe
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
            Logging.printError("Error encoding tool: \(error)")
            throw Error.encodeError(error)
        }

        // Ensure we have a newline at the end for parsing on the other side
        var data = jsonData
        data.append(10) // newline character

        do {
            try await writePipe.write(data)
        } catch {
            Logging.printError("Error encoding tool: \(error)")
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
            Logging.printError("Error reading response: \(error)")
            throw Error.readError(error)
        }
    }
}
