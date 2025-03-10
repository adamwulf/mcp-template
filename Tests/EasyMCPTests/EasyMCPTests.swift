import XCTest
@testable import EasyMCP

final class EasyMCPTests: XCTestCase {
    func testHello() throws {
        let mcp = EasyMCP()
        XCTAssertEqual(mcp.hello(), "Hello from EasyMCP!")
    }
} 