import Foundation
import ArgumentParser
import Logging
import EasyMacMCP
import EasyMCP

@main
struct MCPHelper: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "mcp-helper",
        abstract: "MCP Helper CLI - a simple interface for MCP (Model Control Protocol)",
        version: "0.1.0",
        subcommands: [
            RunCommand.self
        ]
    )
}

@available(macOS 14.0, *)
struct RunCommand: AsyncParsableCommand, Decodable {
    static let configuration = CommandConfiguration(
        commandName: "run",
        abstract: "Start the MCP server to handle MCP protocol communications"
    )

    enum CodingKeys: String, CodingKey {
        case helperId
    }

    // Unique identifier for this helper instance
    private let helperId: String
    private let logger = Logger(label: "com.milestonemade.easymcp")

    // Pipe for sending requests to the Mac app
    private var requestPipe: RequestPipe

    // Pipe for receiving responses from the Mac app
    private var responsePipe: ResponsePipe

    init() {
        helperId = UUID().uuidString
        requestPipe = try! RequestPipe(
            url: PipeConstants.centralRequestPipePath(),
            logger: logger
        )
        responsePipe = try! ResponsePipe(
            url: PipeConstants.helperResponsePipePath(helperId: helperId),
            logger: logger
        )
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        helperId = try container.decode(String.self, forKey: .helperId)
        requestPipe = try RequestPipe(
            url: PipeConstants.centralRequestPipePath(),
            logger: logger
        )
        responsePipe = try ResponsePipe(
            url: PipeConstants.helperResponsePipePath(helperId: helperId),
            logger: logger
        )
    }

    func run() async throws {
        // Create pipes
        do {

            // Open pipes
            try await requestPipe.open()
            try await responsePipe.open()

            // Send initialize message
            try await requestPipe.sendRequest(.initialize(helperId: helperId))

            // Start reading responses
            await responsePipe.startReading { response in
                print("Received response: \(response)")
                // Handle different response types if needed
            }

        } catch {
            logger.error("Failed to set up pipes: \(error)")
            throw error
        }

        // build server
        let mcp = EasyMCP(logger: logger)

        #if DEBUG
        // Add a 3 second delay to allow time for the debugger to attach when wait-for-executable is checked in the scheme
        try await Task.sleep(for: .seconds(3))
        #endif

        // Set up signal handling to gracefully exit
        let signalSource = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
        signal(SIGINT, SIG_IGN)
        signalSource.setEventHandler {
            Task {
                // Send deinitialize message before stopping
                try? await self.requestPipe.sendRequest(.deinitialize(helperId: self.helperId))
                await self.responsePipe.close()
                await mcp.stop()
                RunCommand.exit()
            }
        }
        signalSource.resume()

        // Register a simple tool with no input
        try await mcp.register(tool: Tool(
            name: "helloWorld",
            description: "Returns a friendly greeting message"
        )) { _ in
            // Send the helloWorld request to the main app
            Task {
                let messageId = UUID().uuidString
                try? await self.requestPipe.sendRequest(.helloWorld(
                    helperId: self.helperId,
                    messageId: messageId
                ))
            }
            return Result(content: [.text(helloworld())], isError: false)
        }

        // Register a simple tool that accepts a single parameter
        try await mcp.register(tool: Tool(
            name: "helloPerson",
            description: "Returns a friendly greeting message",
            inputSchema: [
                "type": "object",
                "properties": [
                    "name": [
                        "type": "string",
                        "description": "Name to search for (will match given name or family name)",
                    ]
                ]
            ]
        )) { input in
            let name = input["name"]?.stringValue ?? "world"
            // Send the helloPerson request to the main app
            Task {
                let messageId = UUID().uuidString
                try? await self.requestPipe.sendRequest(.helloPerson(
                    helperId: self.helperId,
                    messageId: messageId,
                    name: name
                ))
            }
            return Result(content: [.text(hello(name))], isError: false)
        }

        // Start the server and keep it running
        try await mcp.start()

        Task {
            try await Task.sleep(for: .seconds(30))

            do {
                // Register a simple tool with no input
                try await mcp.register(tool: Tool(
                    name: "helloEveryone",
                    description: "Returns a friendly greeting message to everyone around"
                )) { _ in
                    return Result(content: [.text(helloworld())], isError: false)
                }
            } catch {
                logger.error("failed registering extra tool: \(error)")
            }
        }

        // Wait until the server is finished processing all input
        try await mcp.waitUntilComplete()

        // Clean up
        try? await requestPipe.sendRequest(.deinitialize(helperId: helperId))
        await responsePipe.close()
    }

    /// A simple example method
    public func helloworld() -> String {
        return "Hello iOS Folks! MCP SDK is configured and ready."
    }

    public func hello(_ name: String) -> String {
        return "Hello \(name)! MCP SDK is configured and ready."
    }
}
