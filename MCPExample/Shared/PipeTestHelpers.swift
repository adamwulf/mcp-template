import Foundation

/// Utility class for testing named pipe functionality
public class PipeTestHelpers {
    
    /// Tests writing to a pipe at the specified path
    /// - Parameters:
    ///   - message: The message to write to the pipe
    ///   - pipePath: The URL path to the pipe (defaults to the test pipe path)
    ///   - completion: Optional completion handler called with success/failure status
    /// - Returns: Boolean indicating success
    @discardableResult
    public static func testWritePipe(
        message: String = "Hello World from PipeTestHelpers!",
        pipePath: URL = PipeConstants.testPipePath(),
        completion: ((Bool) -> Void)? = nil
    ) -> Bool {
        Logging.printInfo("Creating write pipe at: \(pipePath.path)")
        
        // Create a write pipe
        guard let writePipe = WritePipe(url: pipePath) else {
            Logging.printError("Failed to create write pipe")
            completion?(false)
            return false
        }
        
        // Open the pipe for writing
        guard writePipe.open() else {
            Logging.printError("Failed to open write pipe")
            completion?(false)
            return false
        }
        
        // Write to the pipe
        Logging.printInfo("Writing message: \(message)")
        
        let success = writePipe.write(message)
        if success {
            Logging.printInfo("Message written successfully")
        } else {
            Logging.printError("Failed to write message")
        }
        
        // Close the pipe
        writePipe.close()
        Logging.printInfo("Pipe test completed")
        
        completion?(success)
        return success
    }
    
    /// Tests writing to a pipe asynchronously
    /// - Parameters:
    ///   - message: The message to write to the pipe
    ///   - pipePath: The URL path to the pipe (defaults to the test pipe path)
    /// - Returns: Boolean indicating success
    @available(macOS 10.15, *)
    public static func testWritePipeAsync(
        message: String = "Hello World from PipeTestHelpers!",
        pipePath: URL = PipeConstants.testPipePath()
    ) async -> Bool {
        return await withCheckedContinuation { continuation in
            testWritePipe(message: message, pipePath: pipePath) { success in
                continuation.resume(returning: success)
            }
        }
    }
} 