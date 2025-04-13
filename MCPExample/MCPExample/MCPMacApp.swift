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
final class MCPMacApp: EasyMCPHost<MCPRequest, MCPResponse>, ObservableObject {
    @Published var messages: [String] = []
    @Published var writeStatus: String = ""

    override func handleRequest(_ request: MCPRequest) async {
        await super.handleRequest(request)

        // Extract helper ID from the request
        let helperId = request.helperId
        let messageId = request.messageId

        logger?.info("MAC_APP: Received request from helper \(helperId) with messageId: \(messageId)")

        // Update the UI
        let requestDescription: String
        switch request {
        case .initialize:
            requestDescription = "Initialize request from helper: \(helperId) with messageId: \(messageId)"
        case .deinitialize:
            requestDescription = "Deinitialize request from helper: \(helperId) with messageId: \(messageId)"
        case .helloWorld:
            requestDescription = "HelloWorld request from helper: \(helperId) with messageId: \(messageId)"
            // Send response for helloWorld
            logger?.info("MAC_APP: Preparing helloWorld response with messageId: \(messageId)")
            await sendHelloWorldResponse(helperId: helperId, messageId: messageId)
        case .helloPerson(_, _, let name):
            requestDescription = "HelloPerson request from helper: \(helperId) with messageId: \(messageId) and name: \(name)"
            // Send response for helloPerson
            logger?.info("MAC_APP: Preparing helloPerson response with messageId: \(messageId)")
            await sendHelloPersonResponse(helperId: helperId, messageId: messageId, name: name)
        }

        DispatchQueue.main.async {
            self.messages.append(requestDescription)
        }
        print(requestDescription)
    }

    private func sendHelloWorldResponse(helperId: String, messageId: String) async {
        guard let pipe = responsePipe(for: helperId) else {
            logger?.error("MAC_APP: Error: No response pipe for helper \(helperId)")
            return
        }

        logger?.info("MAC_APP: Creating helloWorld response with original messageId: \(messageId)")

        do {
            let response = MCPResponse.helloWorld(
                helperId: helperId,
                messageId: messageId,
                result: "Hello World from Mac app at \(Date())"
            )

            logger?.info("MAC_APP: Response created with helperId: \(response.helperId), messageId: \(response.messageId)")

            try await pipe.sendResponse(response)

            logger?.info("MAC_APP: Successfully sent helloWorld response with messageId: \(messageId)")

            DispatchQueue.main.async {
                self.messages.append("Sent helloWorld response to \(helperId) with messageId: \(messageId)")
            }
        } catch {
            logger?.error("MAC_APP: Error sending helloWorld response: \(error)")
        }
    }

    private func sendHelloPersonResponse(helperId: String, messageId: String, name: String) async {
        guard let pipe = responsePipe(for: helperId) else {
            logger?.error("MAC_APP: Error: No response pipe for helper \(helperId)")
            return
        }

        logger?.info("MAC_APP: Creating helloPerson response with original messageId: \(messageId)")

        do {
            let response = MCPResponse.helloPerson(
                helperId: helperId,
                messageId: messageId,
                result: "Hello \(name) from Mac app at \(Date())"
            )

            logger?.info("MAC_APP: Response created with helperId: \(response.helperId), messageId: \(response.messageId)")

            try await pipe.sendResponse(response)

            logger?.info("MAC_APP: Successfully sent helloPerson response with messageId: \(messageId)")

            DispatchQueue.main.async {
                self.messages.append("Sent helloPerson response to \(helperId) with messageId: \(messageId)")
            }
        } catch {
            logger?.error("MAC_APP: Error sending helloPerson response: \(error)")
        }
    }
}
