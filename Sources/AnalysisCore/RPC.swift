import Foundation
import Darwin

/// Synchronous JSONL transport for a bounded command-line experiment. No credentials or raw messages are logged.
public final class RPC {
    private let process = Process()
    private let input = Pipe()
    private let output = Pipe()
    private var buffer = Data()
    private var nextID = 0
    private var pending: [[String: Any]] = []
    private let temporaryState: URL?
    private var started = false
    private var closed = false
    public private(set) var notificationCounts: [String: Int] = [:]

    public init(executable: String, arguments: [String], cwd: URL, temporaryState: URL? = nil) throws {
        self.temporaryState = temporaryState
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.currentDirectoryURL = cwd
        process.standardInput = input
        process.standardOutput = output
        // Provider logs may include user config paths or other unrelated context; don't persist them.
        process.standardError = FileHandle.nullDevice
        try process.run()
        started = true
    }

    deinit { close() }

    public func close() {
        guard !closed else { return }
        closed = true
        try? input.fileHandleForWriting.close()
        if process.isRunning { process.terminate() }
        let deadline = Date().addingTimeInterval(2)
        while process.isRunning && Date() < deadline { usleep(10_000) }
        if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        if started { process.waitUntilExit() }
        try? output.fileHandleForReading.close()
        if let temporaryState { try? FileManager.default.removeItem(at: temporaryState) }
    }

    public func send(_ message: [String: Any]) throws {
        var data = try JSONSerialization.data(withJSONObject: message)
        data.append(10)
        try input.fileHandleForWriting.write(contentsOf: data)
    }

    private func receive(deadline: Date) throws -> [String: Any] {
        while true {
            if let newline = buffer.firstIndex(of: 10) {
                let line = buffer[..<newline]
                buffer.removeSubrange(...newline)
                guard let object = try JSONSerialization.jsonObject(with: Data(line)) as? [String: Any] else {
                    throw AnalysisError("Invalid JSONL object from app-server")
                }
                return object
            }
            guard buffer.count < 8 * 1024 * 1024 else { throw AnalysisError("Oversized app-server message") }
            guard Date() < deadline else { throw AnalysisError("App-server request timed out") }
            var descriptor = pollfd(fd: output.fileHandleForReading.fileDescriptor, events: Int16(POLLIN | POLLHUP), revents: 0)
            let ready = poll(&descriptor, 1, 100)
            if ready < 0 {
                if errno == EINTR { continue }
                throw AnalysisError("Could not poll app-server")
            }
            if ready == 0 { continue }
            var chunk = [UInt8](repeating: 0, count: 65536)
            let count = Darwin.read(descriptor.fd, &chunk, chunk.count)
            guard count > 0 else { throw AnalysisError("App-server closed its output") }
            buffer.append(contentsOf: chunk.prefix(count))
        }
    }

    private func handle(_ message: [String: Any]) throws {
        if let method = message["method"] as? String {
            notificationCounts[method, default: 0] += 1
            if let id = message["id"] {
                // Never grant tools, permission escalation, token exchange or user input on behalf of the user.
                try send(["id": id, "error": ["code": -32601, "message": "This analysis client does not support server requests"]])
                throw AnalysisError("Unexpected app-server request: \(method)")
            }
        }
        pending.append(message)
        guard pending.count < 20_000 else { throw AnalysisError("Too many pending app-server events") }
    }

    public func request(_ method: String, _ params: [String: Any] = [:], timeout: Double = 30) throws -> [String: Any] {
        nextID += 1
        let id = nextID
        try send(["method": method, "id": id, "params": params])
        let deadline = Date().addingTimeInterval(timeout)
        while true {
            let message = try receive(deadline: deadline)
            if message["id"] as? Int == id, message["method"] == nil {
                if let error = message["error"] as? [String: Any] {
                    throw AnalysisError("\(method): \(error["message"] as? String ?? "RPC error")")
                }
                guard let result = message["result"] as? [String: Any] else { throw AnalysisError("Missing result for \(method)") }
                return result
            }
            try handle(message)
        }
    }

    public func nextEvent(timeout: Double = 1) throws -> [String: Any]? {
        if !pending.isEmpty { return pending.removeFirst() }
        do {
            let message = try receive(deadline: Date().addingTimeInterval(timeout))
            try handle(message)
            return pending.removeFirst()
        } catch let e as AnalysisError where e.description == "App-server request timed out" { return nil }
    }
}
