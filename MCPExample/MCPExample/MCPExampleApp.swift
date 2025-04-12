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
