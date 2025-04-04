import Foundation

/// Protocol for objects that can read from a pipe
public protocol PipeReadable: Sendable {
    /// Opens the pipe for reading
    func open() async throws

    /// Reads a single line from the pipe
    /// - Returns: A single line as a string, or nil if the stream ends
    /// - Throws: Error if reading fails
    func readLine() async throws -> String?

    /// Closes the pipe
    func close() async
}

/// Protocol for objects that can write to a pipe
public protocol PipeWritable: Sendable {
    /// Writes a message to the pipe
    /// - Parameter message: The message to write
    /// - Throws: Error if writing fails
    func write(_ message: String) async throws
}
