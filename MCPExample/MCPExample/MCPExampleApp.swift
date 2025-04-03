//
//  MCPExampleApp.swift
//  MCPExample
//
//  Created by Adam Wulf on 3/16/25.
//

import SwiftUI

@main
struct MCPExampleApp: App {
    // Create an app storage object for the app
    private let pipeReader = PipeReader()
    
    init() {
        // Start the pipe reader on app launch
        pipeReader.startReading { message in
            // We receive messages through the closure
            DispatchQueue.main.async {
                print("Pipe message received: \(message)")
            }
        }
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(pipeReader)
        }
    }
}

// Separate class to handle pipe reading
@MainActor
final class PipeReader: ObservableObject, Sendable {
    @Published var messages: [String] = []
    @Published var isReading: Bool = false
    @Published var writeStatus: String = ""
    
    private var pipeReadTask: Task<Void, Never>?
    
    func startReading(messageHandler: @escaping (String) -> Void) {
        guard !isReading else { return }
        
        isReading = true

        let pipePath = PipeConstants.testPipePath()

        pipeReadTask = Task {
            // Create a read pipe
            guard let readPipe = ReadPipe(url: pipePath) else {
                isReading = false
                return
            }
            
            // Open the pipe for reading
            guard readPipe.open() else {
                isReading = false
                return
            }
            
            // Continuously read from the pipe while isReading is true
            while isReading && !Task.isCancelled {
                if let message = readPipe.readString() {
                    DispatchQueue.main.async {
                        self.messages.append(message)
                        messageHandler(message)
                    }
                }
                
                // Add a small delay to avoid tight loop
                try? await Task.sleep(for: .milliseconds(100))
            }
            
            readPipe.close()
        }
    }
    
    func stopReading() {
        isReading = false
        pipeReadTask?.cancel()
        pipeReadTask = nil
    }
    
    func testWriteToPipe() {
        Task {
            writeStatus = "Checking pipe status..."
            
            // Print pipe status before attempting to write
            PipeTestHelpers.printPipeStatus()
            
            writeStatus = "Writing to pipe..."
            let success = await PipeTestHelpers.testWritePipeAsync(message: "Test message from MCPExampleApp!")
            writeStatus = success ? "Write successful!" : "Write failed!"
            
            // Print pipe status after writing
            PipeTestHelpers.printPipeStatus()
            
            // Clear status after a delay
            try? await Task.sleep(for: .seconds(2))
            writeStatus = ""
        }
    }
}
