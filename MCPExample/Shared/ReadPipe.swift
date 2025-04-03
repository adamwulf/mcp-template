import Foundation
import Darwin

/// A class for creating and reading from a named pipe (FIFO)
class ReadPipe {
    private let fileURL: URL
    private var fileHandle: FileHandle?

    /// Initialize with a URL that represents where the pipe should be created
    /// - Parameter url: A file URL where the pipe should be created
    init?(url: URL) {
        guard url.isFileURL else {
            return nil
        }

        self.fileURL = url

        // Create the pipe
        if !createPipe() {
            return nil
        }
    }

    deinit {
        close()
    }

    /// Creates the named pipe at the specified URL
    /// - Returns: Boolean indicating success
    private func createPipe() -> Bool {
        let pipePath = fileURL.path
        let fileManager = FileManager.default

        // Check if the path already exists
        if fileManager.fileExists(atPath: pipePath) {
            // Check if it's a pipe using FileManager extension
            if fileManager.isPipe(at: fileURL) {
                return true
            } else {
                do {
                    try fileManager.removeItem(atPath: pipePath)
                } catch {
                    return false
                }
            }
        }

        // Create the pipe with read/write permissions for user, group, and others
        // 0o666 = rw-rw-rw-
        let result = mkfifo(pipePath, 0o666)

        if result != 0 {
            let errorString = String(cString: strerror(errno))
            return false
        }

        // Verify it's actually a pipe
        guard fileManager.isPipe(at: fileURL) else {
            return false
        }

        return true
    }

    /// Opens the pipe for reading without blocking on open, but allowing blocking reads
    /// - Returns: Boolean indicating success
    func open() -> Bool {
        // Make sure the path exists and is a pipe
        let pipePath = fileURL.path
        guard FileManager.default.fileExists(atPath: pipePath) else {
            return false
        }

        guard FileManager.default.isPipe(at: fileURL) else {
            return false
        }

        // First open with O_NONBLOCK flag to prevent blocking on open
        let fileDescriptor = Darwin.open(pipePath, O_RDONLY | O_NONBLOCK, 0)
        guard fileDescriptor != -1 else {
            let errorString = String(cString: strerror(errno))
            Logging.printError("Error opening pipe for reading: \(errorString) (errno: \(errno))")
            PipeTestHelpers.printPipeStatus(pipePath: fileURL)
            return false
        }

        // Get flags
        let flags = fcntl(fileDescriptor, F_GETFL)
        guard flags != -1 else {
            let errorString = String(cString: strerror(errno))
            Logging.printError("Error getting file descriptor flags: \(errorString)")
            Darwin.close(fileDescriptor)  // Close the FD to prevent leaks
            return false
        }

        // Set flags - check for error
        let result = fcntl(fileDescriptor, F_SETFL, flags & ~O_NONBLOCK)
        if result == -1 {
            let errorString = String(cString: strerror(errno))
            Logging.printError("Error setting file descriptor flags: \(errorString)")
            // Continue since we can still use the file descriptor
        }

        // Create file handle
        fileHandle = FileHandle(fileDescriptor: fileDescriptor, closeOnDealloc: true)

        return true
    }

    /// Reads data from the pipe (blocking)
    /// - Returns: Data read from the pipe, or nil if there was an error
    func read() -> Data? {
        guard let fileHandle = fileHandle else {
            Logging.printError("Error: Pipe not opened")
            return nil
        }

        do {
            // This will block until data is available
            return try fileHandle.readToEnd()
        } catch {
            Logging.printError("Error reading from pipe", error: error)
            return nil
        }
    }

    /// Reads data from the pipe and converts it to a string
    /// - Returns: String read from the pipe, or nil if there was an error
    func readString() -> String? {
        guard let data = read() else {
            return nil
        }

        if let string = String(data: data, encoding: .utf8) {
            return string
        } else {
            return nil
        }
    }

    /// Closes the pipe
    func close() {
        try? fileHandle?.close()
        fileHandle = nil
    }
}
