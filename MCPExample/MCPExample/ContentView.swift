//
//  ContentView.swift
//  MCPExample
//
//  Created by Adam Wulf on 3/16/25.
//

import SwiftUI

struct ContentView: View {
    @State private var helperPath: String = ""
    
    var body: some View {
        VStack(spacing: 16) {
            Text("MCP Helper Path")
                .font(.headline)
            
            TextField("", text: .constant(helperPath))
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .disabled(true)
                .font(.system(.body, design: .monospaced))
            
            Button("Copy Path") {
                #if os(macOS)
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(helperPath, forType: .string)
                #endif
            }
        }
        .padding()
        .frame(minWidth: 500)
        .onAppear {
            helperPath = getHelperPath()
        }
    }
    
    private func getHelperPath() -> String {
        guard let bundleURL = Bundle.main.url(forAuxiliaryExecutable: "mcp-helper") else {
            return "Helper executable not found"
        }
        return bundleURL.path
    }
}

#Preview {
    ContentView()
}
