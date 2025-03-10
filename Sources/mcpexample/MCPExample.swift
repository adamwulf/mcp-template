import Foundation
import ArgumentParser
import EasyMCP

@main
struct MCPExample: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "mcpexample",
        abstract: "MCP Example CLI - a simple interface for MCP (Model Control Protocol)",
        version: "0.1.0",
        subcommands: [
            HelloCommand.self,
            RunCommand.self
        ]
    )
}

struct HelloCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "hello",
        abstract: "Display a hello message from EasyMCP"
    )
    
    func run() async throws {
        print("MCP Example CLI")
        print("--------------")
        
        let mcp = EasyMCP()
        print(mcp.hello())
    }
}

@available(macOS 14.0, *)
struct RunCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "run",
        abstract: "Start the MCP server to handle MCP protocol communications"
    )
    
    func run() async throws {
        let mcp = EasyMCP()
        
        // Set up signal handling to gracefully exit
        let signalSource = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
        signal(SIGINT, SIG_IGN)
        signalSource.setEventHandler {
            Task {
                await mcp.stop()
                RunCommand.exit()
            }
        }
        signalSource.resume()
        
        // Start the server and keep it running
        try await mcp.start()
        
        // Keep the process alive until signal is received
        while true {
            do {
                try await Task.sleep(for: .seconds(1))
            } catch {
                break // Exit the loop if Task is cancelled
            }
        }
    }
} 
