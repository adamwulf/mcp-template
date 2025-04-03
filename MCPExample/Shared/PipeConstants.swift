import Foundation

/// Constants for pipe paths
public enum PipeConstants {
    /// Path to the pipe for IPC between MCPExample and mcp-helper
    public static func testPipePath() -> URL {
        // Use the app group container which is accessible by both processes
        guard let sharedContainerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: BuildSettings.GROUP_IDENTIFIER) else {
            fatalError("Failed to access app group container: \(BuildSettings.GROUP_IDENTIFIER). Ensure entitlements are properly configured.")
        }
        
        let pipePath = sharedContainerURL.appendingPathComponent("mcp_test_pipe")
        
        print("======== PIPE PATH DEBUG INFO ========")
        print("Process: \(ProcessInfo.processInfo.processName)")
        print("Bundle ID: \(Bundle.main.bundleIdentifier ?? "Unknown")")
        print("App group: \(BuildSettings.GROUP_IDENTIFIER)")
        print("Shared container: \(sharedContainerURL.path)")
        print("Pipe path: \(pipePath.path)")
        print("======================================")
        
        return pipePath
    }
} 