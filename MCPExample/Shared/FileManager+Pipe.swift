import Foundation

extension FileManager {
    /// Checks if a path points to a named pipe (FIFO)
    /// - Parameter url: The URL to check
    /// - Returns: True if the path exists and is a pipe, false otherwise
    func isPipe(at url: URL) -> Bool {
        let path = url.path
        var isDirectory: ObjCBool = false
        
        guard fileExists(atPath: path, isDirectory: &isDirectory) else {
            return false  // Path doesn't exist
        }
        
        do {
            let attributes = try attributesOfItem(atPath: path)
            if let fileType = attributes[.type] as? FileAttributeType {
                return fileType == .typeSocket || fileType == .typeBlockSpecial || fileType == .typeCharacterSpecial
            }
        } catch {
            Logging.printError("Error getting file attributes", error: error)
        }
        
        return false
    }
} 