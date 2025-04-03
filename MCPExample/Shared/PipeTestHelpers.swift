import Foundation

/// Utility class for testing named pipe functionality
public class PipeTestHelpers {

    /// Tests writing to a pipe at the specified path
    /// - Parameters:
    ///   - message: The message to write to the pipe
    ///   - pipePath: The URL path to the pipe (defaults to the test pipe path)
    ///   - completion: Optional completion handler called with success/failure status
    /// - Returns: Boolean indicating success
    public static func testWritePipe(
        message: String,
        pipePath: URL,
        completion: ((Bool) -> Void)? = nil
    ) {
        var writePipe: WritePipe?
        do {
            // Create a write pipe
            let pipe = try WritePipe(url: pipePath)
            writePipe = pipe

            // Open the pipe for writing
            try pipe.open()

            // Write test message to the pipe
            try pipe.write(message)

            // Close the pipe
            pipe.close()

            completion?(true)
        } catch {
            writePipe?.close()
            completion?(false)
        }
    }

    /// Tests writing to a pipe asynchronously
    /// - Parameters:
    ///   - message: The message to write to the pipe
    ///   - pipePath: The URL path to the pipe (defaults to the test pipe path)
    /// - Returns: Boolean indicating success
    @available(macOS 10.15, *)
    public static func testWritePipeAsync(
        message: String = "Hello World from PipeTestHelpers!",
        pipePath: URL = PipeConstants.testPipePath()
    ) async -> Bool {
        return await withCheckedContinuation { continuation in
            testWritePipe(message: message, pipePath: pipePath) { success in
                continuation.resume(returning: success)
            }
        }
    }

    /// Checks the status of a pipe file and returns diagnostic information
    /// - Parameter pipePath: The URL path to the pipe (defaults to the test pipe path)
    /// - Returns: Dictionary with diagnostic information
    public static func checkPipeStatus(pipePath: URL = PipeConstants.testPipePath()) -> [String: String] {
        let fileManager = FileManager.default
        var result: [String: String] = [:]

        let pipePathString = pipePath.path
        result["path"] = pipePathString

        // Check if file exists
        let fileExists = fileManager.fileExists(atPath: pipePathString)
        result["exists"] = "\(fileExists)"

        if fileExists {
            // Check if it's a pipe
            let isPipe = fileManager.isPipe(at: pipePath)
            result["isPipe"] = "\(isPipe)"

            // Get permissions
            if let attributes = try? fileManager.attributesOfItem(atPath: pipePathString) {
                if let fileType = attributes[.type] as? FileAttributeType {
                    result["fileType"] = "\(fileType)"
                }

                if let posixPermissions = attributes[.posixPermissions] as? NSNumber {
                    result["permissions"] = String(format: "%o", posixPermissions.intValue)
                }

                if let owner = attributes[.ownerAccountName] as? String {
                    result["owner"] = owner
                }

                if let group = attributes[.groupOwnerAccountName] as? String {
                    result["group"] = group
                }

                if let creationDate = attributes[.creationDate] as? Date {
                    result["creationDate"] = "\(creationDate)"
                }

                if let size = attributes[.size] as? NSNumber {
                    result["size"] = "\(size)"
                }
            } else {
                result["attributesError"] = "Could not get file attributes"
            }

            // Try to stat the file
            var statBuf = stat()
            if stat(pipePathString, &statBuf) == 0 {
                result["mode"] = String(format: "%o", statBuf.st_mode)
                result["inode"] = "\(statBuf.st_ino)"
                result["device"] = "\(statBuf.st_dev)"
                result["links"] = "\(statBuf.st_nlink)"
                result["uid"] = "\(statBuf.st_uid)"
                result["gid"] = "\(statBuf.st_gid)"
                result["size"] = "\(statBuf.st_size)"
            } else {
                result["statError"] = String(cString: strerror(errno))
            }
        }

        // Check directory permissions
        let directoryPath = pipePath.deletingLastPathComponent().path
        result["directoryPath"] = directoryPath

        if let dirAttributes = try? fileManager.attributesOfItem(atPath: directoryPath) {
            if let dirPermissions = dirAttributes[.posixPermissions] as? NSNumber {
                result["directoryPermissions"] = String(format: "%o", dirPermissions.intValue)
            }

            if let dirOwner = dirAttributes[.ownerAccountName] as? String {
                result["directoryOwner"] = dirOwner
            }
        } else {
            result["directoryAttributesError"] = "Could not get directory attributes"
        }

        return result
    }

    /// Prints the status of a pipe to the console for debugging
    /// - Parameter pipePath: The URL path to the pipe (defaults to the test pipe path)
    public static func printPipeStatus(pipePath: URL = PipeConstants.testPipePath()) {
        let status = checkPipeStatus(pipePath: pipePath)

        Logging.printInfo("===== PIPE STATUS =====")
        for (key, value) in status.sorted(by: { $0.key < $1.key }) {
            Logging.printInfo("\(key): \(value)")
        }
        Logging.printInfo("======================")
    }
}
