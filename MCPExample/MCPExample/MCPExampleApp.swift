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

        let pipePath = PipeConstants.helperToAppPipePath()

        // Use Task.detached to run the pipe reading off the main actor
        pipeReadTask = Task.detached { [weak self] in
            guard let self = self else { return }

            var readPipe: ReadPipe?
            do {
                // Create a read pipe
                let pipe = try ReadPipe(url: pipePath)
                readPipe = pipe

                // Open the pipe for reading
                try await pipe.open()

                // Get a local copy of isReading to avoid constantly checking across actor boundaries
                var shouldContinueReading = await self.isReading

                // Continuously read from the pipe while isReading is true
                while shouldContinueReading && !Task.isCancelled {
                    if let message = try await pipe.readLine() {
                        // Update UI state on the main actor
                        await MainActor.run {
                            self.messages.append(message)
                            messageHandler(message)
                        }
                    }

                    // Check if we should continue reading
                    shouldContinueReading = await self.isReading
                }

                await pipe.close()
            } catch {
                await readPipe?.close()

                // Update UI state on the main actor
                await MainActor.run {
                    self.isReading = false
                }
            }
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
