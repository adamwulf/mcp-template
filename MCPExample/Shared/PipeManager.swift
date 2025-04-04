import Foundation

/// Handles encoding/decoding and sending of tool messages through pipes
public class PipeManager {
    /// Encodes an ExampleTool to JSON and writes it to the helper-to-app pipe
    /// - Parameter tool: The tool to send
    /// - Returns: Success status
    @discardableResult
    public static func sendToolRequest(_ tool: MCPRequest) async -> Bool {
        do {
            let encoder = JSONEncoder()
            let jsonData = try encoder.encode(tool)

            // Ensure we have a newline at the end for parsing on the other side
            var data = jsonData
            data.append(10) // newline character

            return await sendData(data, to: PipeConstants.helperToAppPipePath())
        } catch {
            Logging.printError("Error encoding tool: \(error)")
            return false
        }
    }

    /// Encodes an ExampleToolResponse to JSON and writes it to the app-to-helper pipe
    /// - Parameter response: The response to send
    /// - Returns: Success status
    @discardableResult
    public static func sendToolResponse(_ response: MCPResponse) async -> Bool {
        do {
            let encoder = JSONEncoder()
            let jsonData = try encoder.encode(response)

            // Ensure we have a newline at the end for parsing on the other side
            var data = jsonData
            data.append(10) // newline character

            return await sendData(data, to: PipeConstants.appToHelperPipePath())
        } catch {
            Logging.printError("Error encoding response: \(error)")
            return false
        }
    }

    /// Sends data to a pipe
    /// - Parameters:
    ///   - data: The data to send
    ///   - pipeURL: The URL of the pipe
    /// - Returns: Success status
    private static func sendData(_ data: Data, to pipeURL: URL) async -> Bool {
        return await withCheckedContinuation { continuation in
            var writePipe: WritePipe?
            do {
                let pipe = try WritePipe(url: pipeURL)
                writePipe = pipe

                try pipe.open()
                try pipe.write(data)
                pipe.close()

                continuation.resume(returning: true)
            } catch {
                writePipe?.close()
                Logging.printError("Error writing to pipe: \(error)")
                continuation.resume(returning: false)
            }
        }
    }

    /// Reads an ExampleTool from the helper-to-app pipe
    /// - Parameter pipe: The ReadPipe to use
    /// - Returns: The decoded ExampleTool
    static func readToolRequest(from pipe: ReadPipe) async throws -> MCPRequest {
        let data = try await readDataFrom(pipe)
        let decoder = JSONDecoder()
        return try decoder.decode(MCPRequest.self, from: data)
    }

    /// Reads an ExampleToolResponse from the app-to-helper pipe
    /// - Parameter pipe: The ReadPipe to use
    /// - Returns: The decoded ExampleToolResponse
    static func readToolResponse(from pipe: ReadPipe) async throws -> MCPResponse {
        let data = try await readDataFrom(pipe)
        let decoder = JSONDecoder()
        return try decoder.decode(MCPResponse.self, from: data)
    }

    /// Reads data from a pipe
    /// - Parameter pipe: The ReadPipe to use
    /// - Returns: The data read from the pipe
    private static func readDataFrom(_ pipe: ReadPipe) async throws -> Data {
        guard let string = try await pipe.readLine() else {
            throw ReadPipeError.eof
        }
        return Data(string.utf8)
    }
}
