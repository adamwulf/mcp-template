import Foundation
import Darwin

/// Errors that can occur when working with ReadPipe
public enum ReadPipeError: Error {
    case invalidURL
    case failedToCreatePipe(String)
    case pipeAlreadyExists
    case pipeDoesNotExist
    case notAPipe
    case openFailed(String)
    case getFlagsFailed(String)
    case setFlagsFailed(String)
    case pipeNotOpened
    case readError(Error)
    case eof
    case stringEncodingError
}

/// A class for creating and reading from a named pipe (FIFO)
public actor ReadPipe: PipeReadable {
    private let fileURL: URL
    private var fileHandle: FileHandle?

    /// Initialize with a URL that represents where the pipe should be created
    /// - Parameters:
    ///   - url: A file URL where the pipe should be created
    /// - Throws: ReadPipeError if initialization fails
    public init(url: URL) throws {
        guard url.isFileURL else {
            throw ReadPipeError.invalidURL
        }

        self.fileURL = url

        // Create the pipe
        let pipePath = fileURL.path
        let fileManager = FileManager.default

        // Check if the path already exists
        if fileManager.fileExists(atPath: pipePath) {
            // Check if it's a pipe using FileManager extension
            if fileManager.isPipe(at: fileURL) {
                return
            } else {
                do {
                    try fileManager.removeItem(atPath: pipePath)
                } catch {
                    throw ReadPipeError.pipeAlreadyExists
                }
            }
        }

        // Create the pipe with read/write permissions for user, group, and others
        // 0o666 = rw-rw-rw-
        let result = mkfifo(pipePath, 0o666)

        if result != 0 {
            let errorString = String(cString: strerror(errno))
            throw ReadPipeError.failedToCreatePipe(errorString)
        }

        // Verify it's actually a pipe
        guard fileManager.isPipe(at: fileURL) else {
            throw ReadPipeError.notAPipe
        }
    }

    deinit {
        try? fileHandle?.close()
        fileHandle = nil
    }

    /// Opens the pipe for reading without blocking on open, but allowing blocking reads
    /// - Throws: ReadPipeError if opening fails
    public func open() async throws {
        // Make sure the path exists and is a pipe
        let pipePath = fileURL.path
        guard FileManager.default.fileExists(atPath: pipePath) else {
            throw ReadPipeError.pipeDoesNotExist
        }

        guard FileManager.default.isPipe(at: fileURL) else {
            throw ReadPipeError.notAPipe
        }

        // First open with O_NONBLOCK flag to prevent blocking on open
        let fileDescriptor = Darwin.open(pipePath, O_RDONLY | O_NONBLOCK, 0)
        guard fileDescriptor != -1 else {
            let errorString = String(cString: strerror(errno))
            Logging.printError("Error opening pipe for reading: \(errorString) (errno: \(errno))")
            throw ReadPipeError.openFailed(errorString)
        }

        // Get flags
        let flags = fcntl(fileDescriptor, F_GETFL)
        guard flags != -1 else {
            let errorString = String(cString: strerror(errno))
            Logging.printError("Error getting file descriptor flags: \(errorString)")
            Darwin.close(fileDescriptor)  // Close the FD to prevent leaks
            throw ReadPipeError.getFlagsFailed(errorString)
        }

        // Set flags based on blocking preference
        let newFlags: Int32 = flags & ~O_NONBLOCK
        let result = fcntl(fileDescriptor, F_SETFL, newFlags)
        if result == -1 {
            let errorString = String(cString: strerror(errno))
            Logging.printError("Error setting file descriptor flags: \(errorString)")
            // We still create the file handle but log the error
        }

        // Create file handle
        fileHandle = FileHandle(fileDescriptor: fileDescriptor, closeOnDealloc: true)
    }

    /// Reads a single line from the pipe
    /// - Returns: A single line as a string, or nil if the stream ends or no data available in non-blocking mode
    /// - Throws: ReadPipeError if reading fails
    public func readLine() async throws -> String? {
        guard let fileHandle = fileHandle else {
            Logging.printError("Error: Pipe not opened")
            throw ReadPipeError.pipeNotOpened
        }

        do {
            // In non-blocking mode, this may return immediately if no data is available
            for try await line in fileHandle.bytes.lines {
                return line
            }
            // If we get here, the sequence was empty (EOF or no data in non-blocking mode)
            // Sleep for a short time to avoid spinning CPU when repeatedly called
            try await Task.sleep(for: .milliseconds(100))
            return nil
        } catch {
            // In non-blocking mode, check for specific errors like EAGAIN/EWOULDBLOCK            
            Logging.printError("Error reading line from pipe", error: error)
            throw ReadPipeError.readError(error)
        }
    }

    /// Closes the pipe
    public func close() async {
        try? fileHandle?.close()
        fileHandle = nil
    }
}
