//
//  MCPExampleApp.swift
//  MCPExample
//
//  Created by Adam Wulf on 3/16/25.
//

import SwiftUI
import EasyMacMCP
import Logging

@main
struct MCPExampleApp: App {
    // Create the actor that will manage MCP communication
    private let mcpApp = MCPMacApp()

    init() {
        // Start listening for MCP requests on app launch
        mcpApp.startListening()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(mcpApp)
        }
    }
}

// Actor to handle all MCP communication
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
                    self?.handleRequest(request)
                }
            } catch {
                print("Error setting up request pipe: \(error)")
            }
        }
    }
    
    private func handleRequest(_ request: MCPRequest) {
        // Extract helper ID from the request
        let helperId = request.helperId
        
        // Update the UI
        let requestDescription: String
        switch request {
        case .initialize:
            requestDescription = "Initialize request from helper: \(helperId)"
        case .deinitialize:
            requestDescription = "Deinitialize request from helper: \(helperId)"
        case .helloWorld:
            requestDescription = "HelloWorld request from helper: \(helperId)"
        case .helloPerson(_, _, let name):
            requestDescription = "HelloPerson request from helper: \(helperId) with name: \(name)"
        }
        
        self.messages.append(requestDescription)
        print(requestDescription)
        
        // Setup response pipe for this helper if needed
        setupResponsePipe(for: helperId)
    }
    
    private func setupResponsePipe(for helperId: String) {
        // Only create a new response pipe if we don't already have one for this helper
        if responsePipes[helperId] == nil {
            Task {
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
