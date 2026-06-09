import XCTest
import Foundation
import Logging
import MCP
@testable import EasyMacMCP

/// Minimal `MCPResponseProtocol` conformance for tests that exercise the
/// `HelperResponsePipe.startReading(...)` generic API. The reader Task
/// will never actually decode a real response in these tests — the pipe
/// stays silent except for the sentinel byte `signalReaderWake()` injects
/// during shutdown.
private struct StubResponse: MCPResponseProtocol {
    let helperId: String
    let messageId: String

    func asCallToolResult() -> MCP.CallTool.Result {
        MCP.CallTool.Result(content: [], isError: false)
    }

    static func makeListToolsResponse(helperId: String, messageId: String, tools: [ToolMetadata]) -> StubResponse {
        StubResponse(helperId: helperId, messageId: messageId)
    }

    func asListToolsResult() -> MCP.ListTools.Result? { nil }
}

/// Minimal `MCPRequestProtocol` conformance for tests that exercise the
/// `HostRequestPipe.startReading(...)` generic API. The reader Task will
/// never actually decode a real request — the pipe stays silent except
/// for the sentinel byte that `signalReaderWake()` injects during
/// shutdown.
private struct StubRequest: MCPRequestProtocol {
    let helperId: String
    let messageId: String
    var isInitialize: Bool { false }
    var isDeinitialize: Bool { false }

    static func create(helperId: String, messageId: String, parameters: MCP.CallTool.Parameters) throws -> StubRequest {
        StubRequest(helperId: helperId, messageId: messageId)
    }

    static func makeListToolsRequest(helperId: String, messageId: String) -> StubRequest {
        StubRequest(helperId: helperId, messageId: messageId)
    }
}

/// MCPRequestProtocol conformance used by the dispatch-ordering tests. Unlike
/// `StubRequest`, this struct's `isInitialize`/`isDeinitialize` flags are
/// stored properties so a test can construct a mix of lifecycle and
/// non-lifecycle requests, write them to the FIFO as JSON, and let
/// `HostRequestPipe.readRequest()` decode them back on the host side.
private struct DispatchTestRequest: MCPRequestProtocol, Codable {
    let helperId: String
    let messageId: String
    let isInitialize: Bool
    let isDeinitialize: Bool

    init(helperId: String, messageId: String, isInitialize: Bool = false, isDeinitialize: Bool = false) {
        self.helperId = helperId
        self.messageId = messageId
        self.isInitialize = isInitialize
        self.isDeinitialize = isDeinitialize
    }

    static func create(helperId: String, messageId: String, parameters: MCP.CallTool.Parameters) throws -> DispatchTestRequest {
        DispatchTestRequest(helperId: helperId, messageId: messageId)
    }

    static func makeListToolsRequest(helperId: String, messageId: String) -> DispatchTestRequest {
        DispatchTestRequest(helperId: helperId, messageId: messageId)
    }
}

/// Standalone repro for the suspected `ReadPipe.readLine()` over-read bug.
///
/// Hypothesis (see `/tmp/easymacmcp-readline-bug-notes.md`): each call to
/// `readLine()` builds a fresh `FileHandle.AsyncBytes` iterator. The iterator
/// reads a chunk (~4 KB) from the FD into its own buffer, returns the first
/// line, and is then dropped — discarding any additional lines that were
/// already in that chunk. The next `readLine()` finds the kernel pipe drained
/// and returns `nil` (or, with blocking-mode FDs, blocks forever waiting for
/// more bytes).
///
/// These tests write multiple lines to a FIFO before the reader's first
/// `readLine()`, then ask for them back. The tests bound execution time by
/// closing the writer pipe after a deadline — when the writer's FD closes,
/// any in-flight blocking read on the reader gets EOF (returns `nil`) and the
/// actor unblocks, so assertions can run.
///
/// Run with: `swift test --filter ReadPipeOverReadReproTests`
final class ReadPipeOverReadReproTests: XCTestCase {

    private var fifoURL: URL!

    override func setUp() async throws {
        try await super.setUp()
        let name = "easymacmcp-repro-\(UUID().uuidString).fifo"
        fifoURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(name)
        try? FileManager.default.removeItem(at: fifoURL)
    }

    override func tearDown() async throws {
        if let url = fifoURL {
            try? FileManager.default.removeItem(at: url)
        }
        try await super.tearDown()
    }

    /// Two writes BEFORE first read — the precise trigger from the bug notes.
    /// Expected (post-fix): "hello", "world". Observed (with bug): "hello",
    /// then nil/blocked because AsyncBytes' chunk consumed both lines but
    /// only one survived.
    func testTwoLinesQueuedBeforeFirstRead() async throws {
        let reader = try ReadPipe(url: fifoURL)
        let writer = try WritePipe(url: fifoURL)

        // Reader must open first — opening a FIFO O_WRONLY|O_NONBLOCK fails
        // with ENXIO if no reader is attached.
        try await reader.open()
        try await writer.open()

        try await writer.write("hello\n")
        try await writer.write("world\n")

        let results = await readLines(from: reader, count: 2, deadlineSeconds: 3, closingWriter: writer)

        XCTAssertEqual(results.first ?? nil, "hello", "first readLine should return the first queued line")
        XCTAssertEqual(results.dropFirst().first ?? nil, "world", "second readLine should return the second queued line; nil here confirms the over-read bug")

        await reader.close()
    }

    /// Burst of 10 writes, then 10 reads. Even more aggressive than the
    /// 2-line case — guarantees the chunk read by AsyncBytes contains
    /// multiple lines.
    func testBurstThenRead() async throws {
        let reader = try ReadPipe(url: fifoURL)
        let writer = try WritePipe(url: fifoURL)

        try await reader.open()
        try await writer.open()

        let lines = (0..<10).map { "line-\($0)" }
        for line in lines {
            try await writer.write(line + "\n")
        }

        let results = await readLines(from: reader, count: lines.count, deadlineSeconds: 5, closingWriter: writer)

        let received = results.compactMap { $0 }
        XCTAssertEqual(received, lines, "all 10 lines should come back in order; missing tail entries indicate over-read")

        await reader.close()
    }

    /// Sanity check: one write, one read. This exercises the original
    /// "request rate slower than read loop" path that hid the bug. Should
    /// pass against both the buggy and fixed implementations — guards
    /// against the fix accidentally breaking the simple case.
    func testSingleLineRoundTrip() async throws {
        let reader = try ReadPipe(url: fifoURL)
        let writer = try WritePipe(url: fifoURL)

        try await reader.open()
        try await writer.open()

        try await writer.write("solo\n")

        let results = await readLines(from: reader, count: 1, deadlineSeconds: 3, closingWriter: writer)

        XCTAssertEqual(results.first ?? nil, "solo")

        await reader.close()
    }

    /// EOF + reopen: open writer, write a line, close writer (causing EOF
    /// on the reader's next call after the buffered line). Open writer
    /// again, write another line. Reader's subsequent `readLine()` should
    /// return the new line — this validates the iterator-rebuild-on-nil
    /// branch that keeps `startReading` consumers working when a helper
    /// disconnects and reconnects.
    func testEOFThenReopenReturnsNewLine() async throws {
        let reader = try ReadPipe(url: fifoURL)
        try await reader.open()

        // First writer session: write one line, then close.
        do {
            let writer1 = try WritePipe(url: fifoURL)
            try await writer1.open()
            try await writer1.write("first\n")
            await writer1.close()
        }

        let firstResults = await readLines(from: reader, count: 1, deadlineSeconds: 3, closingWriter: nil)
        XCTAssertEqual(firstResults.first ?? nil, "first", "should receive the line written by the first writer session")

        // Second writer session — separate process-side close/reopen of the
        // writer FD. The reader must rebuild its iterator after EOF and
        // pick up the new line.
        let writer2 = try WritePipe(url: fifoURL)
        try await writer2.open()
        try await writer2.write("second\n")

        let secondResults = await readLines(from: reader, count: 1, deadlineSeconds: 3, closingWriter: writer2)
        XCTAssertEqual(secondResults.first ?? nil, "second", "after a writer disconnects and a new one attaches, readLine() should resume — nil here means the iterator wasn't rebuilt on EOF")

        await reader.close()
    }

    /// Two interleaved write bursts with a read drain in between. Verifies
    /// the iterator's chunk buffer is correctly preserved across calls and
    /// also handles fresh data arriving after the buffer drains naturally.
    func testInterleavedWriteAndReadBursts() async throws {
        let reader = try ReadPipe(url: fifoURL)
        let writer = try WritePipe(url: fifoURL)

        try await reader.open()
        try await writer.open()

        // First burst: 3 lines back-to-back.
        for line in ["a-1", "a-2", "a-3"] {
            try await writer.write(line + "\n")
        }
        let first = await readLines(from: reader, count: 3, deadlineSeconds: 3, closingWriter: nil)
        XCTAssertEqual(first.compactMap { $0 }, ["a-1", "a-2", "a-3"])

        // Second burst after the first drain.
        for line in ["b-1", "b-2"] {
            try await writer.write(line + "\n")
        }
        let second = await readLines(from: reader, count: 2, deadlineSeconds: 3, closingWriter: writer)
        XCTAssertEqual(second.compactMap { $0 }, ["b-1", "b-2"])

        await reader.close()
    }

    /// All-external-writers-detach gap: open ReadPipe, attach an external
    /// WritePipe, write+read a line, close the WritePipe so zero external
    /// writers remain. Then a separate Task opens a NEW WritePipe after a
    /// brief delay and writes a second line. The reader's `readLine()` must
    /// block across the writer-detach gap and return the second line.
    ///
    /// Without the self-pipe keepalive, `AsyncBytes` sees the kernel writer
    /// count drop to zero and ends the sequence with EOF — `readLine()`
    /// returns nil immediately and `HostRequestPipe.startReading` spins.
    /// With the keepalive in place, ReadPipe holds its own writer FD so the
    /// kernel writer count stays positive, `read(2)` blocks, and the second
    /// line arrives normally.
    func testReadLineBlocksWhenAllExternalWritersDetach() async throws {
        let reader = try ReadPipe(url: fifoURL)
        try await reader.open()

        let writer1 = try WritePipe(url: fifoURL)
        try await writer1.open()
        try await writer1.write("first\n")

        let firstLine = try await reader.readLine()
        XCTAssertEqual(firstLine, "first")

        // Detach the only external writer. Without the keepalive, the next
        // readLine() would see EOF and return nil immediately.
        await writer1.close()

        // In a background task, sleep briefly then attach a NEW writer and
        // send the second line. The reader must be blocked on readLine()
        // across this gap.
        let url = fifoURL!
        let writerTask = Task {
            try await Task.sleep(for: .milliseconds(50))
            let writer2 = try WritePipe(url: url)
            try await writer2.open()
            try await writer2.write("second\n")
            return writer2
        }

        // Bound the read with a deadline so a regression doesn't hang the
        // test indefinitely. If the keepalive is missing, readLine() returns
        // nil quickly (well under the deadline) and the assertion fails.
        let secondLine: String? = await withTaskGroup(of: String?.self) { group in
            group.addTask {
                return try? await reader.readLine()
            }
            group.addTask {
                // Use throwing sleep so group.cancelAll() on the happy path
                // propagates cancellation here and skips the unnecessary
                // reader.close() (the trailing close at the end of the test
                // already handles cleanup).
                do {
                    try await Task.sleep(for: .seconds(3))
                } catch {
                    return nil
                }
                // Deadline genuinely fired: close the reader to unblock any
                // hung readLine() so the test fails fast on regression.
                await reader.close()
                return nil
            }
            let result = await group.next() ?? nil
            group.cancelAll()
            return result
        }

        XCTAssertEqual(secondLine, "second", "readLine() should have blocked across the writer-detach gap and returned the line from the reattached writer; nil here means the keepalive writer FD is missing or got closed")

        let writer2 = try await writerTask.value
        await writer2.close()
        await reader.close()
    }

    /// Close while a reader is mid-`read()` and an *external* writer is
    /// still attached — the production deadlock case, now fixed by the
    /// cancel → `signalReaderWake()` → await → `close()` shutdown sequence.
    ///
    /// The CLI hang from the field looked like this: the helper process has a
    /// ReadPipe open on the response FIFO; the host app has its own
    /// WritePipe open on the same FIFO (the writer side of the response
    /// channel). When the CLI tears down, it calls `ReadPipe.close()` while
    /// the reader Task is parked in `read(2)`.
    ///
    /// Root cause: `FileHandle.AsyncBytes` is backed by `dispatch_io`, which
    /// owns the FD for the lifetime of its read. Calling `fileHandle.close()`
    /// from another thread while a dispatch_io worker is parked on a kqueue
    /// `EVFILT_READ` filter does NOT deliver EBADF/EINTR to the worker; the
    /// closer blocks waiting for dispatch_io to release the FD. With an
    /// external writer attached, the FIFO never sees EOF, so the kqueue
    /// filter never fires and dispatch_io never releases. Deadlock.
    ///
    /// The fix: consumers MUST cancel and await their reader Task before
    /// calling `close()`. The required sequence is:
    ///
    ///   1. cancel the reader Task
    ///   2. `signalReaderWake()` to deliver a sentinel byte through the
    ///      keepalive — wakes the dispatch_io read so the iterator can yield
    ///   3. `await readerTask.value` — gives dispatch_io scheduler time to
    ///      drain (this is the key step — back-to-back write+close on the
    ///      same actor leaves no time for dispatch_io to run)
    ///   4. `close()` — uncontended, returns immediately
    ///
    /// This test pins down the contract.
    func testProperShutdownSequenceUnblocksCleanlyWithExternalWriterAttached() async throws {
        let reader = try ReadPipe(url: fifoURL)
        try await reader.open()

        // External writer attached, but produces no data. This mirrors the
        // host-side WritePipe staying open during CLI teardown.
        let externalWriter = try WritePipe(url: fifoURL)
        try await externalWriter.open()

        // Start a reader Task that will park in read(). With an external
        // writer attached, EOF is impossible — the only way out is the
        // sentinel byte we deliver in step 2 below.
        let readerTask = Task<String?, Never> {
            return try? await reader.readLine()
        }

        // Give the reader Task a moment to actually reach the read() syscall.
        try await Task.sleep(for: .milliseconds(100))

        // Race the full shutdown sequence against a deadline. With the fix,
        // the whole sequence completes in well under a second. Without it,
        // the close() at the end would block until either the reader Task is
        // woken or the dispatch_io grace timer fires; the test's rescue
        // write through the external writer rescues that case so a
        // regression doesn't hang the suite.
        let shutdownStartedAt = ContinuousClock.now
        let elapsedOnComplete: ContinuousClock.Duration = await withTaskGroup(of: ContinuousClock.Duration?.self) { group in
            group.addTask {
                // The contract — cancel → wake → await → close.
                readerTask.cancel()
                await reader.signalReaderWake()
                _ = await readerTask.value
                await reader.close()
                return ContinuousClock.now - shutdownStartedAt
            }
            group.addTask {
                // Deadline: 2s. If shutdown hasn't completed by then, rescue
                // by writing data through the external writer so any blocked
                // read returns and the suite doesn't hang. On the happy path
                // we cancel this task before it ever runs the write.
                do {
                    try await Task.sleep(for: .seconds(2))
                } catch {
                    return nil
                }
                try? await externalWriter.write("rescue\n")
                return nil
            }
            var result: ContinuousClock.Duration = .seconds(0)
            for await item in group {
                if let item = item {
                    result = item
                    break
                }
            }
            group.cancelAll()
            await group.waitForAll()
            return result
        }

        XCTAssertLessThan(elapsedOnComplete, .seconds(1), "The full cancel → signalReaderWake → await → close shutdown sequence should complete in well under a second with an external writer attached. Taking >=1s here means the new shutdown contract isn't unblocking the dispatch_io reader — likely a regression in `signalReaderWake()`, the reader Task await, or `close()`'s post-await invariants.")

        await externalWriter.close()
    }

    /// Close with no external writer attached at all.
    ///
    /// Realistic scenario: the helper opens its response pipe before the
    /// host app has wired up its writer (or the host has already detached
    /// and quit), then the helper shuts down. The only writer on the FIFO
    /// is ReadPipe's own keepalive FD.
    ///
    /// Without an external writer, the sentinel write in close() could
    /// theoretically SIGPIPE if our keepalive FD were the only writer AND
    /// it were somehow torn down before the write — this test guards
    /// against a regression where the keepalive close-order or signal
    /// disposition gets disturbed. With the current fix, the write goes
    /// out, the keepalive is the sole reader-of-its-own-write (nobody
    /// drains), then the FD is closed and torn down cleanly.
    func testCloseWithNoExternalWriterAttached() async throws {
        let reader = try ReadPipe(url: fifoURL)
        try await reader.open()

        // No external writer at all. close() should return promptly.
        let closeStartedAt = ContinuousClock.now
        await reader.close()
        let elapsed = ContinuousClock.now - closeStartedAt

        XCTAssertLessThan(elapsed, .seconds(1), "close() should return in well under a second with no external writer attached")
    }

    /// Concurrent close() calls from two Tasks.
    ///
    /// Realistic scenario: the helper has two shutdown paths that both end
    /// up calling close() on the same pipe — e.g. an explicit cleanup
    /// closure in sendRequest() and a defer/finalizer somewhere else. Actor
    /// reentrancy serializes them, but the second call must not crash
    /// (double-close on the FD), SIGPIPE, or hang.
    ///
    /// Both calls should complete quickly; the second is a no-op since
    /// keepaliveWriterFD and fileHandle are both nil by then.
    func testConcurrentCloseCalls() async throws {
        let reader = try ReadPipe(url: fifoURL)
        try await reader.open()

        let closeStartedAt = ContinuousClock.now
        async let close1: Void = reader.close()
        async let close2: Void = reader.close()
        _ = await (close1, close2)
        let elapsed = ContinuousClock.now - closeStartedAt

        XCTAssertLessThan(elapsed, .seconds(1), "two concurrent close() calls should both return promptly; >=1s suggests a hang or busy-loop")

        // A third close() after both have returned should still be a clean
        // no-op. Catches a regression where state isn't properly nil-ed.
        await reader.close()
    }

    /// signalReaderWake() on a pipe that was never opened.
    ///
    /// Realistic scenario: a helper constructs a ReadPipe, then errors out
    /// during initialization before calling `open()`. The cleanup path
    /// still calls `signalReaderWake()` (e.g. as part of a generic
    /// teardown sequence). This must be a clean no-op — no crash, no
    /// SIGPIPE, no write to an invalid FD.
    func testSignalReaderWakeOnNeverOpenedPipe() async throws {
        let reader = try ReadPipe(url: fifoURL)
        // Do NOT call open(). keepaliveWriterFD is nil.
        await reader.signalReaderWake()
        // If we got here without crashing, the no-op guard works.
    }

    /// signalReaderWake() after close() is also a no-op.
    ///
    /// Realistic scenario: a cleanup path calls close() and then a stray
    /// shutdown signal (or a defer block) calls signalReaderWake() again.
    /// The keepalive FD is already nil, so the call returns instantly
    /// without touching any FD.
    func testSignalReaderWakeAfterClose() async throws {
        let reader = try ReadPipe(url: fifoURL)
        try await reader.open()
        await reader.close()
        // After close, keepaliveWriterFD is nil — this must no-op.
        await reader.signalReaderWake()
    }

    /// Double stopReading() on HelperResponsePipe.
    ///
    /// Realistic scenario: a consumer calls stopReading() explicitly, and
    /// a separate cleanup path (e.g. close(), or a defer block in an
    /// error handler) also calls stopReading() / close(). The second call
    /// must be a clean no-op — the readingTask reference was nil-ed by
    /// the first call, so cancel/await is skipped; signalReaderWake will
    /// still run but writes a sentinel into a closed pipe is harmless
    /// (or into an open one is one stray empty line, which the decode
    /// loop logs and discards). No crash, no hang.
    func testDoubleStopReadingIsSafe() async throws {
        let helperPipe = try HelperResponsePipe(url: fifoURL)
        try await helperPipe.open()

        await helperPipe.startReading { (_: StubResponse) in }
        try await Task.sleep(for: .milliseconds(50))

        // First stopReading drives the full sequence.
        await helperPipe.stopReading()
        // Second stopReading must be safe.
        await helperPipe.stopReading()

        await helperPipe.close()
    }

    /// HelperResponsePipe.close() while its internal reader Task is parked
    /// in readLine() — the production code path.
    ///
    /// `HelperResponsePipe.startReading(...)` owns an internal Task that
    /// loops on `readPipe.readLine()` and dispatches decoded responses to a
    /// handler. This is how ResponseManager consumes responses in production
    /// (see ResponseManager.swift:52-78). When the helper shuts down,
    /// `close()` must cancel that internal Task, signal the reader to wake,
    /// await the Task's exit, and then close the underlying ReadPipe.
    ///
    /// Test setup mirrors production: start reading via `startReading(...)`,
    /// attach an external writer that never produces data (stands in for the
    /// host-side writer staying open during shutdown), then call close().
    /// Expect prompt return.
    func testHelperResponsePipeCloseUnblocksInternalReaderTask() async throws {
        let helperPipe = try HelperResponsePipe(url: fifoURL)
        try await helperPipe.open()

        let externalWriter = try WritePipe(url: fifoURL)
        try await externalWriter.open()

        // Start the internal reader loop. The handler closure type matches
        // the generic constraint on `startReading`.
        await helperPipe.startReading { (_: StubResponse) in }

        // Give the internal Task a moment to actually reach the read() syscall.
        try await Task.sleep(for: .milliseconds(100))

        let closeStartedAt = ContinuousClock.now
        let elapsedOnComplete: ContinuousClock.Duration = await withTaskGroup(of: ContinuousClock.Duration?.self) { group in
            group.addTask {
                await helperPipe.close()
                return ContinuousClock.now - closeStartedAt
            }
            group.addTask {
                do {
                    try await Task.sleep(for: .seconds(2))
                } catch {
                    return nil
                }
                try? await externalWriter.write("rescue\n")
                return nil
            }
            var result: ContinuousClock.Duration = .seconds(0)
            for await item in group {
                if let item = item {
                    result = item
                    break
                }
            }
            group.cancelAll()
            await group.waitForAll()
            return result
        }

        XCTAssertLessThan(elapsedOnComplete, .seconds(1), "HelperResponsePipe.close() should return promptly while its internal reader Task is parked in readLine() with an external writer attached; >=1s means the cancel → signalReaderWake → await sequence inside close()/stopReading() isn't unblocking the dispatch_io reader")

        await externalWriter.close()
    }

    /// ResponseManager.stopReading() while its internal reader Task is
    /// parked in readLine() — the exact production code path from the
    /// original CLI-hang thread dump.
    ///
    /// ResponseManager wraps HelperResponsePipe, owns its own reader Task
    /// (`responseReaderTask`), and calls `responsePipe.readLine()` in a
    /// loop. When the helper shuts down (the thread dump's
    /// `ResponseManager.stopReading()` frame), the manager must cancel
    /// the reader Task, signal the wake, await the Task to exit, and
    /// then close the pipe. This test pins down the production sequence
    /// end-to-end.
    func testResponseManagerStopReadingUnblocksWithExternalWriterAttached() async throws {
        let helperPipe = try HelperResponsePipe(url: fifoURL)
        let manager = ResponseManager<StubResponse>(responsePipe: helperPipe)
        try await manager.startReading()

        // External writer attached, but produces no data — mirrors the
        // host-side WritePipe staying open during CLI teardown.
        let externalWriter = try WritePipe(url: fifoURL)
        try await externalWriter.open()

        // Give the manager's internal Task a moment to park in read().
        try await Task.sleep(for: .milliseconds(100))

        let stopStartedAt = ContinuousClock.now
        let elapsedOnComplete: ContinuousClock.Duration = await withTaskGroup(of: ContinuousClock.Duration?.self) { group in
            group.addTask {
                await manager.stopReading()
                return ContinuousClock.now - stopStartedAt
            }
            group.addTask {
                do {
                    try await Task.sleep(for: .seconds(2))
                } catch {
                    return nil
                }
                try? await externalWriter.write("rescue\n")
                return nil
            }
            var result: ContinuousClock.Duration = .seconds(0)
            for await item in group {
                if let item = item {
                    result = item
                    break
                }
            }
            group.cancelAll()
            await group.waitForAll()
            return result
        }

        XCTAssertLessThan(elapsedOnComplete, .seconds(1), "ResponseManager.stopReading() should return promptly while its internal reader Task is parked in readLine() with an external writer attached. This is the exact CLI-hang path from the original report; >=1s means a regression in the shutdown sequence.")

        await externalWriter.close()
    }

    /// HostRequestPipe.close() while its internal reader Task is parked
    /// in readLine() — symmetric to the HelperResponsePipe case but on
    /// the request side. The host app uses HostRequestPipe to receive
    /// incoming requests from helpers; same shutdown contract applies.
    func testHostRequestPipeCloseUnblocksInternalReaderTask() async throws {
        let readPipe = try ReadPipe(url: fifoURL)
        let hostPipe = HostRequestPipe<StubRequest>(readPipe: readPipe)
        try await hostPipe.open()

        let externalWriter = try WritePipe(url: fifoURL)
        try await externalWriter.open()

        // Start the internal reader loop with a no-op handler.
        await hostPipe.startReading { (_: StubRequest) in }
        try await Task.sleep(for: .milliseconds(100))

        let closeStartedAt = ContinuousClock.now
        let elapsedOnComplete: ContinuousClock.Duration = await withTaskGroup(of: ContinuousClock.Duration?.self) { group in
            group.addTask {
                await hostPipe.close()
                return ContinuousClock.now - closeStartedAt
            }
            group.addTask {
                do {
                    try await Task.sleep(for: .seconds(2))
                } catch {
                    return nil
                }
                try? await externalWriter.write("rescue\n")
                return nil
            }
            var result: ContinuousClock.Duration = .seconds(0)
            for await item in group {
                if let item = item {
                    result = item
                    break
                }
            }
            group.cancelAll()
            await group.waitForAll()
            return result
        }

        XCTAssertLessThan(elapsedOnComplete, .seconds(1), "HostRequestPipe.close() should return promptly while its internal reader Task is parked in readLine() with an external writer attached; >=1s means the request-side shutdown sequence has drifted from the response-side one.")

        await externalWriter.close()
    }

    private enum CloseOutcome {
        case closed
        case deadlineFired
    }

    // MARK: - Helpers

    /// Reads up to `count` lines from `reader`, with a hard wall-clock
    /// deadline. When the deadline expires, closes `writer` so any in-flight
    /// blocking read sees EOF and returns `nil` instead of hanging the test.
    /// Returns exactly `count` entries (any unread positions are `nil`).
    private func readLines(
        from reader: ReadPipe,
        count: Int,
        deadlineSeconds: TimeInterval,
        closingWriter writer: WritePipe?
    ) async -> [String?] {
        await withTaskGroup(of: ReadGroupResult.self) { group in
            group.addTask {
                var collected: [String?] = []
                for _ in 0..<count {
                    let line: String?
                    do {
                        line = try await reader.readLine()
                    } catch {
                        line = nil
                    }
                    collected.append(line)
                    if line == nil { break }
                }
                return .reads(collected)
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(deadlineSeconds))
                // Close the writer to send EOF to any blocked reader. This
                // unblocks `readLine()` and lets the read task finish. When
                // no writer is supplied (the caller doesn't want to disturb
                // an in-flight writer), the deadline is purely advisory.
                await writer?.close()
                return .deadlineFired
            }

            var collected: [String?] = []
            for await result in group {
                switch result {
                case .reads(let lines):
                    collected = lines
                    group.cancelAll()
                    // pad with nils for any positions we didn't reach
                    while collected.count < count { collected.append(nil) }
                    return collected
                case .deadlineFired:
                    // Wait for the read task to drain (it should now finish
                    // because we just closed the writer).
                    continue
                }
            }
            while collected.count < count { collected.append(nil) }
            return collected
        }
    }

    private enum ReadGroupResult {
        case reads([String?])
        case deadlineFired
    }

    // MARK: - Dispatch ordering tests
    //
    // These tests pin down the per-request dispatch invariants in
    // `HostRequestPipe.startReading(...)`:
    //
    //  - `initialize` is dispatched inline (read loop blocks until handler
    //    returns), so any subsequent same-helper request observes the host
    //    state that `initialize` set up (e.g. the response pipe being
    //    opened and registered).
    //  - `deinitialize` is dispatched inline (read loop blocks until handler
    //    returns), so the response pipe teardown runs immediately even if
    //    the helper had in-flight tool-call handlers. Those in-flight
    //    handlers may fail to write back — that's the documented contract:
    //    a helper that wanted those responses shouldn't have sent
    //    deinitialize early.
    //  - Non-lifecycle requests are dispatched in their own Task, so
    //    handlers run concurrently with the read loop and with each
    //    other. This preserves the parallel-tool-call workload that
    //    commit 4c00a64 was originally optimizing for.
    //
    // The tests below exercise each of these invariants in isolation.

    /// Helper to drive a sequence of pre-written JSON request lines through
    /// `HostRequestPipe` and observe the dispatcher's behavior via a handler
    /// closure. The pipe is opened, a writer is attached, the requests are
    /// pre-queued in the FIFO before `startReading()` is called, then the
    /// reader starts and the supplied `body` runs the assertions. Always
    /// tears everything down on exit.
    private func withDispatchHarness(
        preQueuedRequests: [DispatchTestRequest],
        handler: @escaping @Sendable (DispatchTestRequest) async -> Void,
        body: (_ hostPipe: HostRequestPipe<DispatchTestRequest>, _ writer: WritePipe) async throws -> Void
    ) async throws {
        let readPipe = try ReadPipe(url: fifoURL)
        let hostPipe = HostRequestPipe<DispatchTestRequest>(readPipe: readPipe)
        try await hostPipe.open()

        let writer = try WritePipe(url: fifoURL)
        try await writer.open()

        let encoder = JSONEncoder()
        for request in preQueuedRequests {
            var line = try encoder.encode(request)
            line.append(10) // newline
            try await writer.write(line)
        }

        await hostPipe.startReading(requestHandler: handler)

        do {
            try await body(hostPipe, writer)
        } catch {
            await hostPipe.close()
            await writer.close()
            throw error
        }
        await hostPipe.close()
        await writer.close()
    }

    /// An `initialize` request followed immediately by a tool-call request
    /// for the same helperId must be dispatched in order — the tool-call
    /// handler must not start until the `initialize` handler has fully
    /// returned. This is the production invariant that broke with commit
    /// 4c00a64 (when both requests were Task-dispatched, the tool-call's
    /// Task could run before the initialize's Task finished opening the
    /// response pipe, the tool-call handler then found no pipe registered,
    /// returned silently, and the helper timed out).
    func testInitializeBlocksSubsequentSameHelperRequest() async throws {
        let helperId = "helper-A"
        let initializeStarted = AsyncOrderRecorder()
        let initializeFinished = AsyncOrderRecorder()
        let toolCallStarted = AsyncOrderRecorder()

        let preQueued: [DispatchTestRequest] = [
            DispatchTestRequest(helperId: helperId, messageId: "m-init", isInitialize: true),
            DispatchTestRequest(helperId: helperId, messageId: "m-tool")
        ]

        let toolCallObserved = expectation(description: "tool-call handler ran")

        try await withDispatchHarness(
            preQueuedRequests: preQueued,
            handler: { request in
                if request.isInitialize {
                    await initializeStarted.record("init-start")
                    // Simulate the host doing pipe setup work — equivalent to
                    // `setupResponsePipe(for:)` opening a FIFO. The whole
                    // point of the inline-dispatch invariant is that the
                    // tool-call handler must wait for this to finish.
                    try? await Task.sleep(for: .milliseconds(150))
                    await initializeFinished.record("init-end")
                } else {
                    await toolCallStarted.record("tool-start")
                    toolCallObserved.fulfill()
                }
            },
            body: { _, _ in
                await fulfillment(of: [toolCallObserved], timeout: 2.0)
            }
        )

        let initStartIdx = await initializeStarted.firstIndex(of: "init-start")
        let initEndIdx = await initializeFinished.firstIndex(of: "init-end")
        let toolStartIdx = await toolCallStarted.firstIndex(of: "tool-start")

        XCTAssertNotNil(initStartIdx, "initialize handler should have run")
        XCTAssertNotNil(initEndIdx, "initialize handler should have finished")
        XCTAssertNotNil(toolStartIdx, "tool-call handler should have run")

        if let initEnd = initEndIdx, let toolStart = toolStartIdx {
            // We measured init-end and tool-start on separate AsyncOrderRecorders
            // (so their indices aren't directly comparable). Instead, re-derive
            // the ordering via the absolute timestamps each recorder stamped.
            let initEndAt = await initializeFinished.timestamp(at: initEnd)
            let toolStartAt = await toolCallStarted.timestamp(at: toolStart)
            XCTAssertLessThan(initEndAt, toolStartAt, "tool-call handler started before initialize handler finished — the read loop did not wait for initialize to complete before dispatching the next request, which means EasyMCPHost.setupResponsePipe could race against the first real tool call.")
        }
    }

    /// Two non-lifecycle (tool-call) requests from the same helper must run
    /// concurrently — the second must be able to start while the first is
    /// still in its handler. This is the parallel-tool-call workload that
    /// commit 4c00a64 originally enabled and that the current dispatch
    /// shape continues to support.
    func testNonLifecycleRequestsRunConcurrently() async throws {
        let helperId = "helper-A"
        let firstStarted = expectation(description: "first handler started")
        let secondStarted = expectation(description: "second handler started")
        let firstFinish = AsyncSignal()

        let preQueued: [DispatchTestRequest] = [
            DispatchTestRequest(helperId: helperId, messageId: "m-1"),
            DispatchTestRequest(helperId: helperId, messageId: "m-2")
        ]

        try await withDispatchHarness(
            preQueuedRequests: preQueued,
            handler: { request in
                if request.messageId == "m-1" {
                    firstStarted.fulfill()
                    // Block until the test releases us. If dispatch were
                    // serial, the second request's handler would never get
                    // to fulfill `secondStarted` and the test would time
                    // out at `fulfillment(of: [secondStarted])`.
                    await firstFinish.wait()
                } else {
                    secondStarted.fulfill()
                }
            },
            body: { _, _ in
                await fulfillment(of: [firstStarted, secondStarted], timeout: 2.0)
                await firstFinish.signal()
            }
        )
    }

    /// A non-lifecycle handler that takes a long time must not block the
    /// read loop. The read loop should continue pulling subsequent requests
    /// off the pipe and dispatching them. We assert this by writing a
    /// blocking request followed by a fast request and showing that the
    /// fast request's handler runs before we release the blocking one.
    func testReadLoopKeepsReadingDuringSlowHandler() async throws {
        let helperId = "helper-A"
        let blockerStarted = expectation(description: "blocker started")
        let fastDispatched = expectation(description: "fast handler ran")
        let blockerRelease = AsyncSignal()

        let preQueued: [DispatchTestRequest] = [
            DispatchTestRequest(helperId: helperId, messageId: "m-blocker"),
            DispatchTestRequest(helperId: helperId, messageId: "m-fast")
        ]

        try await withDispatchHarness(
            preQueuedRequests: preQueued,
            handler: { request in
                if request.messageId == "m-blocker" {
                    blockerStarted.fulfill()
                    await blockerRelease.wait()
                } else {
                    fastDispatched.fulfill()
                }
            },
            body: { _, _ in
                // If the read loop were waiting for the blocker's handler to
                // finish before reading the next line, `fastDispatched`
                // would never fulfill and we'd hit the timeout.
                await fulfillment(of: [blockerStarted, fastDispatched], timeout: 2.0)
                await blockerRelease.signal()
            }
        )
    }

    /// A slow non-lifecycle handler for helper A must not block dispatch of
    /// a request from helper B. Cross-helper concurrency is the design
    /// payoff of the per-request Task dispatch — without it, one slow
    /// helper could starve every other helper sharing the central pipe.
    func testRequestsFromDifferentHelpersAreNotSerialized() async throws {
        let slowStarted = expectation(description: "slow helper handler started")
        let fastDispatched = expectation(description: "fast helper handler ran")
        let slowRelease = AsyncSignal()

        let preQueued: [DispatchTestRequest] = [
            DispatchTestRequest(helperId: "helper-A", messageId: "m-slow"),
            DispatchTestRequest(helperId: "helper-B", messageId: "m-fast")
        ]

        try await withDispatchHarness(
            preQueuedRequests: preQueued,
            handler: { request in
                if request.helperId == "helper-A" {
                    slowStarted.fulfill()
                    await slowRelease.wait()
                } else {
                    fastDispatched.fulfill()
                }
            },
            body: { _, _ in
                await fulfillment(of: [slowStarted, fastDispatched], timeout: 2.0)
                await slowRelease.signal()
            }
        )
    }

    /// `deinitialize` is dispatched inline (the read loop blocks until its
    /// handler returns), and it does NOT wait for previously-dispatched
    /// non-lifecycle handlers from the same helper to finish. This pins
    /// down the documented contract: a helper that sends `deinitialize`
    /// while it still has in-flight tool-call requests has explicitly
    /// signaled that it no longer cares about those responses; the host
    /// is free to tear down the response pipe immediately.
    ///
    /// Test shape: queue [tool-call, deinitialize]. The tool-call handler
    /// parks on a signal that the test never releases until after it
    /// observes the deinitialize handler running. If deinitialize were
    /// gated on the in-flight tool-call finishing, the deinit handler
    /// would never run and `deinitObserved` would time out.
    func testDeinitializeDoesNotWaitForInFlightToolCalls() async throws {
        let helperId = "helper-A"
        let toolStarted = expectation(description: "tool-call started")
        let deinitObserved = expectation(description: "deinit handler ran")
        let toolRelease = AsyncSignal()

        let preQueued: [DispatchTestRequest] = [
            DispatchTestRequest(helperId: helperId, messageId: "m-tool"),
            DispatchTestRequest(helperId: helperId, messageId: "m-deinit", isDeinitialize: true)
        ]

        try await withDispatchHarness(
            preQueuedRequests: preQueued,
            handler: { request in
                if request.isDeinitialize {
                    deinitObserved.fulfill()
                } else {
                    toolStarted.fulfill()
                    await toolRelease.wait()
                }
            },
            body: { _, _ in
                await fulfillment(of: [toolStarted, deinitObserved], timeout: 2.0)
                await toolRelease.signal()
            }
        )
    }

    // MARK: - Shutdown log-noise tests
    //
    // These tests pin down a separate but related contract: the documented
    // shutdown sequence (cancel reader Task → signalReaderWake → await
    // Task → close pipe) must not surface any error-level log lines. Two
    // independent noise sources used to exist on this path:
    //
    //   1. `AsyncLineSequence.next()` throws `CancellationError` when its
    //      enclosing Task is cancelled. `ReadPipe.readLine()` used to log
    //      that as "Error reading line from pipe" and wrap it as
    //      `ReadPipeError.readError`. The consumer's catch then logged it
    //      a second time as "Error in response reader" / "Error in read
    //      loop". Two error lines per successful CLI invocation.
    //   2. `signalReaderWake()` writes a sentinel `\n` to unblock the
    //      parked read. `AsyncLineSequence` interprets that as an empty
    //      line and yields `""`. The consumer used to JSON-decode that
    //      empty string, fail, and log "Failed to decode response" — a
    //      third error line on every shutdown.
    //
    // The tests below install a `RecordingLogHandler` on the injected
    // logger, drive the production shutdown sequence end-to-end, and
    // assert no error-level events were emitted from the reader-Task
    // catch or from the empty-line decode path. They are the regression
    // backstop for both noise sources.

    /// A clean `ResponseManager.stopReading()` after the reader Task has
    /// parked in `readLine()` must not emit any error-level logs through
    /// the injected logger. Catches both the `CancellationError` rethrow
    /// from `ReadPipe.readLine()` (previously logged as "Error reading
    /// line from pipe" and "Error in response reader") and the sentinel
    /// empty-line case (previously logged as "Failed to decode response").
    func testResponseManagerShutdownEmitsNoErrorLogs() async throws {
        let recorder = LogRecorder()
        let logger = Logger(label: "test.response-manager-shutdown") { _ in
            RecordingLogHandler(recorder: recorder)
        }

        let helperPipe = try HelperResponsePipe(url: fifoURL, logger: logger)
        let manager = ResponseManager<StubResponse>(responsePipe: helperPipe, logger: logger)
        try await manager.startReading()

        // External writer attached but silent — mirrors the host-side
        // WritePipe staying open during CLI teardown.
        let externalWriter = try WritePipe(url: fifoURL)
        try await externalWriter.open()

        try await Task.sleep(for: .milliseconds(100))
        await manager.stopReading()

        let errors = recorder.eventsAtLevel(.error)
        XCTAssertTrue(
            errors.isEmpty,
            "ResponseManager shutdown must not log at error level — got \(errors.count): \(errors.map(\.message).joined(separator: " | "))"
        )

        await externalWriter.close()
    }

    /// Same shape as the ResponseManager test, but for `HostRequestPipe`.
    /// The request-side reader-Task catch had the same noise problem and
    /// the same fix; this test ensures the request-side shutdown is also
    /// quiet.
    func testHostRequestPipeShutdownEmitsNoErrorLogs() async throws {
        let recorder = LogRecorder()
        let logger = Logger(label: "test.host-request-shutdown") { _ in
            RecordingLogHandler(recorder: recorder)
        }

        let readPipe = try ReadPipe(url: fifoURL)
        let hostPipe = HostRequestPipe<StubRequest>(readPipe: readPipe, logger: logger)
        try await hostPipe.open()

        let externalWriter = try WritePipe(url: fifoURL)
        try await externalWriter.open()

        await hostPipe.startReading { (_: StubRequest) in }
        try await Task.sleep(for: .milliseconds(100))
        await hostPipe.close()

        let errors = recorder.eventsAtLevel(.error)
        XCTAssertTrue(
            errors.isEmpty,
            "HostRequestPipe shutdown must not log at error level — got \(errors.count): \(errors.map(\.message).joined(separator: " | "))"
        )

        await externalWriter.close()
    }

}

/// Test-only ordered append actor. Tests use it to record when handlers
/// observe a particular state in dispatch order and then assert on the
/// resulting sequence after the fact. Each `record(_:)` also stamps a
/// monotonic timestamp so cross-recorder ordering can be reconstructed.
private actor AsyncOrderRecorder {
    private var entries: [(label: String, at: ContinuousClock.Instant)] = []

    func record(_ label: String) {
        entries.append((label: label, at: ContinuousClock.now))
    }

    func firstIndex(of label: String) -> Int? {
        entries.firstIndex(where: { $0.label == label })
    }

    func timestamp(at index: Int) -> ContinuousClock.Instant {
        entries[index].at
    }
}

/// One-shot async gate. `wait()` suspends until `signal()` is called.
/// `signal()` is idempotent; subsequent calls are no-ops.
private actor AsyncSignal {
    private var continuations: [CheckedContinuation<Void, Never>] = []
    private var fired = false

    func wait() async {
        if fired { return }
        await withCheckedContinuation { continuation in
            continuations.append(continuation)
        }
    }

    func signal() {
        guard !fired else { return }
        fired = true
        let pending = continuations
        continuations.removeAll()
        for continuation in pending {
            continuation.resume()
        }
    }
}

/// Thread-safe in-memory store of log events captured by
/// `RecordingLogHandler`. Tests construct a `Logger` whose factory closure
/// returns a `RecordingLogHandler` wired to a shared `LogRecorder`, run
/// the production code, then query `eventsAtLevel(_:)` to assert
/// expectations.
///
/// Recording is synchronous (`NSLock`-guarded) rather than actor-isolated
/// so the `LogHandler.log(...)` call site can record without spawning a
/// Task — that avoids a race where the assertion runs before the captured
/// event reaches the actor.
private final class LogRecorder: @unchecked Sendable {
    struct CapturedEvent: Sendable {
        let level: Logger.Level
        let message: String
    }

    private let lock = NSLock()
    private var events: [CapturedEvent] = []

    func record(level: Logger.Level, message: String) {
        lock.lock()
        events.append(CapturedEvent(level: level, message: message))
        lock.unlock()
    }

    func eventsAtLevel(_ level: Logger.Level) -> [CapturedEvent] {
        lock.lock()
        defer { lock.unlock() }
        return events.filter { $0.level == level }
    }
}

/// `LogHandler` implementation that funnels every emitted event into a
/// shared `LogRecorder`. The handler logs at every level (no filtering at
/// this layer) so the test can decide what counts as noise. Required
/// mutable `metadata`/`logLevel`/`metadataProvider` properties exist only
/// to satisfy the protocol.
private struct RecordingLogHandler: LogHandler {
    let recorder: LogRecorder
    var metadata: Logger.Metadata = [:]
    var logLevel: Logger.Level = .trace
    var metadataProvider: Logger.MetadataProvider?

    subscript(metadataKey key: String) -> Logger.Metadata.Value? {
        get { metadata[key] }
        set { metadata[key] = newValue }
    }

    func log(event: LogEvent) {
        recorder.record(level: event.level, message: event.message.description)
    }
}
