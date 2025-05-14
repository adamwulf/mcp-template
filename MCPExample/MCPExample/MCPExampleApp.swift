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
    private let mcpApp: MCPMacApp
    private let logger = Logger(label: "com.milestonemade.easymcp")

    init() {
        // Start listening for MCP requests on app launch
        mcpApp = MCPMacApp(readPipe: try! ReadPipe(url: PipeConstants.centralRequestPipePath()), helperWritePipe: { helperId in
            let url = PipeConstants.helperResponsePipePath(helperId: helperId)
            return try WritePipe(url: url)
        }, logger: logger)

        Task {
            do {
                mcpApp.startListening()
            } catch {
                print("Error setting up request pipe: \(error)")
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(mcpApp)
        }
    }
}
