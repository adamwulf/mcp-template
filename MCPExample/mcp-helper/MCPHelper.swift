import Foundation
import ArgumentParser
import Logging
import EasyMacMCP
import EasyMCP
import MCP

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
    private var requestPipe: HelperRequestPipe

    // Pipe for receiving responses from the Mac app
    private var responsePipe: HelperResponsePipe

    init() {
        helperId = UUID().uuidString
        requestPipe = try! HelperRequestPipe(
            url: PipeConstants.centralRequestPipePath(),
            logger: logger
        )
        responsePipe = try! HelperResponsePipe(
            url: PipeConstants.helperResponsePipePath(helperId: helperId),
            logger: logger
        )
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        helperId = try container.decode(String.self, forKey: .helperId)
        requestPipe = try HelperRequestPipe(
            url: PipeConstants.centralRequestPipePath(),
            logger: logger
        )
        responsePipe = try HelperResponsePipe(
            url: PipeConstants.helperResponsePipePath(helperId: helperId),
            logger: logger
        )
    }

    func run() async throws {
        // Create EasyMacMCP server
        let mcpServer = EasyMacMCP<MCPRequest, MCPResponse>(
            helperId: helperId,
            requestPipe: requestPipe,
            responsePipe: responsePipe,
            logger: logger
        )

        #if DEBUG
        // Add a 3 second delay to allow time for the debugger to attach when wait-for-executable is checked in the scheme
        try await Task.sleep(for: .seconds(3))
        #endif

        // Set up signal handling to gracefully exit
        let signalSource = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
        signal(SIGINT, SIG_IGN)
        signalSource.setEventHandler {
            Task {
                await mcpServer.stop()
                RunCommand.exit()
            }
        }
        signalSource.resume()

        // Start the server - this will automatically register tools from MCPRequest.allCases
        try await mcpServer.start()

        // Send the initialize message to notify the Mac app about this helper
        try await requestPipe.sendRequest(MCPRequest.initialize(helperId: helperId))

        // Wait until the server is finished processing all input
        try await mcpServer.waitUntilComplete()

        // Clean up - send deinitialize message before exiting
        try await requestPipe.sendRequest(MCPRequest.deinitialize(helperId: helperId))
    }
}
