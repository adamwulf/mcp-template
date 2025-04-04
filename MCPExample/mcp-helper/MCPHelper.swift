import Foundation
import ArgumentParser
import EasyMCP
import Logging

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
    private let pipes: HelperPipes

    init() {
        helperId = UUID().uuidString
        let helperToApp = try! WritePipe(url: PipeConstants.helperToAppPipePath())
        let appToHelper = try! ReadPipe(url: PipeConstants.appToHelperPipePath())
        pipes = HelperPipes(helperToAppPipe: helperToApp, appToHelperPipe: appToHelper)
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        helperId = try container.decode(String.self, forKey: .helperId)
        let helperToApp = try WritePipe(url: PipeConstants.helperToAppPipePath())
        let appToHelper = try ReadPipe(url: PipeConstants.appToHelperPipePath())
        pipes = HelperPipes(helperToAppPipe: helperToApp, appToHelperPipe: appToHelper)
    }

    func run() async throws {
        try await pipes.open()

        // Send initialize message
        await pipes.sendToolRequest(.initialize(helperId: helperId))

        // build server
        let logger = Logger(label: "com.milestonemade.easymcp")
        let mcp = EasyMCP(logger: logger)

        try await Task.sleep(for: .seconds(3))

        // Use the new PipeTestHelpers to test pipe functionality
        Task {
            await PipeTestHelpers.testWritePipeAsync(
                message: "Hello World from mcp-helper through PipeTestHelpers!\n"
            )
        }

        // Set up signal handling to gracefully exit
        let signalSource = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
        signal(SIGINT, SIG_IGN)
        signalSource.setEventHandler {
            Task {
                // Send deinitialize message before stopping
                await pipes.sendToolRequest(.deinitialize(helperId: self.helperId))
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
                await pipes.sendToolRequest(.helloWorld(helperId: self.helperId, messageId: UUID().uuidString))
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
                await pipes.sendToolRequest(.helloPerson(helperId: self.helperId, messageId: UUID().uuidString, name: name))
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

        await pipes.sendToolRequest(.deinitialize(helperId: helperId))
        try await pipes.close()
    }

    /// A simple example method
    public func helloworld() -> String {
        return "Hello iOS Folks! MCP SDK is configured and ready."
    }

    public func hello(_ name: String) -> String {
        return "Hello \(name)! MCP SDK is configured and ready."
    }
}
