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

func testArgumentParserHonorsQuotedValues() throws {
    let arguments = try CommandLineArgumentParser.parse("one 'two words' \"three words\" escaped\\ space")

    try assertEqual(arguments, ["one", "two words", "three words", "escaped space"], "parsed arguments")
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
            ("testArgumentParserHonorsQuotedValues", testArgumentParserHonorsQuotedValues),
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
