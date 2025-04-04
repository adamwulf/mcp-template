import Foundation

/// Constants for pipe paths for testing
public enum PipeConstants {
    /// Base directory for test pipes
    private static func testPipeDirectory() -> URL {
        let tempDirectory = FileManager.default.temporaryDirectory
        let testDirectory = tempDirectory.appendingPathComponent("EasyMacMCPTests", isDirectory: true)

        // Create directory if it doesn't exist
        try? FileManager.default.createDirectory(at: testDirectory, withIntermediateDirectories: true)

        return testDirectory
    }

    /// Path to the pipe for sending messages from helper to app
    public static func helperToAppPipePath() -> URL {
        return testPipeDirectory().appendingPathComponent("helper_to_app_pipe")
    }

    /// Path to the pipe for sending messages from app to helper
    public static func appToHelperPipePath() -> URL {
        return testPipeDirectory().appendingPathComponent("app_to_helper_pipe")
    }
}
