import Foundation

struct TestFailure: Error, CustomStringConvertible {
    let description: String
}

func assertEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String) throws {
    if actual != expected {
        throw TestFailure(description: "\(message): expected \(expected), got \(actual)")
    }
}

func assertTrue(_ condition: Bool, _ message: String) throws {
    if !condition {
        throw TestFailure(description: message)
    }
}

func assertFalse(_ condition: Bool, _ message: String) throws {
    if condition {
        throw TestFailure(description: message)
    }
}

func testShellMetacharactersArePassedAsArguments() throws {
    let tempDir = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let script = tempDir.appendingPathComponent("record-args.sh")
    let output = tempDir.appendingPathComponent("args.txt")
    let marker = tempDir.appendingPathComponent("injected")

    try """
    #!/bin/sh
    printf '%s\\n' "$@" > "\(output.path)"
    """.write(to: script, atomically: true, encoding: .utf8)
    try makeExecutable(script)

    let runner = ScriptRunner(timeout: 2)
    let result = try runner.run(path: script.path, arguments: "safe; touch \(marker.path)")

    try assertEqual(result.exitCode, 0, "script exit code")
    try assertFalse(result.timedOut, "script should not time out")
    try assertFalse(FileManager.default.fileExists(atPath: marker.path), "shell metacharacters were executed")
    try assertEqual(
        try String(contentsOf: output, encoding: .utf8),
        "safe;\ntouch\n\(marker.path)\n",
        "script arguments"
    )
}

func testRunnerTerminatesProcessAfterTimeout() throws {
    let tempDir = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let script = tempDir.appendingPathComponent("slow.sh")
    let marker = tempDir.appendingPathComponent("finished")

    try """
    #!/bin/sh
    sleep 2
    touch "\(marker.path)"
    """.write(to: script, atomically: true, encoding: .utf8)
    try makeExecutable(script)

    let runner = ScriptRunner(timeout: 0.2)
    let result = try runner.run(path: script.path, arguments: "")

    try assertTrue(result.timedOut, "script should time out")
    try assertTrue(result.exitCode != 0, "timed-out script should not exit cleanly")
    try assertFalse(FileManager.default.fileExists(atPath: marker.path), "timed-out script kept running")
}

func testTimeoutKillsDescendantProcesses() throws {
    let tempDir = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let script = tempDir.appendingPathComponent("spawner.sh")
    let writes = tempDir.appendingPathComponent("writes.txt")

    try """
    #!/bin/sh
    (
        i=0
        while [ "$i" -lt 10000 ]; do
            echo "$i" >> "\(writes.path)"
            i=$((i + 1))
            sleep 0.02
        done
    ) &
    sleep 10
    """.write(to: script, atomically: true, encoding: .utf8)
    try makeExecutable(script)

    let runner = ScriptRunner(timeout: 0.5)
    let result = try runner.run(path: script.path, arguments: "")

    try assertTrue(result.timedOut, "script should time out")

    func lineCount() throws -> Int {
        guard FileManager.default.fileExists(atPath: writes.path) else { return 0 }
        let content = try String(contentsOf: writes, encoding: .utf8)
        return content.isEmpty ? 0 : content.components(separatedBy: "\n").filter { !$0.isEmpty }.count
    }

    // Give a surviving descendant the chance to keep writing, then verify it stopped.
    Thread.sleep(forTimeInterval: 0.3)
    let countAfterKill = try lineCount()
    try assertTrue(countAfterKill > 0, "descendant should have written before the kill")
    Thread.sleep(forTimeInterval: 0.3)
    try assertEqual(try lineCount(), countAfterKill, "descendant process kept writing after timeout kill")
}

func testArgumentParserHonorsQuotedValues() throws {
    let arguments = try CommandLineArgumentParser.parse("one 'two words' \"three words\" escaped\\ space")

    try assertEqual(arguments, ["one", "two words", "three words", "escaped space"], "parsed arguments")
}

func testArgumentParserRejectsUnbalancedQuotes() throws {
    var threw = false
    do {
        _ = try CommandLineArgumentParser.parse("hello 'world")
    } catch let error as ScriptRunnerError {
        threw = true
        try assertTrue(error == .unbalancedQuote, "expected unbalancedQuote error")
    }
    try assertTrue(threw, "unbalanced single quote should throw")

    threw = false
    do {
        _ = try CommandLineArgumentParser.parse("hello \"world")
    } catch let error as ScriptRunnerError {
        threw = true
        try assertTrue(error == .unbalancedQuote, "expected unbalancedQuote error")
    }
    try assertTrue(threw, "unbalanced double quote should throw")
}

func testArgumentParserHandlesEmptyAndWhitespaceInput() throws {
    try assertEqual(try CommandLineArgumentParser.parse(""), [], "empty string")
    try assertEqual(try CommandLineArgumentParser.parse("   "), [], "whitespace only")
    try assertEqual(try CommandLineArgumentParser.parse("  \t\n  "), [], "mixed whitespace")
}

func testArgumentParserHandlesEmptyQuotedStrings() throws {
    try assertEqual(try CommandLineArgumentParser.parse("'' \"\""), ["", ""], "empty quoted strings")
    try assertEqual(try CommandLineArgumentParser.parse("a '' b"), ["a", "", "b"], "empty quoted string between args")
}

func testRunnerPassesEnvironmentVariables() throws {
    let tempDir = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let script = tempDir.appendingPathComponent("env.sh")
    let output = tempDir.appendingPathComponent("env.txt")

    try """
    #!/bin/sh
    printf '%s' "$THEME_MODE" > "\(output.path)"
    """.write(to: script, atomically: true, encoding: .utf8)
    try makeExecutable(script)

    let runner = ScriptRunner(timeout: 2)
    let result = try runner.run(path: script.path, arguments: "", environment: ["THEME_MODE": "dark"])

    try assertEqual(result.exitCode, 0, "script exit code")
    try assertEqual(try String(contentsOf: output, encoding: .utf8), "dark", "THEME_MODE env var")
}

func makeTemporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("ThemeSyncTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

func makeExecutable(_ url: URL) throws {
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
}

@main
struct TestRunner {
    static func main() throws {
        let tests: [(String, () throws -> Void)] = [
            ("testShellMetacharactersArePassedAsArguments", testShellMetacharactersArePassedAsArguments),
            ("testRunnerTerminatesProcessAfterTimeout", testRunnerTerminatesProcessAfterTimeout),
            ("testTimeoutKillsDescendantProcesses", testTimeoutKillsDescendantProcesses),
            ("testArgumentParserHonorsQuotedValues", testArgumentParserHonorsQuotedValues),
            ("testArgumentParserRejectsUnbalancedQuotes", testArgumentParserRejectsUnbalancedQuotes),
            ("testArgumentParserHandlesEmptyAndWhitespaceInput", testArgumentParserHandlesEmptyAndWhitespaceInput),
            ("testArgumentParserHandlesEmptyQuotedStrings", testArgumentParserHandlesEmptyQuotedStrings),
            ("testRunnerPassesEnvironmentVariables", testRunnerPassesEnvironmentVariables),
        ]

        for (name, test) in tests {
            do {
                try test()
                print("PASS \(name)")
            } catch {
                print("FAIL \(name): \(error)")
                throw error
            }
        }
    }
}
