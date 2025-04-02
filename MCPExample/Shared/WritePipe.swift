import Foundation

/// A class for creating and writing to a named pipe (FIFO)
class WritePipe {
    private let fileURL: URL
    private var fileHandle: FileHandle?
    
    /// Initialize with a URL that represents where the pipe should be created
    /// - Parameter url: A file URL where the pipe should be created
    init?(url: URL) {
        guard url.isFileURL else {
            fatalError("Error: URL must be a file URL")
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
        
        // Check if the pipe already exists
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: pipePath) {
            // Pipe already exists, so just use it
            return true
        }
        
        // Create the pipe with read/write permissions for user, group, and others
        // 0o666 = rw-rw-rw-
        let result = mkfifo(pipePath, 0o666)
        
        if result != 0 {
            let errorString = String(cString: strerror(errno))
            print("Error creating pipe at \(pipePath): \(errorString)")
            return false
        }
        
        return true
    }
    
    /// Opens the pipe for writing
    /// - Returns: Boolean indicating success
    func open() -> Bool {
        do {
            fileHandle = try FileHandle(forWritingTo: fileURL)
            return true
        } catch {
            print("Error opening pipe for writing: \(error.localizedDescription)")
            return false
        }
    }
    
    /// Writes data to the pipe
    /// - Parameter data: The data to write
    /// - Returns: Boolean indicating success
    func write(_ data: Data) -> Bool {
        guard let fileHandle = fileHandle else {
            print("Error: Pipe not opened")
            return false
        }
        
        do {
            try fileHandle.write(contentsOf: data)
            return true
        } catch {
            print("Error writing to pipe: \(error.localizedDescription)")
            return false
        }
    }
    
    /// Writes a string to the pipe (converts to UTF8 data)
    /// - Parameter string: The string to write
    /// - Returns: Boolean indicating success
    func write(_ string: String) -> Bool {
        guard let data = string.data(using: .utf8) else {
            print("Error converting string to data")
            return false
        }
        
        return write(data)
    }
    
    /// Closes the pipe
    func close() {
        try? fileHandle?.close()
        fileHandle = nil
    }
} 
