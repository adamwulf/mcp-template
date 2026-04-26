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
    /// Persistent line iterator over `fileHandle.bytes.lines`. Held across
    /// `readLine()` calls so the underlying `AsyncBytes` chunk buffer
    /// survives — building a fresh iterator per call would over-read the FD
    /// and silently discard any extra lines that came in the same chunk.
    private var lineIterator: AsyncLineSequence<FileHandle.AsyncBytes>.AsyncIterator?

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
        let handle = FileHandle(fileDescriptor: fileDescriptor, closeOnDealloc: true)
        fileHandle = handle
        lineIterator = handle.bytes.lines.makeAsyncIterator()
    }

    /// Reads a single line from the pipe.
    ///
    /// Uses a persistent `AsyncLineSequence` iterator so chunked reads from
    /// the underlying FD don't drop buffered lines between calls. When the
    /// iterator returns `nil` (all writers detached → EOF), rebuild it once
    /// from the same FD and retry, so a writer that reattaches later resumes
    /// the read loop cleanly.
    /// - Returns: A single line, or `nil` if the pipe is at EOF and no
    ///   writer reattached.
    /// - Throws: `ReadPipeError` if reading fails.
    public func readLine() async throws -> String? {
        guard let handle = fileHandle, var iterator = lineIterator else {
            Logging.printError("Error: Pipe not opened")
            throw ReadPipeError.pipeNotOpened
        }

        do {
            if let line = try await iterator.next() {
                lineIterator = iterator
                return line
            }
            // EOF on this iterator. Rebuild from the same FD and try once
            // more — a freshly-attached writer will block the read until it
            // produces data, matching the original "read forever" contract.
            var rebuilt = handle.bytes.lines.makeAsyncIterator()
            let line = try await rebuilt.next()
            lineIterator = rebuilt
            return line
        } catch {
            lineIterator = iterator
            Logging.printError("Error reading line from pipe", error: error)
            throw ReadPipeError.readError(error)
        }
    }

    /// Closes the pipe
    public func close() async {
        lineIterator = nil
        try? fileHandle?.close()
        fileHandle = nil
    }
}
