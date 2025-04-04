//
//  HelperPipes.swift
//  MCPExample
//
//  Created by Adam Wulf on 4/3/25.
//
import Foundation

actor HelperPipes {
    let writePipe: WritePipe
    let readPipe: ReadPipe

    init(writePipe: WritePipe, readPipe: ReadPipe) {
        self.writePipe = writePipe
        self.readPipe = readPipe
    }

    public func open() async throws {
        try writePipe.open()
        try await readPipe.open()
    }

    public func close() async throws {
        writePipe.close()
        await readPipe.close()
    }

    @discardableResult
    public func sendToolRequest(_ tool: MCPRequest) async -> Bool {
        do {
            let encoder = JSONEncoder()
            let jsonData = try encoder.encode(tool)

            // Ensure we have a newline at the end for parsing on the other side
            var data = jsonData
            data.append(10) // newline character

            try writePipe.write(data)
            return true
        } catch {
            Logging.printError("Error encoding tool: \(error)")
            return false
        }
    }

    /// Reads an ExampleToolResponse from the app-to-helper pipe
    /// - Parameter pipe: The ReadPipe to use
    /// - Returns: The decoded ExampleToolResponse
    func readToolResponse() async throws -> MCPResponse {
        guard let string = try await readPipe.readLine() else {
            throw ReadPipeError.eof
        }
        let decoder = JSONDecoder()
        return try decoder.decode(MCPResponse.self, from: Data(string.utf8))
    }
}
