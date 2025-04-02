//
//  ContentView.swift
//  MCPExample
//
//  Created by Adam Wulf on 3/16/25.
//

import SwiftUI

struct ContentView: View {
    @State private var helperPath: String = ""
    @EnvironmentObject private var pipeReader: PipeReader
    
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
            
            Divider()
            
            HStack {
                Button("Test Write to Pipe") {
                    pipeReader.testWriteToPipe()
                }
                .padding(8)
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(8)
                
                if !pipeReader.writeStatus.isEmpty {
                    Text(pipeReader.writeStatus)
                        .padding(8)
                        .background(Color.gray.opacity(0.2))
                        .cornerRadius(8)
                }
            }
            
            Divider()
            
            Text("Pipe Messages")
                .font(.headline)
            
            VStack(alignment: .leading) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(pipeReader.messages, id: \.self) { message in
                            Text(message)
                                .padding(4)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .frame(height: 150)
                .border(Color.gray.opacity(0.2))
            }
            
            Button("Clear Messages") {
                pipeReader.messages.removeAll()
            }
            .disabled(pipeReader.messages.isEmpty)
        }
        .padding()
        .frame(minWidth: 500, minHeight: 400)
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
