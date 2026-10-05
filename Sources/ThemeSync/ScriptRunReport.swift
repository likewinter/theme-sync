import Foundation

struct ScriptConfiguration: Equatable {
    let path: String
    let arguments: String

    init(path: String, arguments: String) {
        self.path = path.trimmingCharacters(in: .whitespacesAndNewlines)
        self.arguments = arguments
    }

    init(isDark: Bool, defaults: UserDefaults = .standard) {
        self.init(
            path: defaults.string(forKey: isDark ? DefaultsKeys.darkPath : DefaultsKeys.lightPath) ?? "",
            arguments: defaults.string(forKey: isDark ? DefaultsKeys.darkArgs : DefaultsKeys.lightArgs) ?? ""
        )
    }

    var problem: String? {
        guard !path.isEmpty else { return "Choose a script before testing." }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) else {
            return "File not found. Choose an existing script."
        }
        guard !isDirectory.boolValue else { return "Choose a script file, not a folder." }
        guard FileManager.default.isExecutableFile(atPath: path) else {
            return "File is not executable. Use chmod +x to make it executable."
        }
        do {
            _ = try CommandLineArgumentParser.parse(arguments)
        } catch {
            return error.localizedDescription
        }
        return nil
    }
}

struct ScriptRunReport: Codable, Equatable {
    let isDark: Bool
    let path: String
    let arguments: String
    let startedAt: Date
    let finishedAt: Date
    let timeout: TimeInterval
    let exitCode: Int32?
    let timedOut: Bool
    let terminatedBySignal: Bool
    let errorMessage: String?
    let output: String
    let outputTruncated: Bool

    var modeName: String { isDark ? "Dark" : "Light" }
    var succeeded: Bool { errorMessage == nil && !timedOut && !terminatedBySignal && exitCode == 0 }
    var duration: TimeInterval { max(0, finishedAt.timeIntervalSince(startedAt)) }

    var status: String {
        if errorMessage != nil { return "could not run" }
        if timedOut { return "timed out" }
        return succeeded ? "succeeded" : "failed"
    }

    var menuTitle: String { "Last run: \(modeName) · \(status)" }

    var summary: String {
        if let errorMessage { return errorMessage }
        if timedOut { return "Timed out after \(String(format: "%g", timeout)) s." }
        if terminatedBySignal { return "Stopped by signal \(exitCode ?? 0)." }
        if succeeded { return String(format: "Succeeded in %.1f s.", duration) }
        return "Failed with exit code \(exitCode ?? 0)."
    }

    var details: String {
        var lines = [
            "Mode: \(modeName)",
            "Script: \(path)",
            "Arguments: \(arguments.isEmpty ? "None" : arguments)",
            "Started: \(DateFormatter.localizedString(from: startedAt, dateStyle: .medium, timeStyle: .medium))",
            String(format: "Duration: %.1f s", duration),
            "Result: \(summary)"
        ]
        if !output.isEmpty {
            lines.append("\nOutput\(outputTruncated ? " (earlier output omitted)" : ""):\n\(output)")
        } else {
            lines.append("\nNo output.")
        }
        return lines.joined(separator: "\n")
    }
}

enum ScriptTestState {
    case queued
    case running
    case finished(ScriptRunReport)
}

extension ScriptRunner {
    func run(configuration: ScriptConfiguration, isDark: Bool) -> ScriptRunReport {
        let startedAt = Date()
        var result: ScriptExecutionResult?
        var errorMessage = configuration.problem
        if errorMessage == nil {
            do {
                result = try run(path: configuration.path, arguments: configuration.arguments,
                                 environment: ["THEME_MODE": isDark ? "dark" : "light"])
            } catch {
                errorMessage = error.localizedDescription
            }
        }
        return ScriptRunReport(
            isDark: isDark, path: configuration.path, arguments: configuration.arguments,
            startedAt: startedAt, finishedAt: Date(), timeout: timeout,
            exitCode: result?.exitCode, timedOut: result?.timedOut ?? false,
            terminatedBySignal: result?.terminatedBySignal ?? false,
            errorMessage: errorMessage, output: result?.output ?? "",
            outputTruncated: result?.outputTruncated ?? false
        )
    }
}
