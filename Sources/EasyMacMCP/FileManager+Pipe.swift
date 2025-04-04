import Foundation
import Darwin

extension FileManager {
    /// Checks if a path points to a named pipe (FIFO)
    /// - Parameter url: The URL to check
    /// - Returns: True if the path exists and is a pipe, false otherwise
    func isPipe(at url: URL) -> Bool {
        guard url.isFileURL else {
            return false
        }

        let path = url.path

        // Use stat to check if it's a pipe
        var statInfo = stat()
        guard stat(path, &statInfo) == 0 else {
            return false // Can't stat the file
        }

        // S_ISFIFO macro checks if it's a pipe (FIFO)
        return (statInfo.st_mode & S_IFMT) == S_IFIFO
    }
}
