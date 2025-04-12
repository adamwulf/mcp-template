import Foundation
import Logging

/// Actor that wraps a WritePipe for sending requests from helpers to the Mac app
public actor HelperRequestPipe {
    public enum Error: Swift.Error {
        case encodeError(_ error: Swift.Error)
        case sendError(_ error: Swift.Error)
    }

    private let writePipe: WritePipe
    private let logger: Logger?

    /// Initialize with a pipe URL
    /// - Parameters:
    ///   - url: URL to the central request pipe
    ///   - logger: Optional logger for debugging
    public init(url: URL, logger: Logger? = nil) throws {
        self.writePipe = try WritePipe(url: url)
        self.logger = logger
    }

    /// Open the pipe for writing
    public func open() async throws {
        try await writePipe.open()
    }

    /// Close the pipe
    public func close() async {
        await writePipe.close()
    }

    /// Send a request to the Mac app
    /// - Parameter request: The request to send
    public func sendRequest<Request: MCPRequestProtocol & Encodable>(_ request: Request) async throws {
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
    
    /// Send a string to the Mac app
    /// - Parameter string: The string to send
    public func sendString(_ string: String) async throws {
        guard let data = string.data(using: .utf8) else {
            throw Error.encodeError(NSError(domain: "HelperRequestPipe", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to encode string as UTF-8"]))
        }
        
        // Ensure we have a newline at the end for parsing on the other side
        var newlineData = data
        newlineData.append(10) // newline character
        
        do {
            try await writePipe.write(newlineData)
        } catch {
            logger?.error("Error sending string: \(error.localizedDescription)")
            throw Error.sendError(error)
        }
    }
} 