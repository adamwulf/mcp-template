//
//  HelperPipes.swift
//  MCPExample
//
//  Created by Adam Wulf on 4/3/25.
//
import Foundation

actor HelperPipes {
    let helperToAppPipe: WritePipe
    let appToHelperPipe: ReadPipe

    init(helperToAppPipe: WritePipe, appToHelperPipe: ReadPipe) {
        self.helperToAppPipe = helperToAppPipe
        self.appToHelperPipe = appToHelperPipe
    }

    public func open() async throws {
        try helperToAppPipe.open()
        try await appToHelperPipe.open()
    }

    public func close() async throws {
        helperToAppPipe.close()
        await appToHelperPipe.close()
    }

    @discardableResult
    public func sendToolRequest(_ tool: MCPRequest) async -> Bool {
        do {
            let encoder = JSONEncoder()
            let jsonData = try encoder.encode(tool)

            // Ensure we have a newline at the end for parsing on the other side
            var data = jsonData
            data.append(10) // newline character

            try helperToAppPipe.write(data)
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
        guard let string = try await appToHelperPipe.readLine() else {
            throw ReadPipeError.eof
        }
        let decoder = JSONDecoder()
        return try decoder.decode(MCPResponse.self, from: Data(string.utf8))
    }
}
