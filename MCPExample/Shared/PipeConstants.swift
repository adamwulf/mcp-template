import Foundation

/// Constants for pipe paths to support multiple MCP server instances
public enum PipeConstants {
    /// Path to the central pipe for all MCP servers to send requests to the app (many-to-one)
    public static func centralRequestPipePath() -> URL {
        guard let sharedContainerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: BuildSettings.GROUP_IDENTIFIER) else {
            fatalError("Failed to access app group container: \(BuildSettings.GROUP_IDENTIFIER)")
        }

        return sharedContainerURL.appendingPathComponent("central_request_pipe")
    }

    /// Path to a server-specific pipe for the app to send responses to a specific MCP server (one-to-many)
    /// - Parameter helperId: The unique identifier for the MCP server instance
    public static func helperResponsePipePath(helperId: String) -> URL {
        guard let sharedContainerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: BuildSettings.GROUP_IDENTIFIER) else {
            fatalError("Failed to access app group container: \(BuildSettings.GROUP_IDENTIFIER)")
        }

        return sharedContainerURL.appendingPathComponent("response_pipe_\(helperId)")
    }

    // For backward compatibility during migration

    /// Path to the pipe for sending messages from helper to app (deprecated)
    @available(*, deprecated, message: "Use centralRequestPipePath instead")
    public static func helperToAppPipePath() -> URL {
        return centralRequestPipePath()
    }

    /// Path to the pipe for sending messages from app to helper (deprecated)
    @available(*, deprecated, message: "Use helperResponsePipePath(helperId:) instead")
    public static func appToHelperPipePath() -> URL {
        guard let sharedContainerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: BuildSettings.GROUP_IDENTIFIER) else {
            fatalError("Failed to access app group container: \(BuildSettings.GROUP_IDENTIFIER)")
        }

        return sharedContainerURL.appendingPathComponent("app_to_helper_pipe")
    }
}
