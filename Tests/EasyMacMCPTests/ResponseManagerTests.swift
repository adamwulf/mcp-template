import XCTest
@testable import EasyMacMCP

final class ResponseManagerTests: XCTestCase {
    var responseManager: ResponseManager!

    override func setUp() {
        super.setUp()
        responseManager = ResponseManager()
    }

    override func tearDown() {
        responseManager = nil
        super.tearDown()
    }

    func testHandleResponse() async throws {
        // Create a task that waits for a response
        let helperId = "test-helper"
        let messageId = "test-message"

        // Setup an expectation for the response
        let responseExpectation = expectation(description: "Response received")

        // Create a task that waits for a response
        let responseTask = Task {
            do {
                let response = try await responseManager.waitForResponse(helperId: helperId, messageId: messageId)

                // Check that we got the correct response
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

        // Wait a bit then send a response
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            Task {
                // Send a response that matches the request
                let response = MCPResponse.helloWorld(
                    helperId: helperId,
                    messageId: messageId,
                    result: "Hello Test"
                )
                await self.responseManager.handleResponse(response)
            }
        }

        // Wait for the response expectation to be fulfilled
        await waitForExpectations(timeout: 1.0)

        // Cancel the task
        responseTask.cancel()
    }

    func testTimeout() async {
        // Setup an expectation for the timeout
        let timeoutExpectation = expectation(description: "Request timed out")

        // Use a very short timeout for testing
        let timeout: TimeInterval = 0.1

        // Create a task that waits for a response that will never come
        let task = Task {
            do {
                _ = try await responseManager.waitForResponse(
                    helperId: "test-helper",
                    messageId: "test-message",
                    timeout: timeout
                )
                XCTFail("Expected a timeout error")
            } catch {
                XCTAssertTrue(error is ResponseError)
                if let responseError = error as? ResponseError {
                    XCTAssertEqual(responseError, ResponseError.timeout)
                    timeoutExpectation.fulfill()
                } else {
                    XCTFail("Unexpected error type: \(error)")
                }
            }
        }

        // Wait for the timeout expectation to be fulfilled
        await waitForExpectations(timeout: 1.0)

        // Cancel the task
        task.cancel()
    }

    func testCancelRequest() async {
        // Setup an expectation for the cancellation
        let cancelExpectation = expectation(description: "Request cancelled")

        let helperId = "test-helper"
        let messageId = "test-message"

        // Create a task that waits for a response
        let task = Task {
            do {
                _ = try await responseManager.waitForResponse(
                    helperId: helperId,
                    messageId: messageId,
                    timeout: 10 // Long timeout
                )
                XCTFail("Expected a cancellation error")
            } catch {
                XCTAssertTrue(error is ResponseError)
                if let responseError = error as? ResponseError {
                    XCTAssertEqual(responseError, ResponseError.requestCancelled)
                    cancelExpectation.fulfill()
                } else {
                    XCTFail("Unexpected error type: \(error)")
                }
            }
        }

        // Wait a bit then cancel the request
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            Task {
                await self.responseManager.cancelRequest(helperId: helperId, messageId: messageId)
            }
        }

        // Wait for the cancellation expectation to be fulfilled
        await waitForExpectations(timeout: 1.0)

        // Cancel the task
        task.cancel()
    }

    func testMultipleRequests() async {
        let responseCount = 5
        var expectations = [XCTestExpectation]()
        var tasks = [Task<Void, Error>]()

        // Create multiple concurrent requests
        for i in 0..<responseCount {
            let helperId = "test-helper"
            let messageId = "test-message-\(i)"
            let expectation = expectation(description: "Response \(i) received")
            expectations.append(expectation)

            // Create a task for each request
            let task = Task {
                do {
                    let response = try await responseManager.waitForResponse(
                        helperId: helperId,
                        messageId: messageId,
                        timeout: 1.0
                    )

                    // Check that we got the correct response
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

        // Wait a bit then send responses
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            Task {
                // Send responses in reverse order to ensure correct matching
                for i in stride(from: responseCount - 1, through: 0, by: -1) {
                    let helperId = "test-helper"
                    let messageId = "test-message-\(i)"
                    let response = MCPResponse.helloWorld(
                        helperId: helperId,
                        messageId: messageId,
                        result: "Hello \(i)"
                    )
                    await self.responseManager.handleResponse(response)

                    // Add a small delay between responses
                    try? await Task.sleep(for: .nanoseconds(10_000_000))
                }
            }
        }

        // Wait for all expectations to be fulfilled
        await waitForExpectations(timeout: 1.0)

        // Cancel all tasks
        for task in tasks {
            task.cancel()
        }
    }
}
