import Darwin
import Foundation

struct ScriptExecutionResult {
    let exitCode: Int32
    let timedOut: Bool
}

enum ScriptRunnerError: LocalizedError {
    case unbalancedQuote

    var errorDescription: String? {
        switch self {
        case .unbalancedQuote:
            return "Arguments contain an unbalanced quote."
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

    func run(path: String, arguments: String) throws -> ScriptExecutionResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = try CommandLineArgumentParser.parse(arguments)

        let completion = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in
            completion.signal()
        }

        try process.run()

        let deadline = DispatchTime.now() + timeout
        let timedOut = completion.wait(timeout: deadline) == .timedOut
        if timedOut {
            process.terminate()

            if completion.wait(timeout: .now() + 1) == .timedOut {
                kill(process.processIdentifier, SIGKILL)
                completion.wait()
            }
        }

        return ScriptExecutionResult(
            exitCode: process.terminationStatus,
            timedOut: timedOut
        )
    }
}

private extension Character {
    var isShellWhitespace: Bool {
        unicodeScalars.allSatisfy { CharacterSet.whitespacesAndNewlines.contains($0) }
    }
}
