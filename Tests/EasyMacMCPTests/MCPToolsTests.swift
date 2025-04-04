import XCTest
@testable import EasyMacMCP

final class MCPToolsTests: XCTestCase {
    var responseManager: ResponseManager!
    var mockWriter: MockPipeWriter!
    var mcpTools: MCPTools!

    override func setUp() {
        super.setUp()
        responseManager = ResponseManager()
        mockWriter = MockPipeWriter()
        mcpTools = MCPTools(helperId: "test-helper", writePipe: mockWriter, responseManager: responseManager)
    }

    override func tearDown() {
        mcpTools = nil
        mockWriter = nil
        responseManager = nil
        super.tearDown()
    }

    func testHelloWorld_Success() async throws {
        // Set up an expectation for the request
        let requestExpectation = expectation(description: "Request received")

        // Define the expected message ID
        var capturedMessageId: String?

        // Set up the write handler to capture the message ID
        await mockWriter.writeHandler = { message in
            // Parse the JSON to get the message ID
            if let data = message.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let helloWorld = json["helloWorld"] as? [String: Any],
               let messageId = helloWorld["messageId"] as? String {
                capturedMessageId = messageId
                requestExpectation.fulfill()
            }
        }

        // Create a task that will send the response after the request is captured
        Task {
            // Wait for the request to be sent
            await waitForExpectations(timeout: 1.0)

            // Make sure we captured a message ID
            guard let messageId = capturedMessageId else {
                XCTFail("No message ID captured")
                return
            }

            // Send a response with the captured message ID
            let response = MCPResponse.helloWorld(
                helperId: "test-helper",
                messageId: messageId,
                result: "Hello from tests!"
            )

            // Handle the response
            await responseManager.handleResponse(response)
        }

        // Call the hello world tool
        let result = try await mcpTools.helloWorld(timeout: 2.0)

        // Verify the result
        XCTAssertEqual(result, "Hello from tests!")

        // Verify a message was written
        let messages = await mockWriter.writtenMessages
        XCTAssertEqual(messages.count, 1)
        XCTAssertTrue(messages[0].contains("helloWorld"))
    }

    func testHelloPerson_Success() async throws {
        // Set up an expectation for the request
        let requestExpectation = expectation(description: "Request received")

        // Define the expected message ID and name
        var capturedMessageId: String?
        var capturedName: String?

        // Set up the write handler to capture the message ID and name
        await mockWriter.writeHandler = { message in
            // Parse the JSON to get the message ID and name
            if let data = message.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let helloPerson = json["helloPerson"] as? [String: Any],
               let messageId = helloPerson["messageId"] as? String,
               let name = helloPerson["name"] as? String {
                capturedMessageId = messageId
                capturedName = name
                requestExpectation.fulfill()
            }
        }

        // Create a task that will send the response after the request is captured
        Task {
            // Wait for the request to be sent
            await waitForExpectations(timeout: 1.0)

            // Make sure we captured a message ID
            guard let messageId = capturedMessageId, let name = capturedName else {
                XCTFail("No message ID or name captured")
                return
            }

            // Send a response with the captured message ID
            let response = MCPResponse.helloPerson(
                helperId: "test-helper",
                messageId: messageId,
                result: "Hello, \(name)!"
            )

            // Handle the response
            await responseManager.handleResponse(response)
        }

        // Call the hello person tool
        let result = try await mcpTools.helloPerson(name: "John", timeout: 2.0)

        // Verify the result
        XCTAssertEqual(result, "Hello, John!")

        // Verify a message was written
        let messages = await mockWriter.writtenMessages
        XCTAssertEqual(messages.count, 1)
        XCTAssertTrue(messages[0].contains("helloPerson"))
        XCTAssertTrue(messages[0].contains("John"))
    }

    func testTimeout() async {
        // Set up timeout expectation
        let timeoutExpectation = expectation(description: "Request timed out")

        // Make the timeout very short
        let timeout: TimeInterval = 0.1

        do {
            // Call the hello world tool with a short timeout
            _ = try await mcpTools.helloWorld(timeout: timeout)
            XCTFail("Expected a timeout error")
        } catch {
            // Verify the error is a timeout error
            XCTAssertTrue(error is ResponseError)
            if let responseError = error as? ResponseError {
                XCTAssertEqual(responseError, ResponseError.timeout)
                timeoutExpectation.fulfill()
            }
        }

        // Wait for the timeout expectation to be fulfilled
        await waitForExpectations(timeout: 1.0)

        // Verify a message was written despite the timeout
        let messages = await mockWriter.writtenMessages
        XCTAssertEqual(messages.count, 1)
        XCTAssertTrue(messages[0].contains("helloWorld"))
    }
}
