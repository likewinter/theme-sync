import Darwin
import Foundation

struct ScriptExecutionResult {
    let exitCode: Int32
    let timedOut: Bool
    let terminatedBySignal: Bool
    let output: String
    let outputTruncated: Bool
}

enum ScriptRunnerError: LocalizedError, Equatable {
    case unbalancedQuote

    var errorDescription: String? {
        switch self {
        case .unbalancedQuote:
            return "Arguments contain an unbalanced quote. Close the quote before testing."
        }
    }
}

enum CommandLineArgumentParser {
    static func parse(_ input: String) throws -> [String] {
        var arguments: [String] = []
        var current = ""
        var hasCurrent = false
        var inSingleQuote = false
        var inDoubleQuote = false
        var isEscaping = false

        for character in input {
            if isEscaping {
                current.append(character)
                hasCurrent = true
                isEscaping = false
                continue
            }

            if character == "\\" && !inSingleQuote {
                isEscaping = true
                hasCurrent = true
                continue
            }

            if character == "'" && !inDoubleQuote {
                inSingleQuote.toggle()
                hasCurrent = true
                continue
            }

            if character == "\"" && !inSingleQuote {
                inDoubleQuote.toggle()
                hasCurrent = true
                continue
            }

            if character.isShellWhitespace && !inSingleQuote && !inDoubleQuote {
                if hasCurrent {
                    arguments.append(current)
                    current = ""
                    hasCurrent = false
                }
                continue
            }

            current.append(character)
            hasCurrent = true
        }

        if isEscaping {
            current.append("\\")
        }

        guard !inSingleQuote, !inDoubleQuote else {
            throw ScriptRunnerError.unbalancedQuote
        }

        if hasCurrent {
            arguments.append(current)
        }

        return arguments
    }
}

struct ScriptRunner {
    let timeout: TimeInterval

    init(timeout: TimeInterval = 30) {
        self.timeout = timeout
    }

    func run(path: String, arguments: String, environment: [String: String] = [:]) throws -> ScriptExecutionResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = try CommandLineArgumentParser.parse(arguments)

        let output = try ScriptOutputCapture()
        defer { output.close() }
        process.standardOutput = output.pipe
        process.standardError = output.pipe

        if !environment.isEmpty {
            var env = ProcessInfo.processInfo.environment
            env.merge(environment) { _, new in new }
            process.environment = env
        }

        let completion = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in
            completion.signal()
        }

        try process.run()
        try output.pipe.fileHandleForWriting.close()

        // Best-effort: give the child its own process group so the timeout
        // signals below also reach processes the script spawned.
        setpgid(process.processIdentifier, process.processIdentifier)

        let deadline = DispatchTime.now() + timeout
        // Drain output while waiting so a verbose script cannot fill its pipe
        // and block. Nonblocking reads also avoid waiting for background children.
        func waitForCompletion(until deadline: DispatchTime) -> Bool {
            while true {
                output.drain()
                let nextCheck = min(deadline, DispatchTime.now() + 0.02)
                if completion.wait(timeout: nextCheck) == .success { return true }
                if DispatchTime.now() >= deadline { return false }
            }
        }

        let timedOut = !waitForCompletion(until: deadline)
        if timedOut {
            let pid = process.processIdentifier
            // The group kill only works when setpgid above won the race;
            // signal the child directly as a fallback.
            kill(-pid, SIGTERM)
            kill(pid, SIGTERM)

            let graceDeadline = DispatchTime.now() + 1
            let parentExited = waitForCompletion(until: graceDeadline)
            if parentExited {
                // The parent may exit before descendants finish their cleanup.
                // Give the remaining group the same grace period.
                while kill(-pid, 0) == 0 && DispatchTime.now() < graceDeadline {
                    output.drain()
                    Thread.sleep(forTimeInterval: 0.01)
                }
            }

            // Escalate the group even when the direct child already exited.
            kill(-pid, SIGKILL)
            if !parentExited {
                kill(pid, SIGKILL)
                completion.wait()
            }
        }

        output.drain()

        return ScriptExecutionResult(
            exitCode: process.terminationStatus,
            timedOut: timedOut,
            terminatedBySignal: process.terminationReason == .uncaughtSignal,
            output: String(decoding: output.data, as: UTF8.self),
            outputTruncated: output.truncated
        )
    }
}

private final class ScriptOutputCapture {
    let pipe = Pipe()
    private(set) var data = Data()
    private(set) var truncated = false
    private let limit = 64 * 1024

    init() throws {
        let fd = pipe.fileHandleForReading.fileDescriptor
        let flags = fcntl(fd, F_GETFL)
        guard flags != -1, fcntl(fd, F_SETFL, flags | O_NONBLOCK) != -1 else {
            let error = NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
            close()
            throw error
        }
    }

    func drain() {
        var buffer = [UInt8](repeating: 0, count: 16 * 1024)
        // Bound each drain so continuous output cannot delay the timeout.
        for _ in 0..<16 {
            let count = Darwin.read(pipe.fileHandleForReading.fileDescriptor, &buffer, buffer.count)
            if count < 0 && errno == EINTR { continue }
            guard count > 0 else { return }
            data.append(contentsOf: buffer.prefix(count))
            if data.count > limit {
                data.removeFirst(data.count - limit)
                truncated = true
            }
        }
    }

    func close() {
        try? pipe.fileHandleForWriting.close()
        try? pipe.fileHandleForReading.close()
    }
}

private extension Character {
    var isShellWhitespace: Bool {
        unicodeScalars.allSatisfy { CharacterSet.whitespacesAndNewlines.contains($0) }
    }
}
