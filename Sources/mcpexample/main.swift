import Foundation
import ArgumentParser
import EasyMCP

struct MCPExample: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "mcpexample",
        abstract: "MCP Example CLI - a simple interface for MCP (Model Control Protocol)",
        version: "0.1.0",
        subcommands: [
            HelloCommand.self,
            RunCommand.self
        ],
        defaultSubcommand: HelloCommand.self
    )
}

struct HelloCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "hello",
        abstract: "Display a hello message from EasyMCP"
    )
    
    func run() throws {
        print("MCP Example CLI")
        print("--------------")
        
        if #available(macOS 14.0, *) {
            let mcp = EasyMCP()
            print(mcp.hello())
        } else {
            print("This command requires macOS 14.0 or later.")
            throw ExitCode.failure
        }
    }
}

@available(macOS 14.0, *)
struct RunCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "run",
        abstract: "Start the MCP server to handle MCP protocol communications"
    )
    
    func run() async throws {
        print("Starting MCP server...")
        
        let mcp = EasyMCP()
        
        // Set up signal handling to gracefully exit
        let signalSource = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
        signal(SIGINT, SIG_IGN)
        signalSource.setEventHandler {
            print("\nShutting down MCP server...")
            Task {
                await mcp.stop()
                RunCommand.exit()
            }
        }
        signalSource.resume()
        
        // Start the server and keep it running
        try await mcp.start()
        
        // Keep the process alive until signal is received
        dispatchMain()
    }
}

// Since we have an async command, we need to handle the async main
if #available(macOS 14.0, *) {
    MCPExample.main()
} else {
    print("This application requires macOS 14.0 or later.")
    exit(1)
} 
