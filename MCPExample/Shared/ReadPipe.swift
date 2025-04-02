import Foundation

/// A class for creating and reading from a named pipe (FIFO)
class ReadPipe {
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
    
    /// Opens the pipe for reading
    /// - Returns: Boolean indicating success
    func open() -> Bool {
        do {
            fileHandle = try FileHandle(forReadingFrom: fileURL)
            return true
        } catch {
            print("Error opening pipe for reading: \(error.localizedDescription)")
            return false
        }
    }
    
    /// Reads data from the pipe
    /// - Returns: Data read from the pipe, or nil if there was an error
    func read() -> Data? {
        guard let fileHandle = fileHandle else {
            print("Error: Pipe not opened")
            return nil
        }
        
        do {
            // This will block until data is available
            let data = try fileHandle.readToEnd()
            return data
        } catch {
            print("Error reading from pipe: \(error.localizedDescription)")
            return nil
        }
    }
    
    /// Reads data from the pipe and converts it to a string
    /// - Returns: String read from the pipe, or nil if there was an error
    func readString() -> String? {
        guard let data = read() else {
            return nil
        }
        
        return String(data: data, encoding: .utf8)
    }
    
    /// Closes the pipe
    func close() {
        try? fileHandle?.close()
        fileHandle = nil
    }
} 
