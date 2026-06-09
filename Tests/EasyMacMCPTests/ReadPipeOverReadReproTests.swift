import XCTest
import Foundation
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
}
