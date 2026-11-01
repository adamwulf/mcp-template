import XCTest
import Foundation
import Logging
@testable import EasyMacMCP

/// A request line that fails to decode must cost only that line: the read loop
/// keeps serving what follows. Read errors and cancellation still end the loop.
///
/// Run with: `swift test --filter HostRequestPipeDecodeFailureTests`
final class HostRequestPipeDecodeFailureTests: XCTestCase {

    private var fifoURL: URL!

    override func setUp() async throws {
        try await super.setUp()
        let name = "easymacmcp-decode-failure-\(UUID().uuidString).fifo"
        fifoURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(name)
    }

    override func tearDown() async throws {
        if let url = fifoURL {
            try? FileManager.default.removeItem(at: url)
        }
        try await super.tearDown()
    }

    // MARK: - Decode failures on a real FIFO

    func testGarbledLineBetweenValidRequestsLosesOnlyThatLine() async throws {
        try await withRunningHostPipe { _, writer, served, logs in
            try await writer.write(Self.requestLine("m-before"))
            try await writer.write("not json\n")
            try await writer.write(Self.requestLine("m-after"))
            await assertServed(["m-before", "m-after"], by: served)

            // The buffer is drained now, so this one proves the reader went
            // back to a real read(2) rather than just working through a chunk.
            try await Task.sleep(for: .milliseconds(50))
            try await writer.write(Self.requestLine("m-later"))
            await assertServed(["m-later"], by: served)

            let messageIds = await served.messageIds
            XCTAssertEqual(messageIds, ["m-before", "m-after", "m-later"])
            XCTAssertEqual(logs.eventsAtLevel(.error).count, 1, "readRequest logs the failure once; the loop must not log it again")
        }
    }

    func testUnknownRequestCaseLosesOnlyThatLine() async throws {
        try await withRunningHostPipe { _, writer, served, _ in
            try await writer.write("{\"someFutureRequest\":{}}\n")
            try await writer.write(Self.requestLine("m-after"))
            await assertServed(["m-after"], by: served)
        }
    }

    func testInvalidUTF8LineLosesOnlyThatLine() async throws {
        try await withRunningHostPipe { _, writer, served, _ in
            try await writer.write(Data([0xFF, 0xFE, 0x0A]))
            try await writer.write(Self.requestLine("m-after"))
            await assertServed(["m-after"], by: served)
        }
    }

    /// The shape an interleaved write leaves behind: another writer's frame
    /// lands inside a multibyte character, here "…" (E2 80 A6). That costs both
    /// frames, but nothing after them.
    func testFrameSplitInsideMultibyteCharacterLosesOnlyTheInterleavedFrames() async throws {
        try await withRunningHostPipe { _, writer, served, _ in
            var interleaved = Data("{\"helperId\":\"helper-A\",\"messageId\":\"m-split".utf8)
            interleaved += [0xE2, 0x80]
            interleaved += try Self.requestLine("m-interleaved")
            interleaved += [0xA6]
            interleaved += Data("\",\"isInitialize\":false,\"isDeinitialize\":false}\n".utf8)
            try await writer.write(interleaved)
            try await writer.write(Self.requestLine("m-after"))
            await assertServed(["m-after"], by: served)

            let messageIds = await served.messageIds
            XCTAssertEqual(messageIds, ["m-after"])
        }
    }

    /// `AsyncLineSequence` looks ahead after C2 and E2 for U+0085, U+2028 and
    /// U+2029, and that lookahead swallows a newline directly after those bytes.
    /// The next frame then joins this line and is lost with it, so this asserts
    /// only that the loop survives to serve the frame after that.
    func testLeadByteBeforeNewlineDoesNotEndTheLoop() async throws {
        try await withRunningHostPipe { _, writer, served, _ in
            try await writer.write(Data([0x61, 0xE2, 0x0A]))
            try await writer.write(Self.requestLine("m-joined-to-previous-line"))
            try await writer.write(Self.requestLine("m-after"))
            await assertServed(["m-after"], by: served)
        }
    }

    /// `JSONEncoder` leaves U+2028 raw and `AsyncLineSequence` treats it as a
    /// line ending, so one valid request arrives as two undecodable lines. No
    /// concurrent writer is needed, only text containing the character.
    func testRequestContainingUnicodeLineSeparatorDoesNotEndTheLoop() async throws {
        try await withRunningHostPipe { _, writer, served, _ in
            try await writer.write(Self.requestLine("m-with\u{2028}separator"))
            try await writer.write(Self.requestLine("m-after"))
            await assertServed(["m-after"], by: served)
        }
    }

    // MARK: - Terminal paths

    func testReadErrorEndsLoopWithoutSpinning() async throws {
        let logs = LogRecorder()
        let pipe = ScriptedPipeReader([.fail(SimulatedReadError())])
        let hostPipe = HostRequestPipe<DispatchTestRequest>(readPipe: pipe, logger: Self.logger(recordingTo: logs))

        await hostPipe.startReading { _ in }

        await assertLoopEnded(hostPipe, pipe, afterReads: 1)
        XCTAssertEqual(logs.eventsAtLevel(.error).count, 1, "the read error should be logged once")
        await hostPipe.close()
    }

    func testReadErrorAfterDecodeFailureEndsLoop() async throws {
        let logs = LogRecorder()
        let pipe = ScriptedPipeReader([.line("not json"), .fail(SimulatedReadError())])
        let hostPipe = HostRequestPipe<DispatchTestRequest>(readPipe: pipe, logger: Self.logger(recordingTo: logs))

        await hostPipe.startReading { _ in }

        await assertLoopEnded(hostPipe, pipe, afterReads: 2)
        XCTAssertEqual(logs.eventsAtLevel(.error).count, 2, "one log for the decode failure, one for the read error")
        await hostPipe.close()
    }

    func testCancellationErrorEndsLoopWithoutErrorLog() async throws {
        let logs = LogRecorder()
        let pipe = ScriptedPipeReader([.fail(CancellationError())])
        let hostPipe = HostRequestPipe<DispatchTestRequest>(readPipe: pipe, logger: Self.logger(recordingTo: logs))

        await hostPipe.startReading { _ in }

        await assertLoopEnded(hostPipe, pipe, afterReads: 1)
        XCTAssertTrue(logs.eventsAtLevel(.error).isEmpty, "cancellation is a normal exit, not an error")
        await hostPipe.close()
    }

    // MARK: - Shutdown after a decode failure

    func testCloseAfterDecodeFailureReturnsPromptly() async throws {
        try await withRunningHostPipe { hostPipe, writer, served, logs in
            try await writer.write("not json\n")
            try await writer.write(Self.requestLine("m-after"))
            await assertServed(["m-after"], by: served)

            // Let the reader park in read(2) again, with this writer attached.
            try await Task.sleep(for: .milliseconds(100))

            let elapsed = await closeMeasuringElapsed(hostPipe) {
                try? await writer.write("rescue\n")
            }

            XCTAssertLessThan(elapsed, .seconds(1), "close() should stay prompt after the loop has survived a decode failure")
            XCTAssertEqual(logs.eventsAtLevel(.error).count, 1, "shutdown must add no error logs to the one for the garbled line")
        }
    }

    /// A real `ReadPipe` never yields the wake sentinel as a line, because
    /// `AsyncLineSequence` drops empty lines and cancellation surfaces as
    /// `CancellationError`. The protocol doesn't promise that, so this covers a
    /// `PipeReadable` whose wake does yield one: that decode failure arrives
    /// during shutdown, and reading again would park forever.
    func testDecodeFailureDuringCancellationExitsInsteadOfReadingAgain() async throws {
        let pipe = ScriptedPipeReader([.line("not json")])
        let hostPipe = HostRequestPipe<DispatchTestRequest>(readPipe: pipe)

        await hostPipe.startReading { _ in }

        // A second read means the loop survived the garbled line and has parked.
        let parked = await eventually { await pipe.readCount == 2 }
        XCTAssertTrue(parked, "the loop should read again after the garbled line")

        let elapsed = await closeMeasuringElapsed(hostPipe) {
            await pipe.release()
        }

        XCTAssertLessThan(elapsed, .seconds(1), "close() must not wait on a read started after cancellation")
        let finalReadCount = await pipe.readCount
        XCTAssertEqual(finalReadCount, 2, "the wake's decode failure must end the loop, not start another read")
    }

    // MARK: - Helpers

    /// Starts a reader on a real FIFO with a logger and a writer attached, runs
    /// `body`, then closes. `close()` is safe to call again if `body` already did.
    private func withRunningHostPipe(
        body: (_ hostPipe: HostRequestPipe<DispatchTestRequest>, _ writer: WritePipe, _ served: ServedRequests, _ logs: LogRecorder) async throws -> Void
    ) async throws {
        let logs = LogRecorder()
        let served = ServedRequests()
        let readPipe = try ReadPipe(url: fifoURL)
        let hostPipe = HostRequestPipe<DispatchTestRequest>(readPipe: readPipe, logger: Self.logger(recordingTo: logs))
        try await hostPipe.open()

        let writer = try WritePipe(url: fifoURL)
        try await writer.open()

        await hostPipe.startReading { request in
            await served.record(request.messageId)
        }

        do {
            try await body(hostPipe, writer, served, logs)
        } catch {
            await hostPipe.close()
            await writer.close()
            throw error
        }
        await hostPipe.close()
        await writer.close()
    }

    private static func requestLine(_ messageId: String) throws -> Data {
        var line = try JSONEncoder().encode(DispatchTestRequest(helperId: "helper-A", messageId: messageId))
        line.append(0x0A)
        return line
    }

    private static func logger(recordingTo recorder: LogRecorder) -> Logger {
        Logger(label: "test.host-request-decode-failure") { _ in
            RecordingLogHandler(recorder: recorder)
        }
    }

    private func eventually(timeout: Duration = .seconds(2), _ condition: () async -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if await condition() { return true }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return await condition()
    }

    private func assertServed(
        _ messageIds: Set<String>,
        by served: ServedRequests,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        let arrived = await eventually { await served.messageIds.isSuperset(of: messageIds) }
        let actual = await served.messageIds
        XCTAssertTrue(arrived, "expected \(messageIds) to be served; served \(actual)", file: file, line: line)
    }

    /// `isReading` is private, so observe it: reads stop at `reads`, and a new
    /// `startReading`, which is a no-op while `isReading` is true, reads again.
    /// The extra read parks on the exhausted script until `close()` wakes it.
    private func assertLoopEnded(
        _ hostPipe: HostRequestPipe<DispatchTestRequest>,
        _ pipe: ScriptedPipeReader,
        afterReads reads: Int,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        _ = await eventually { await pipe.readCount >= reads }
        try? await Task.sleep(for: .milliseconds(100))
        let settled = await pipe.readCount
        XCTAssertEqual(settled, reads, "the loop should stop reading after the terminal error", file: file, line: line)

        await hostPipe.startReading { _ in }
        let restarted = await eventually { await pipe.readCount > settled }
        XCTAssertTrue(restarted, "isReading should be false once the loop has ended", file: file, line: line)
    }

    /// Runs `rescue` if `close()` is still blocked after 2s, so a regression
    /// fails the elapsed-time assertion rather than hanging the suite.
    private func closeMeasuringElapsed(
        _ hostPipe: HostRequestPipe<DispatchTestRequest>,
        rescue: @escaping @Sendable () async -> Void
    ) async -> ContinuousClock.Duration {
        let rescueTask = Task {
            do {
                try await Task.sleep(for: .seconds(2))
            } catch {
                return
            }
            await rescue()
        }
        let startedAt = ContinuousClock.now
        await hostPipe.close()
        let elapsed = ContinuousClock.now - startedAt
        rescueTask.cancel()
        return elapsed
    }
}

private actor ServedRequests {
    private(set) var messageIds: Set<String> = []

    func record(_ messageId: String) {
        messageIds.insert(messageId)
    }
}

private struct SimulatedReadError: Error {}

/// Plays back `steps`, then parks like a blocking read until woken.
private actor ScriptedPipeReader: PipeReadable {
    enum Step: Sendable {
        case line(String)
        case fail(any Error)
    }

    private var steps: [Step]
    private var parked: CheckedContinuation<String?, any Error>?
    private var released = false
    private(set) var readCount = 0

    init(_ steps: [Step]) {
        self.steps = steps
    }

    func open() async throws {}

    func close() async {}

    func readLine() async throws -> String? {
        readCount += 1
        if !steps.isEmpty {
            switch steps.removeFirst() {
            case .line(let line):
                return line
            case .fail(let error):
                throw error
            }
        }
        if released {
            throw SimulatedReadError()
        }
        return try await withCheckedThrowingContinuation { parked = $0 }
    }

    /// Wakes a parked read with an empty line, which fails to decode.
    func signalReaderWake() async {
        parked?.resume(returning: "")
        parked = nil
    }

    /// Test rescue: ends a parked read, and any later one, with a read error.
    func release() {
        released = true
        parked?.resume(throwing: SimulatedReadError())
        parked = nil
    }
}
