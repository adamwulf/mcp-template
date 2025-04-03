import Foundation

/// Constants for pipe paths
public enum PipeConstants {
    /// Path to the pipe for IPC between MCPExample and mcp-helper
    public static func testPipePath() -> URL {
        // Use the app group container which is accessible by both processes
        guard let sharedContainerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: BuildSettings.GROUP_IDENTIFIER) else {
            fatalError("Failed to access app group container: \(BuildSettings.GROUP_IDENTIFIER). Ensure entitlements are properly configured.")
        }
        
        return sharedContainerURL.appendingPathComponent("mcp_test_pipe")
    }
} 
