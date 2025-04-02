import Foundation

/// Utility class for logging messages
public enum Logging {
    /// Prints an error message to standard error
    /// - Parameter message: The error message to print
    public static func printError(_ message: String) {
        let stderr = FileHandle.standardError
        if let data = (message + "\n").data(using: .utf8) {
            stderr.write(data)
        }
    }
    
    /// Prints an error message with a specific error object to standard error
    /// - Parameters:
    ///   - message: The error message prefix
    ///   - error: The error object containing details
    public static func printError(_ message: String, error: Error) {
        printError("\(message): \(error.localizedDescription)")
    }
    
    /// Prints a warning message to standard error
    /// - Parameter message: The warning message to print
    public static func printWarning(_ message: String) {
        printError("Warning: \(message)")
    }
    
    /// Prints an info message to standard output
    /// - Parameter message: The info message to print
    public static func printInfo(_ message: String) {
        if let data = (message + "\n").data(using: .utf8) {
            FileHandle.standardOutput.write(data)
        }
    }
} 