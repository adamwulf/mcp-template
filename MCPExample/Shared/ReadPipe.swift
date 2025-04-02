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
            Logging.printError("Error: URL must be a file URL")
            return nil
        }
        
        self.fileURL = url
        Logging.printInfo("ReadPipe init with path: \(url.path)")
        
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
    
    /// Opens the pipe for reading without blocking on open, but allowing blocking reads
    /// - Returns: Boolean indicating success
    func open() -> Bool {
        Logging.printInfo("Opening pipe for reading: \(fileURL.path)")
        
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
        
        // First open with O_NONBLOCK flag to prevent blocking on open
        let fileDescriptor = Darwin.open(pipePath, O_RDONLY | O_NONBLOCK, 0)
        guard fileDescriptor != -1 else {
            let errorString = String(cString: strerror(errno))
            Logging.printError("Error opening pipe for reading: \(errorString) (errno: \(errno))")
            return false
        }

        Logging.printInfo("Successfully opened pipe for reading with file descriptor: \(fileDescriptor)")

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
        } else {
            Logging.printInfo("Successfully set file descriptor to blocking mode")
        }

        // Create file handle
        fileHandle = FileHandle(fileDescriptor: fileDescriptor, closeOnDealloc: true)
        Logging.printInfo("Created FileHandle for reading")
        
        return true
    }
    
    /// Reads data from the pipe (blocking)
    /// - Returns: Data read from the pipe, or nil if there was an error
    func read() -> Data? {
        guard let fileHandle = fileHandle else {
            Logging.printError("Error: Pipe not opened")
            return nil
        }
        
        Logging.printInfo("Reading from pipe (blocking)...")
        do {
            // This will block until data is available
            let data = try fileHandle.readToEnd()
            if let data = data {
                Logging.printInfo("Successfully read \(data.count) bytes from pipe")
            } else {
                Logging.printInfo("Read returned nil data (EOF)")
            }
            return data
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
            Logging.printInfo("Successfully converted data to string: \(string)")
            return string
        } else {
            Logging.printError("Failed to convert data to string")
            return nil
        }
    }
    
    /// Closes the pipe
    func close() {
        Logging.printInfo("Closing read pipe")
        try? fileHandle?.close()
        fileHandle = nil
    }
} 
