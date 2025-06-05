//
//  EasyMCPMac.swift
//  mcp-template
//
//  Created by Adam Wulf on 4/12/25.
//

import SwiftUI
import Logging

@MainActor
open class EasyMCPHost<Request: MCPRequestProtocol, Response: MCPResponseProtocol>: Sendable {
    // Maps helper IDs to their respective response pipes
    private var responsePipes: [String: HostResponsePipe<Response>] = [:]
    private var requestPipe: HostRequestPipe<Request>
    private var requestReadTask: Task<Void, Never>?
    public let logger: Logger?
    private var helperWritePipe: (String) throws -> any PipeWritable

    public init(readPipe: any PipeReadable, helperWritePipe: @escaping (String) throws -> any PipeWritable, logger: Logger?) {
        self.requestPipe = HostRequestPipe<Request>(readPipe: readPipe, logger: logger)
        self.helperWritePipe = helperWritePipe
        self.logger = logger
    }

    public func startListening() {
        Task {
            do {
                try await requestPipe.open()
                print("Request pipe opened successfully")

                // Start reading requests
                await requestPipe.startReading { [weak self] request in
                    guard let self = self else { return }
                    await self.handleRequest(request)
                }
            } catch {
                print("Error setting up request pipe: \(error)")
            }
        }
    }

    open func handleRequest(_ request: Request) async {
        // Extract helper ID from the request
        let helperId = request.helperId
        let messageId = request.messageId

        logger?.info("MAC_APP: Received request from helper \(helperId) with messageId: \(messageId)")

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

    private func setupResponsePipe(for helperId: String) async {
        // Only create a new response pipe if we don't already have one for this helper
        if responsePipes[helperId] == nil {
            do {
                print("Setting up response pipe for helper \(helperId)")

                // Create the response pipe for this specific helper
                let pipe = try helperWritePipe(helperId)
                let responsePipe = HostResponsePipe<Response>(helperId: helperId, writePipe: pipe, logger: logger)

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
    }
}
