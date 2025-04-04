import Foundation

/// Constants for pipe paths
public enum PipeConstants {
    /// Path to the pipe for sending messages from helper to app
    public static func helperToAppPipePath() -> URL {
        guard let sharedContainerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: BuildSettings.GROUP_IDENTIFIER) else {
            fatalError("Failed to access app group container: \(BuildSettings.GROUP_IDENTIFIER)")
        }

        return sharedContainerURL.appendingPathComponent("helper_to_app_pipe")
    }

    /// Path to the pipe for sending messages from app to helper
    public static func appToHelperPipePath() -> URL {
        guard let sharedContainerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: BuildSettings.GROUP_IDENTIFIER) else {
            fatalError("Failed to access app group container: \(BuildSettings.GROUP_IDENTIFIER)")
        }

        return sharedContainerURL.appendingPathComponent("app_to_helper_pipe")
    }
}
