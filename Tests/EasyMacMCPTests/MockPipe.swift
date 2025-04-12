import Foundation
@testable import EasyMacMCP

/// A mock implementation of PipeReadable for testing
public actor MockPipeReader: PipeReadable {
    /// Messages that will be returned by readLine()
    public var messagesToReturn: [String] = []

    /// Simulated delay before returning from readLine() in seconds
    public var simulatedDelay: TimeInterval = 0

    /// Whether open() has been called
    public private(set) var isOpened = false

    /// Whether close() has been called
    public private(set) var isClosed = false

    public init() {}

    /// Simulates opening the pipe
    public func open() async throws {
        isOpened = true
    }

    /// Simulates reading a line from the pipe
    /// - Returns: The next message from messagesToReturn, or nil if empty
    public func readLine() async throws -> String? {
        if simulatedDelay > 0 {
            try? await Task.sleep(for: .seconds(simulatedDelay))
        }

        if messagesToReturn.isEmpty {
            return nil
        }

        return messagesToReturn.removeFirst()
    }

    /// Simulates closing the pipe
    public func close() async {
        isClosed = true
    }
}

/// A mock implementation of PipeWritable for testing
public actor MockPipeWriter: PipeWritable {
    /// Messages that have been written to the pipe
    public private(set) var writtenMessages: [String] = []

    /// Optional handler to execute when write() is called
    public var writeHandler: ((String) throws -> Void)?

    public init() {}

    public func open() async throws {
        // noop
    }

    /// Simulates writing a message to the pipe
    /// - Parameter message: The message to write
    public func write(_ message: String) throws {
        writtenMessages.append(message)

        // Call the handler if one is set
        try writeHandler?(message)
    }

    public func write(_ data: Data) async throws {
        fatalError("not yet implemented")
    }

    public func close() async {
        // noop
    }

    /// Clears all written messages
    public func clear() {
        writtenMessages.removeAll()
    }
}
