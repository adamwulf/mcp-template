import XCTest
@testable import EasyMacMCP

final class MCPResponseReaderTests: XCTestCase {
    var responseManager: ResponseManager!
    var mockReader: MockPipeReader!
    var responseReader: MCPResponseReader!

    override func setUp() {
        super.setUp()
        responseManager = ResponseManager()
        mockReader = MockPipeReader()
        responseReader = MCPResponseReader(pipe: mockReader, responseManager: responseManager)
    }

    override func tearDown() {
        responseReader = nil
        mockReader = nil
        responseManager = nil
        super.tearDown()
    }

    func createResponseJSON(helperId: String, messageId: String, result: String) -> String {
        return """
        {"helloWorld":{"helperId":"\(helperId)","messageId":"\(messageId)","result":"\(result)"}}
        """
    }

    func testReaderDispatchesToManager() async throws {
        // Set up an expectation
        let responseExpectation = expectation(description: "Response received by manager")

        // Define helper and message IDs
        let helperId = "test-helper"
        let messageId = "test-message"

        // Add a response to the mock reader's queue
        let responseJSON = createResponseJSON(
            helperId: helperId,
            messageId: messageId,
            result: "Hello Test"
        )
        await mockReader.messagesToReturn = [responseJSON]

        // Create a task to wait for the response
        let responseTask = Task {
            do {
                let response = try await responseManager.waitForResponse(
                    helperId: helperId,
                    messageId: messageId,
                    timeout: 1.0
                )

                // Verify response content
                if case .helloWorld(let respHelperId, let respMessageId, let result) = response {
                    XCTAssertEqual(respHelperId, helperId)
                    XCTAssertEqual(respMessageId, messageId)
                    XCTAssertEqual(result, "Hello Test")
                    responseExpectation.fulfill()
                } else {
                    XCTFail("Unexpected response type")
                }

                return response
            } catch {
                XCTFail("Unexpected error: \(error)")
                throw error
            }
        }

        // Start the reader
        await responseReader.startReading()

        // Wait for the response to be processed
        await waitForExpectations(timeout: 1.0)

        // Verify pipe was opened
        let isOpened = await mockReader.isOpened
        XCTAssertTrue(isOpened)

        // Cleanup
        await responseReader.stopReading()
        responseTask.cancel()
    }

    func testMultipleResponses() async throws {
        // Set up expectations
        let responseCount = 3
        var expectations = [XCTestExpectation]()
        var tasks = [Task<Void, Error>]()

        // Queue multiple responses
        var responsesToQueue = [String]()
        for i in 0..<responseCount {
            let helperId = "test-helper"
            let messageId = "test-message-\(i)"
            let expectation = expectation(description: "Response \(i) received")
            expectations.append(expectation)

            // Add response to queue
            let responseJSON = createResponseJSON(
                helperId: helperId,
                messageId: messageId,
                result: "Hello \(i)"
            )
            responsesToQueue.append(responseJSON)

            // Create wait task
            let task = Task {
                do {
                    let response = try await responseManager.waitForResponse(
                        helperId: helperId,
                        messageId: messageId,
                        timeout: 1.0
                    )

                    // Verify response content
                    if case .helloWorld(let respHelperId, let respMessageId, let result) = response {
                        XCTAssertEqual(respHelperId, helperId)
                        XCTAssertEqual(respMessageId, messageId)
                        XCTAssertEqual(result, "Hello \(i)")
                        expectation.fulfill()
                    } else {
                        XCTFail("Unexpected response type")
                    }
                } catch {
                    XCTFail("Unexpected error: \(error)")
                }
            }

            tasks.append(task as! Task<Void, Error>)
        }

        // Set the responses to be read
        await mockReader.messagesToReturn = responsesToQueue

        // Start the reader
        await responseReader.startReading()

        // Wait for all expectations to be fulfilled
        await waitForExpectations(timeout: 1.0)

        // Cleanup
        await responseReader.stopReading()
        for task in tasks {
            task.cancel()
        }
    }

    func testInvalidResponse() async throws {
        // Setup the mock reader with invalid JSON
        await mockReader.messagesToReturn = ["Not valid JSON"]

        // Start the reader
        await responseReader.startReading()

        // Wait a moment
        try? await Task.sleep(for: .seconds(0.1))

        // The reader should still be running
        let isOpened = await mockReader.isOpened
        XCTAssertTrue(isOpened)

        // Cleanup
        await responseReader.stopReading()
    }
}
