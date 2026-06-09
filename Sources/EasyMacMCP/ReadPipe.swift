import Foundation
import Darwin

/// Errors that can occur when working with ReadPipe
public enum ReadPipeError: Error {
    case invalidURL
    case failedToCreatePipe(String)
    case pipeAlreadyExists
    case pipeDoesNotExist
    case notAPipe
    case openFailed(String)
    case keepaliveOpenFailed(String)
    case getFlagsFailed(String)
    case setFlagsFailed(String)
    case pipeNotOpened
    case pipeAlreadyOpen
    case readError(Error)
    case eof
    case stringEncodingError
}

/// A class for creating and reading from a named pipe (FIFO)
public actor ReadPipe: PipeReadable {
    private let fileURL: URL
    private var fileHandle: FileHandle?
    /// Persistent line iterator over `fileHandle.bytes.lines`. Held across
    /// `readLine()` calls so the underlying `AsyncBytes` chunk buffer
    /// survives — building a fresh iterator per call would over-read the FD
    /// and silently discard any extra lines that came in the same chunk.
    private var lineIterator: AsyncLineSequence<FileHandle.AsyncBytes>.AsyncIterator?
    /// Self-pipe keepalive: a writer-side FD on the same FIFO that we hold
    /// open for the lifetime of the ReadPipe. With at least one writer always
    /// attached, the kernel never delivers EOF to the reader when external
    /// writers detach, so `read(2)` (and therefore `AsyncBytes`) blocks until
    /// a real writer produces data instead of returning nil and spinning the
    /// caller's read loop.
    private var keepaliveWriterFD: Int32?

    /// Initialize with a URL that represents where the pipe should be created
    /// - Parameters:
    ///   - url: A file URL where the pipe should be created
    /// - Throws: ReadPipeError if initialization fails
    public init(url: URL) throws {
        guard url.isFileURL else {
            throw ReadPipeError.invalidURL
        }

        self.fileURL = url

        // Create the pipe
        let pipePath = fileURL.path
        let fileManager = FileManager.default

        // Check if the path already exists
        if fileManager.fileExists(atPath: pipePath) {
            // Check if it's a pipe using FileManager extension
            if fileManager.isPipe(at: fileURL) {
                return
            } else {
                do {
                    try fileManager.removeItem(atPath: pipePath)
                } catch {
                    throw ReadPipeError.pipeAlreadyExists
                }
            }
        }

        // Create the pipe with read/write permissions for user, group, and others
        // 0o666 = rw-rw-rw-
        let result = mkfifo(pipePath, 0o666)

        if result != 0 {
            let errorString = String(cString: strerror(errno))
            throw ReadPipeError.failedToCreatePipe(errorString)
        }

        // Verify it's actually a pipe
        guard fileManager.isPipe(at: fileURL) else {
            throw ReadPipeError.notAPipe
        }
    }

    deinit {
        // No cancel/await/signal-wake dance here: deinit only runs when there
        // are zero references to this actor, and any consumer Task parked in
        // `readLine()` is keeping the consumer's actor (and therefore this
        // ReadPipe) alive through `readPipe.readLine()`. By the time deinit
        // can fire, every reader Task has already exited via the documented
        // shutdown sequence. Do NOT try to add the sentinel-write pattern
        // here — deinit is synchronous and cannot await dispatch_io to drain.
        if let fd = keepaliveWriterFD {
            Darwin.close(fd)
            keepaliveWriterFD = nil
        }
        try? fileHandle?.close()
        fileHandle = nil
    }

    /// Opens the pipe for reading without blocking on open, but allowing blocking reads
    /// - Throws: ReadPipeError if opening fails, including `.pipeAlreadyOpen`
    ///   if the pipe is already open and `.keepaliveOpenFailed` if the
    ///   self-pipe writer FD could not be opened (in which case the reader
    ///   FD is closed and no resources are leaked).
    public func open() async throws {
        // Reject double-open. Re-opening would leak the previous reader FD's
        // FileHandle and the keepalive writer FD; callers must close()
        // explicitly before re-opening.
        guard fileHandle == nil && keepaliveWriterFD == nil else {
            throw ReadPipeError.pipeAlreadyOpen
        }

        // Make sure the path exists and is a pipe
        let pipePath = fileURL.path
        guard FileManager.default.fileExists(atPath: pipePath) else {
            throw ReadPipeError.pipeDoesNotExist
        }

        guard FileManager.default.isPipe(at: fileURL) else {
            throw ReadPipeError.notAPipe
        }

        // First open with O_NONBLOCK flag to prevent blocking on open
        let fileDescriptor = Darwin.open(pipePath, O_RDONLY | O_NONBLOCK, 0)
        guard fileDescriptor != -1 else {
            let errorString = String(cString: strerror(errno))
            Logging.printError("Error opening pipe for reading: \(errorString) (errno: \(errno))")
            throw ReadPipeError.openFailed(errorString)
        }

        // Get flags
        let flags = fcntl(fileDescriptor, F_GETFL)
        guard flags != -1 else {
            let errorString = String(cString: strerror(errno))
            Logging.printError("Error getting file descriptor flags: \(errorString)")
            Darwin.close(fileDescriptor)  // Close the FD to prevent leaks
            throw ReadPipeError.getFlagsFailed(errorString)
        }

        // Set flags based on blocking preference
        let newFlags: Int32 = flags & ~O_NONBLOCK
        let result = fcntl(fileDescriptor, F_SETFL, newFlags)
        if result == -1 {
            let errorString = String(cString: strerror(errno))
            Logging.printError("Error setting file descriptor flags: \(errorString)")
            // We still create the file handle but log the error
        }

        // Open a writer-side FD against the same FIFO and hold it for the
        // lifetime of the ReadPipe. This keeps the kernel writer count above
        // zero so external writers detaching does not trigger EOF on the
        // reader. O_NONBLOCK is required on this open so it cannot block when
        // there is currently no other writer; we never write to this FD.
        // Failure here means we cannot guarantee the no-EOF contract, so we
        // close the reader FD and surface an error rather than silently
        // re-introducing the original CPU-spin bug.
        let keepaliveFD = Darwin.open(pipePath, O_WRONLY | O_NONBLOCK, 0)
        guard keepaliveFD != -1 else {
            let errorString = String(cString: strerror(errno))
            Logging.printError("Error opening keepalive writer FD: \(errorString) (errno: \(errno))")
            Darwin.close(fileDescriptor)
            throw ReadPipeError.keepaliveOpenFailed(errorString)
        }

        // Both FDs are now owned by self. Create the FileHandle (which will
        // close the reader FD on dealloc) and stash the keepalive.
        let handle = FileHandle(fileDescriptor: fileDescriptor, closeOnDealloc: true)
        fileHandle = handle
        lineIterator = handle.bytes.lines.makeAsyncIterator()
        keepaliveWriterFD = keepaliveFD
    }

    /// Reads a single line from the pipe.
    ///
    /// Blocks until a line is available or the pipe is closed. Returns `nil`
    /// only when the pipe has been closed by us (via `close()` or `deinit`);
    /// an external writer detaching no longer ends the stream because
    /// ReadPipe holds its own writer FD as a keepalive, so the kernel writer
    /// count stays positive across writer churn.
    ///
    /// Uses a persistent `AsyncLineSequence` iterator so chunked reads from
    /// the underlying FD don't drop buffered lines between calls.
    ///
    /// **Cancellation:** if the calling Task is cancelled while parked in
    /// `iterator.next()`, the underlying `AsyncBytes` iterator throws
    /// `CancellationError`. That throw is the documented shutdown signal in
    /// our reader-Task contract (consumer cancels its Task → consumer calls
    /// `signalReaderWake()` → iterator yields → cancellation is observed),
    /// so it is rethrown without logging and without being wrapped in
    /// `ReadPipeError.readError`. Callers that loop on `readLine()` should
    /// either let `CancellationError` propagate out of their loop or check
    /// `Task.isCancelled` and exit cleanly. Any other thrown error is
    /// treated as a real I/O failure: it is logged and wrapped as
    /// `ReadPipeError.readError`.
    /// - Returns: A single line, or `nil` if the pipe has been closed.
    /// - Throws: `CancellationError` if the calling Task was cancelled;
    ///   otherwise `ReadPipeError` if reading fails.
    public func readLine() async throws -> String? {
        guard fileHandle != nil, var iterator = lineIterator else {
            Logging.printError("Error: Pipe not opened")
            throw ReadPipeError.pipeNotOpened
        }

        do {
            let line = try await iterator.next()
            lineIterator = iterator
            return line
        } catch is CancellationError {
            // Documented shutdown signal — rethrow cleanly, no error log.
            lineIterator = iterator
            throw CancellationError()
        } catch {
            lineIterator = iterator
            Logging.printError("Error reading line from pipe", error: error)
            throw ReadPipeError.readError(error)
        }
    }

    /// Wake a consumer Task that is parked in `readLine()` so it can observe
    /// cancellation. Writes a single newline byte through the keepalive writer
    /// FD without closing anything else. The byte enters the FIFO buffer,
    /// `AsyncBytes.Iterator` yields one stray empty line back to the consumer,
    /// the consumer's read loop checks `Task.isCancelled` and exits.
    ///
    /// Why this is separate from `close()`: closing the reader FD while a
    /// dispatch_io worker thread is parked on it deadlocks (see `close()`
    /// docs). The correct shutdown is:
    ///
    /// 1. Consumer cancels its reader Task.
    /// 2. Consumer calls `signalReaderWake()` to unblock the in-flight read.
    /// 3. Consumer awaits its reader Task — the reader Task gets actual
    ///    scheduler time on the cooperative pool to receive the iterator
    ///    yield triggered by the sentinel byte and then exit on observed
    ///    cancellation. Without this await, the actor that called close()
    ///    races dispatch_io's channel teardown.
    /// 4. Consumer calls `close()` — now uncontended, returns immediately.
    ///
    /// Sentinel write is best-effort: we discard the result of
    /// `Darwin.write` because a closed-or-full keepalive FD must not block
    /// teardown. The guard above already returns early if `open()` was
    /// never called or `close()` already ran.
    public func signalReaderWake() {
        guard let fd = keepaliveWriterFD else { return }
        var sentinel: UInt8 = 0x0A // '\n'
        _ = Darwin.write(fd, &sentinel, 1)
    }

    /// Closes the pipe.
    ///
    /// **Important**: if a consumer Task is currently parked in `readLine()`,
    /// the caller MUST have already cancelled and awaited that Task (with a
    /// `signalReaderWake()` between the cancel and the await) before calling
    /// `close()`. Otherwise the underlying `fileHandle.close()` will deadlock
    /// against `dispatch_io`'s in-flight read on the FD — `close(2)` on
    /// Darwin does not deliver EBADF/EINTR to the dispatch worker, and with
    /// an external writer still attached the FIFO never sees EOF.
    ///
    /// See `signalReaderWake()` for the documented shutdown sequence.
    public func close() async {
        lineIterator = nil
        if let fd = keepaliveWriterFD {
            Darwin.close(fd)
            keepaliveWriterFD = nil
        }
        try? fileHandle?.close()
        fileHandle = nil
    }
}
