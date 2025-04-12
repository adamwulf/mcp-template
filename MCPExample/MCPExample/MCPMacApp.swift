//
//  MCPMacApp.swift
//  MCPExample
//
//  Created by Adam Wulf on 4/12/25.
//
// Actor to handle all MCP communication

import SwiftUI
import EasyMacMCP
import Logging

@MainActor
final class MCPMacApp: ObservableObject, Sendable {
    @Published var messages: [String] = []
    @Published var writeStatus: String = ""

    // Maps helper IDs to their respective response pipes
    private var responsePipes: [String: HostResponsePipe] = [:]
    private var requestPipe: HostRequestPipe?
    private var requestReadTask: Task<Void, Never>?
    private let logger = Logger(label: "MCPMacApp")

    func startListening() {
        guard requestPipe == nil else { return }

        Task {
            do {
                // Get the central request pipe path
                let requestPipePath = PipeConstants.centralRequestPipePath()

                // Create a request pipe for reading from helpers
                let pipe = try HostRequestPipe(url: requestPipePath, logger: logger)
                self.requestPipe = pipe

                print("Opening request pipe at: \(requestPipePath.path)")
                try await pipe.open()
                print("Request pipe opened successfully")

                // Start reading requests
                await pipe.startReading { [weak self] request in
                    guard let self = self else { return }
                    Task {
                        await self.handleRequest(request)
                    }
                }
            } catch {
                print("Error setting up request pipe: \(error)")
            }
        }
    }

    private func handleRequest(_ request: MCPRequest) async {
        // Extract helper ID from the request
        let helperId = request.helperId
        let messageId = request.messageId

        logger.info("MAC_APP: Received request from helper \(helperId) with messageId: \(messageId)")

        // Update the UI
        let requestDescription: String
        switch request {
        case .initialize:
            requestDescription = "Initialize request from helper: \(helperId) with messageId: \(messageId)"
            // Setup response pipe only for initialize requests
            await setupResponsePipe(for: helperId)
        case .deinitialize:
            requestDescription = "Deinitialize request from helper: \(helperId) with messageId: \(messageId)"
            // Teardown response pipe for this helper
            await teardownResponsePipe(for: helperId)
        case .helloWorld:
            requestDescription = "HelloWorld request from helper: \(helperId) with messageId: \(messageId)"
            // Send response for helloWorld
            logger.info("MAC_APP: Preparing helloWorld response with messageId: \(messageId)")
            await sendHelloWorldResponse(helperId: helperId, messageId: messageId)
        case .helloPerson(_, _, let name):
            requestDescription = "HelloPerson request from helper: \(helperId) with messageId: \(messageId) and name: \(name)"
            // Send response for helloPerson
            logger.info("MAC_APP: Preparing helloPerson response with messageId: \(messageId)")
            await sendHelloPersonResponse(helperId: helperId, messageId: messageId, name: name)
        }

        DispatchQueue.main.async {
            self.messages.append(requestDescription)
        }
        print(requestDescription)
    }

    private func setupResponsePipe(for helperId: String) async {
        // Only create a new response pipe if we don't already have one for this helper
        if responsePipes[helperId] == nil {
            do {
                print("Setting up response pipe for helper \(helperId)")

                // Create the response pipe for this specific helper
                let responsePipe = try HostResponsePipe(helperId: helperId, logger: logger)

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

    private func sendHelloWorldResponse(helperId: String, messageId: String) async {
        guard let pipe = responsePipes[helperId] else {
            logger.error("MAC_APP: Error: No response pipe for helper \(helperId)")
            return
        }

        logger.info("MAC_APP: Creating helloWorld response with original messageId: \(messageId)")

        do {
            let response = MCPResponse.helloWorld(
                helperId: helperId,
                messageId: messageId,
                result: "Hello World from Mac app at \(Date())"
            )

            logger.info("MAC_APP: Response created with helperId: \(response.helperId), messageId: \(response.messageId)")

            try await pipe.sendResponse(response)

            logger.info("MAC_APP: Successfully sent helloWorld response with messageId: \(messageId)")

            DispatchQueue.main.async {
                self.messages.append("Sent helloWorld response to \(helperId) with messageId: \(messageId)")
            }
        } catch {
            logger.error("MAC_APP: Error sending helloWorld response: \(error)")
        }
    }

    private func sendHelloPersonResponse(helperId: String, messageId: String, name: String) async {
        guard let pipe = responsePipes[helperId] else {
            logger.error("MAC_APP: Error: No response pipe for helper \(helperId)")
            return
        }

        logger.info("MAC_APP: Creating helloPerson response with original messageId: \(messageId)")

        do {
            let response = MCPResponse.helloPerson(
                helperId: helperId,
                messageId: messageId,
                result: "Hello \(name) from Mac app at \(Date())"
            )

            logger.info("MAC_APP: Response created with helperId: \(response.helperId), messageId: \(response.messageId)")

            try await pipe.sendResponse(response)

            logger.info("MAC_APP: Successfully sent helloPerson response with messageId: \(messageId)")

            DispatchQueue.main.async {
                self.messages.append("Sent helloPerson response to \(helperId) with messageId: \(messageId)")
            }
        } catch {
            logger.error("MAC_APP: Error sending helloPerson response: \(error)")
        }
    }

    func stopListening() {
        // Cancel the request reading task
        Task {
            await requestPipe?.close()
            requestPipe = nil
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

    func testWriteToPipe() {
        // Clear previous status
        writeStatus = "Sending test message..."

        // Check if we have any helpers connected
        guard !responsePipes.isEmpty else {
            writeStatus = "No helpers connected. Launch mcp-helper first."
            return
        }

        // Pick the first helper or a random one
        let randomHelperId = responsePipes.keys.randomElement()!

        Task {
            do {
                // Create a test response
                let messageId = UUID().uuidString
                let response = MCPResponse.helloWorld(
                    helperId: randomHelperId,
                    messageId: messageId,
                    result: "Test message from Mac app at \(Date())"
                )

                // Send the response
                try await responsePipes[randomHelperId]?.sendResponse(response)

                // Update status on success
                DispatchQueue.main.async {
                    self.writeStatus = "Message sent successfully to helper: \(randomHelperId)"
                    self.messages.append("Sent helloWorld to \(randomHelperId)")
                }
            } catch {
                // Update status on failure
                DispatchQueue.main.async {
                    self.writeStatus = "Error: \(error.localizedDescription)"
                }
            }
        }
    }
}
