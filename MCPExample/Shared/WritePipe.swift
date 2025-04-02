import Foundation
import Darwin

/// A class for creating and writing to a named pipe (FIFO)
class WritePipe {
    private let fileURL: URL
    private var fileHandle: FileHandle?
    
    /// Initialize with a URL that represents where the pipe should be created
    /// - Parameter url: A file URL where the pipe should be created
    init?(url: URL) {
        guard url.isFileURL else {
            Logging.printError("Error: URL must be a file URL")
            return nil
        }
        
        self.fileURL = url
        Logging.printInfo("WritePipe init with path: \(url.path)")
        
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
        
        Logging.printInfo("Creating pipe at path: \(pipePath)")
        
        // Check if the path already exists
        if fileManager.fileExists(atPath: pipePath) {
            // Check if it's a pipe using FileManager extension
            if fileManager.isPipe(at: fileURL) {
                Logging.printInfo("Pipe already exists at \(pipePath)")
                return true
            } else {
                Logging.printInfo("File exists but is not a pipe, attempting to remove: \(pipePath)")
                do {
                    try fileManager.removeItem(atPath: pipePath)
                    Logging.printInfo("Successfully removed existing file at \(pipePath)")
                } catch {
                    Logging.printError("Error removing existing file at \(pipePath)", error: error)
                    return false
                }
            }
        }
        
        // Create the pipe with read/write permissions for user, group, and others
        // 0o666 = rw-rw-rw-
        Logging.printInfo("Creating named pipe with mkfifo at \(pipePath)")
        let result = mkfifo(pipePath, 0o666)
        
        if result != 0 {
            let errorString = String(cString: strerror(errno))
            Logging.printError("Error creating pipe at \(pipePath): \(errorString) (errno: \(errno))")
            return false
        }
        
        Logging.printInfo("Successfully created pipe at \(pipePath)")
        
        // Check permissions on the created pipe
        if let attributes = try? fileManager.attributesOfItem(atPath: pipePath),
           let posixPermissions = attributes[.posixPermissions] as? NSNumber {
            Logging.printInfo("Pipe permissions: \(String(format: "%o", posixPermissions.intValue))")
        }
        
        // Verify it's actually a pipe
        if fileManager.isPipe(at: fileURL) {
            Logging.printInfo("Verified that the created file is a pipe")
        } else {
            Logging.printError("Created file is not detected as a pipe, this may cause issues")
        }
        
        return true
    }
    
    /// Opens the pipe for writing using non-blocking mode to prevent hanging
    /// - Returns: Boolean indicating success
    func open() -> Bool {
        Logging.printInfo("Opening pipe for writing: \(fileURL.path)")
        
        // Make sure the path exists and is a pipe
        let pipePath = fileURL.path
        guard FileManager.default.fileExists(atPath: pipePath) else {
            Logging.printError("Pipe does not exist at path: \(pipePath)")
            return false
        }
        
        guard FileManager.default.isPipe(at: fileURL) else {
            Logging.printError("File at \(pipePath) is not a pipe")
            return false
        }
        
        // Open with O_NONBLOCK flag to prevent blocking on open
        let fileDescriptor = Darwin.open(pipePath, O_WRONLY | O_NONBLOCK, 0)
        if fileDescriptor == -1 {
            let errorString = String(cString: strerror(errno))
            Logging.printError("Error opening pipe for writing: \(errorString) (errno: \(errno))")
            return false
        }
        
        Logging.printInfo("Successfully opened pipe for writing with file descriptor: \(fileDescriptor)")
        
        // Get current flags
        let flags = fcntl(fileDescriptor, F_GETFL)
        if flags == -1 {
            let errorString = String(cString: strerror(errno))
            Logging.printError("Error getting file descriptor flags: \(errorString)")
            Darwin.close(fileDescriptor)  // Close the FD to prevent leaks
            return false
        }
        
        // Reset the O_NONBLOCK flag for normal writing
        // Comment this out if you want non-blocking writes as well
        let result = fcntl(fileDescriptor, F_SETFL, flags & ~O_NONBLOCK)
        if result == -1 {
            let errorString = String(cString: strerror(errno))
            Logging.printError("Error setting file descriptor flags: \(errorString)")
            // Continue anyway since we can still use the file descriptor
        }
        
        // Create file handle from file descriptor
        fileHandle = FileHandle(fileDescriptor: fileDescriptor, closeOnDealloc: true)
        Logging.printInfo("Created FileHandle for writing")
        
        return true
    }
    
    /// Writes data to the pipe
    /// - Parameter data: The data to write
    /// - Returns: Boolean indicating success
    func write(_ data: Data) -> Bool {
        guard let fileHandle = fileHandle else {
            Logging.printError("Error: Pipe not opened")
            return false
        }
        
        Logging.printInfo("Writing \(data.count) bytes to pipe")
        do {
            try fileHandle.write(contentsOf: data)
            Logging.printInfo("Successfully wrote data to pipe")
            return true
        } catch {
            Logging.printError("Error writing to pipe", error: error)
            return false
        }
    }
    
    /// Writes a string to the pipe (converts to UTF8 data)
    /// - Parameter string: The string to write
    /// - Returns: Boolean indicating success
    func write(_ string: String) -> Bool {
        Logging.printInfo("Writing string to pipe: \(string)")
        guard let data = string.data(using: .utf8) else {
            Logging.printError("Error converting string to data")
            return false
        }
        
        return write(data)
    }
    
    /// Closes the pipe
    func close() {
        Logging.printInfo("Closing write pipe")
        try? fileHandle?.close()
        fileHandle = nil
    }
} 
