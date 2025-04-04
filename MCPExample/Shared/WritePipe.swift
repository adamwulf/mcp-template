import Foundation
import Darwin

/// Errors that can occur when working with WritePipe
enum WritePipeError: Error {
    case invalidURL
    case failedToCreatePipe(String)
    case pipeAlreadyExists
    case pipeDoesNotExist
    case notAPipe
    case openFailed(String)
    case getFlagsFailed(String)
    case setFlagsFailed(String)
    case pipeNotOpened
    case writeError(Error)
}

/// A class for creating and writing to a named pipe (FIFO)
class WritePipe {
    private let fileURL: URL
    private var fileHandle: FileHandle?

    /// Initialize with a URL that represents where the pipe should be created
    /// - Parameter url: A file URL where the pipe should be created
    /// - Throws: WritePipeError if initialization fails
    init(url: URL) throws {
        guard url.isFileURL else {
            Logging.printError("Error: URL must be a file URL")
            throw WritePipeError.invalidURL
        }

        self.fileURL = url

        // Create the pipe
        try createPipe()
    }

    deinit {
        close()
    }

    /// Creates the named pipe at the specified URL
    /// - Throws: WritePipeError if creation fails
    private func createPipe() throws {
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
                    Logging.printError("Error removing existing file at \(pipePath)", error: error)
                    throw WritePipeError.pipeAlreadyExists
                }
            }
        }

        // Create the pipe with read/write permissions for user, group, and others
        // 0o666 = rw-rw-rw-
        let result = mkfifo(pipePath, 0o666)

        if result != 0 {
            let errorString = String(cString: strerror(errno))
            Logging.printError("Error creating pipe at \(pipePath): \(errorString) (errno: \(errno))")
            throw WritePipeError.failedToCreatePipe(errorString)
        }

        // Verify it's actually a pipe
        if !fileManager.isPipe(at: fileURL) {
            Logging.printError("Created file is not detected as a pipe, this may cause issues")
            throw WritePipeError.notAPipe
        }
    }

    /// Opens the pipe for writing using non-blocking mode to prevent hanging
    /// - Throws: WritePipeError if opening fails
    func open() throws {
        // Make sure the path exists and is a pipe
        let pipePath = fileURL.path
        guard FileManager.default.fileExists(atPath: pipePath) else {
            Logging.printError("Pipe does not exist at path: \(pipePath)")
            throw WritePipeError.pipeDoesNotExist
        }

        guard FileManager.default.isPipe(at: fileURL) else {
            Logging.printError("File at \(pipePath) is not a pipe")
            throw WritePipeError.notAPipe
        }

        // Open with O_NONBLOCK flag to prevent blocking on open
        let fileDescriptor = Darwin.open(pipePath, O_WRONLY | O_NONBLOCK, 0)
        if fileDescriptor == -1 {
            let errorString = String(cString: strerror(errno))
            Logging.printError("Error opening pipe for writing: \(errorString) (errno: \(errno))")
            throw WritePipeError.openFailed(errorString)
        }

        // Get current flags
        let flags = fcntl(fileDescriptor, F_GETFL)
        if flags == -1 {
            let errorString = String(cString: strerror(errno))
            Logging.printError("Error getting file descriptor flags: \(errorString)")
            Darwin.close(fileDescriptor)  // Close the FD to prevent leaks
            throw WritePipeError.getFlagsFailed(errorString)
        }

        // Reset the O_NONBLOCK flag for normal writing
        // Comment this out if you want non-blocking writes as well
        let result = fcntl(fileDescriptor, F_SETFL, flags & ~O_NONBLOCK)
        if result == -1 {
            let errorString = String(cString: strerror(errno))
            Logging.printError("Error setting file descriptor flags: \(errorString)")
            // We still create the file handle but log the error
        }

        // Create file handle from file descriptor
        fileHandle = FileHandle(fileDescriptor: fileDescriptor, closeOnDealloc: true)
    }

    /// Writes data to the pipe
    /// - Parameter data: The data to write
    /// - Throws: WritePipeError if writing fails
    func write(_ data: Data) throws {
        guard let fileHandle = fileHandle else {
            Logging.printError("Error: Pipe not opened")
            throw WritePipeError.pipeNotOpened
        }

        do {
            try fileHandle.write(contentsOf: data)
        } catch {
            Logging.printError("Error writing to pipe", error: error)
            throw WritePipeError.writeError(error)
        }
    }

    /// Writes a string to the pipe (converts to UTF8 data)
    /// - Parameter string: The string to write
    /// - Throws: WritePipeError if writing fails
    func write(_ string: String) throws {
        try write(Data(string.utf8))
    }

    /// Closes the pipe
    func close() {
        try? fileHandle?.close()
        fileHandle = nil
    }
}
