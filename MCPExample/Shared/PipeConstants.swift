import Foundation

/// Constants for pipe paths
public enum PipeConstants {
    /// Path to the pipe for IPC between MCPExample and mcp-helper
    public static func testPipePath() -> URL {
        let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return documentsDir.appendingPathComponent("mcp_test_pipe")
    }
} 