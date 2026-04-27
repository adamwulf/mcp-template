import XCTest
import Foundation
@testable import EasyMacMCP

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
                try? await Task.sleep(for: .seconds(3))
                // Deadline: close the reader to unblock any hung readLine().
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
