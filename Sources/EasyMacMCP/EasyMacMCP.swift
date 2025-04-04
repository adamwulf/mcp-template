import Foundation
import EasyMCP

/// EasyMacMCP provides macOS-specific utilities for communication between
/// an MCP helper and a Mac application using pipes.
public enum EasyMacMCP {
    /// Sets up a communication channel between an MCP helper and a Mac application
    /// - Parameters:
    ///   - helperId: The unique identifier for the helper
    ///   - writePipe: The pipe to write requests to
    ///   - responseManager: The response manager to use
    /// - Returns: An MCPTools instance for making tool calls
    public static func setupCommunication(
        helperId: String,
        writePipe: PipeWritable,
        responseManager: ResponseManager
    ) -> MCPTools {
        return MCPTools(
            helperId: helperId,
            writePipe: writePipe,
            responseManager: responseManager
        )
    }

    /// Creates a response reader for handling responses from the Mac application
    /// - Parameters:
    ///   - readPipe: The pipe to read responses from
    ///   - responseManager: The response manager to use
    /// - Returns: An MCPResponseReader instance
    public static func createResponseReader(
        readPipe: PipeReadable,
        responseManager: ResponseManager
    ) -> MCPResponseReader {
        return MCPResponseReader(
            pipe: readPipe,
            responseManager: responseManager
        )
    }
}
