import Foundation

/// Constants for pipe paths
public enum PipeConstants {
    /// Path to the pipe for IPC between MCPExample and mcp-helper
    public static func testPipePath() -> URL {
        // Use the system temp directory instead of the app's documents directory
        // This should be accessible by both sandboxed processes
        let tempDir = FileManager.default.temporaryDirectory.deletingLastPathComponent().deletingLastPathComponent()
        let systemTempDir = tempDir.appendingPathComponent("T")
        let pipePath = systemTempDir.appendingPathComponent("mcp_test_pipe")
        
        print("======== PIPE PATH DEBUG INFO ========")
        print("Process: \(ProcessInfo.processInfo.processName)")
        print("Bundle ID: \(Bundle.main.bundleIdentifier ?? "Unknown")")
        print("System temp directory: \(systemTempDir.path)")
        print("Pipe path: \(pipePath.path)")
        
        // Print other useful directories for debugging sandbox issues
        print("Home directory: \(FileManager.default.homeDirectoryForCurrentUser.path)")
        print("App temp directory: \(FileManager.default.temporaryDirectory.path)")
        
        if let appSupportDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            print("App Support directory: \(appSupportDir.path)")
        }
        
        if let sharedContainerDir = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "com.milestonemade.MCPExample") {
            print("Shared container: \(sharedContainerDir.path)")
        } else {
            print("No shared container available")
        }
        print("======================================")
        
        return pipePath
    }
} 