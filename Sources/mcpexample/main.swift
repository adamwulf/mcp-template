import Foundation
import ArgumentParser
import EasyMCP

struct MCPExample: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "mcpexample",
        abstract: "MCP Example CLI - a simple interface for MCP (Model Control Protocol)",
        version: "0.1.0",
        subcommands: [
            HelloCommand.self
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
        
        let mcp = EasyMCP()
        print(mcp.hello())
    }
}

MCPExample.main() 