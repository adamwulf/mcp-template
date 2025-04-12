import Foundation
import Logging

/// Utility class for logging messages
enum Logging {
    /// The shared internal logger
    private static let logger = Logger(label: "com.milestonemade.easymacmcp")

    /// Prints an error message to standard error
    /// - Parameter message: The error message to print
    static func printError(_ message: String) {
        logger.error("\(message)")
    }

    /// Prints an error message with a specific error object to standard error
    /// - Parameters:
    ///   - message: The error message prefix
    ///   - error: The error object containing details
    static func printError(_ message: String, error: Error) {
        logger.error("\(message): \(error.localizedDescription)")
    }

    /// Prints a warning message to standard error
    /// - Parameter message: The warning message to print
    static func printWarning(_ message: String) {
        logger.warning("\(message)")
    }

    /// Prints an info message to standard output
    /// - Parameter message: The info message to print
    static func printInfo(_ message: String) {
        logger.info("\(message)")
    }
}
