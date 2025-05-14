//
//  EasyMCPMac.swift
//  mcp-template
//
//  Created by Adam Wulf on 4/12/25.
//

import SwiftUI
import Logging
import Foundation

@MainActor
open class EasyMCPHost<Request: MCPRequestProtocol, Response: MCPResponseProtocol>: Sendable {
    // Maps helper IDs to their respective response pipes
    private var responsePipes: [String: HostResponsePipe<Response>] = [:]
    // Maps helper IDs to their cleanup tasks
    private var cleanupTasks: [String: Task<Void, Never>] = [:]
    private var requestPipe: HostRequestPipe<Request>
    private var requestReadTask: Task<Void, Never>?
    public let logger: Logger?
    private var helperWritePipe: (String) throws -> WritePipe
    
    // Timeout for inactive helpers (in seconds)
    private let inactivityTimeout: TimeInterval = 30
    
    // Directory for pipes
    private var pipesDirectory: URL?
    
    // App Group Identifier used for the shared container
    private let groupIdentifier: String
    
    public init(readPipe: ReadPipe, helperWritePipe: @escaping (String) throws -> WritePipe, logger: Logger?, groupIdentifier: String) {
        self.requestPipe = HostRequestPipe<Request>(readPipe: readPipe, logger: logger)
        self.helperWritePipe = helperWritePipe
        self.logger = logger
        self.groupIdentifier = groupIdentifier
    }

    // caller must call scanForExistingHelpers separately
    // with the appropriate directory
    public func startListening() async throws {
        try await requestPipe.open()
        print("Request pipe opened successfully")

        // Start reading requests
        await requestPipe.startReading { [weak self] request in
            guard let self = self else { return }
            await self.handleRequest(request)
        }
    }

    open func handleRequest(_ request: Request) async {
        // Extract helper ID from the request
        let helperId = request.helperId
        let messageId = request.messageId

        logger?.info("MAC_APP: Received request from helper \(helperId) with messageId: \(messageId)")
        
        // Since we heard from this helper, cancel any cleanup task
        cancelCleanupTask(for: helperId)

        if request.isInitialize {
            await setupResponsePipe(for: helperId)
        } else if request.isDeinitialize {
            await teardownResponsePipe(for: helperId)
        }
    }

    public func stopListening() {
        // Cancel the request reading task
        Task {
            await requestPipe.close()
        }

        // Cancel all cleanup tasks
        for (_, task) in cleanupTasks {
            task.cancel()
        }
        cleanupTasks.removeAll()

        // Close all response pipes
        for (helperId, pipe) in responsePipes {
            Task {
                print("Closing response pipe for helper \(helperId)")
                await pipe.close()
            }
        }
        responsePipes.removeAll()
    }

    public func responsePipe(for helperId: String) -> HostResponsePipe<Response>? {
        return responsePipes[helperId]
    }

    // MARK: - Private
    
    /// Scans the provided directory for existing response pipes and reconnects to them
    /// - Parameter directoryURL: The URL of the directory to scan for pipe files
    public func scanForExistingHelpers(in directoryURL: URL) async {
        // Store directory for future pipe operations
        self.pipesDirectory = directoryURL
        
        do {
            let fileManager = FileManager.default
            let contents = try fileManager.contentsOfDirectory(at: directoryURL, includingPropertiesForKeys: nil)
            
            // Find all files that match the response pipe pattern
            for url in contents {
                let filename = url.lastPathComponent
                if filename.hasPrefix("response_pipe_"), fileManager.isPipe(at: url) {
                    // Extract the helper ID from the filename
                    let helperId = String(filename.dropFirst("response_pipe_".count))
                    logger?.info("Found existing pipe for helper: \(helperId)")
                    
                    // Set up the response pipe for this helper
                    await setupResponsePipe(for: helperId)
                    
                    // Start a cleanup task for this helper
                    startCleanupTask(for: helperId)
                }
            }
        } catch {
            logger?.error("Error scanning for existing helpers: \(error)")
        }
    }

    private func setupResponsePipe(for helperId: String) async {
        // Only create a new response pipe if we don't already have one for this helper
        if responsePipes[helperId] == nil {
            do {
                print("Setting up response pipe for helper \(helperId)")

                // Create the response pipe for this specific helper
                let pipe = try helperWritePipe(helperId)
                let responsePipe = try HostResponsePipe<Response>(helperId: helperId, writePipe: pipe, logger: logger)

                // Open the pipe
                try await responsePipe.open()

                // Store it in our dictionary
                responsePipes[helperId] = responsePipe

                print("Response pipe for helper \(helperId) created successfully")

                // If this is an initialize request, we could send a response here
                // await responsePipe.sendResponse(MCPResponse.success(helperId: helperId, ...))
            } catch {
                print("Error creating response pipe for helper \(helperId): \(error)")
            }
        }
    }

    private func teardownResponsePipe(for helperId: String) async {
        guard let pipe = responsePipes[helperId] else { return }

        print("Closing response pipe for helper \(helperId)")
        await pipe.close()
        responsePipes.removeValue(forKey: helperId)
        
        // Also cancel any cleanup task
        cancelCleanupTask(for: helperId)
    }
    
    /// Starts a cleanup task for a helper that will close and delete the pipe if no requests are received within the timeout
    private func startCleanupTask(for helperId: String) {
        // Cancel any existing cleanup task first
        cancelCleanupTask(for: helperId)
        
        // Create a new cleanup task
        cleanupTasks[helperId] = Task {
            do {
                // Wait for the timeout period
                try await Task.sleep(nanoseconds: UInt64(inactivityTimeout * 1_000_000_000))
                
                // If we get here, the timeout expired without activity
                logger?.info("Helper \(helperId) timed out after \(inactivityTimeout) seconds of inactivity")
                
                // Close and remove the pipe
                await teardownResponsePipe(for: helperId)
                
                // Delete the physical pipe file if we know where it is
                if let directory = pipesDirectory {
                    await deletePipeFile(for: helperId, in: directory)
                }
            } catch {
                // Task was likely cancelled, which is expected
                if !(error is CancellationError) {
                    logger?.error("Error in cleanup task for helper \(helperId): \(error)")
                }
            }
            
            // Remove the task from our dictionary
            if self.cleanupTasks[helperId] != nil {
                self.cleanupTasks.removeValue(forKey: helperId)
            }
        }
    }
    
    /// Cancels the cleanup task for a helper
    private func cancelCleanupTask(for helperId: String) {
        if let task = cleanupTasks[helperId] {
            task.cancel()
            cleanupTasks.removeValue(forKey: helperId)
            
            // Start a new cleanup task
            startCleanupTask(for: helperId)
        } else {
            // Only start a new task if we have a pipe for this helper
            if responsePipes[helperId] != nil {
                startCleanupTask(for: helperId)
            }
        }
    }
    
    /// Deletes the physical pipe file for a helper
    /// - Parameters:
    ///   - helperId: ID of the helper whose pipe should be deleted
    ///   - directoryURL: Base directory where the pipe is located
    private func deletePipeFile(for helperId: String, in directoryURL: URL) async {
        let pipePath = directoryURL.appendingPathComponent("response_pipe_\(helperId)")
        do {
            try FileManager.default.removeItem(at: pipePath)
            logger?.info("Deleted pipe file for helper \(helperId)")
        } catch {
            logger?.error("Failed to delete pipe file for helper \(helperId): \(error)")
        }
    }
}
