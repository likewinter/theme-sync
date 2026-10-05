import Darwin
import Foundation

func testRunnerCapturesStandardOutputAndError() throws {
    let result = try ScriptRunner(timeout: 2).run(
        path: "/bin/sh", arguments: "-c 'printf stdout; printf stderr >&2; exit 7'"
    )
    try assertEqual(result.exitCode, 7, "nonzero status should be preserved")
    try assertEqual(result.output, "stdoutstderr", "both output streams should be captured")
    try assertFalse(result.outputTruncated, "short output should be complete")
}

func testRunnerBoundsVerboseOutputAndKeepsItsTail() throws {
    let result = try ScriptRunner(timeout: 3).run(
        path: "/bin/sh",
        arguments: "-c 'i=0; while [ $i -lt 6000 ]; do printf 0123456789012345678901234567890123456789; i=$((i + 1)); done; printf FINAL-MARKER'"
    )
    try assertEqual(result.exitCode, 0, "verbose script should finish without filling its pipe")
    try assertFalse(result.timedOut, "output capture should not deadlock")
    try assertTrue(result.outputTruncated, "large output should be truncated")
    try assertTrue(result.output.utf8.count <= 64 * 1024, "retained output should be bounded")
    try assertTrue(result.output.hasSuffix("FINAL-MARKER"), "the most recent output should be retained")
}

func testRunnerDoesNotWaitForBackgroundChildOutputToClose() throws {
    let started = Date()
    let result = try ScriptRunner(timeout: 0.5).run(
        path: "/bin/sh", arguments: "-c 'sleep 2 & printf finished; exit 0'"
    )
    try assertEqual(result.exitCode, 0, "foreground script should finish")
    try assertFalse(result.timedOut, "an inherited output handle must not cause a timeout")
    try assertEqual(result.output, "finished", "available output should be returned")
    try assertTrue(Date().timeIntervalSince(started) < 1.5, "output collection waited for a background child")
}

func testContinuousOutputDoesNotPreventTimeout() throws {
    let started = Date()
    let result = try ScriptRunner(timeout: 0.2).run(
        path: "/bin/sh", arguments: "-c 'trap \"\" TERM; while :; do printf 0123456789; done'"
    )
    try assertTrue(result.timedOut, "continuously writing script should time out")
    try assertEqual(result.exitCode, SIGKILL, "SIGTERM-resistant writer should be killed")
    try assertTrue(Date().timeIntervalSince(started) < 3, "output draining delayed timeout cleanup")
}

func testConfiguredRunPreservesArgumentsAndThemeEnvironment() throws {
    let temp = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: temp) }
    let script = temp.appendingPathComponent("script with spaces.sh")
    try """
    #!/bin/sh
    printf '%s|%s' "$THEME_MODE" "$1"
    """.write(to: script, atomically: true, encoding: .utf8)
    try makeExecutable(script)
    let defaults = MemoryDefaults(values: [
        DefaultsKeys.lightPath: "  \(script.path)  ",
        DefaultsKeys.lightArgs: "value\\ "
    ])
    let configuration = ScriptConfiguration(isDark: false, defaults: defaults)
    let report = ScriptRunner(timeout: 2).run(configuration: configuration, isDark: false)
    try assertTrue(report.succeeded, "configured script should succeed")
    try assertEqual(report.output, "light|value ", "configured arguments must preserve escaped whitespace")
    try assertEqual(report.menuTitle, "Last run: Light · succeeded", "successful menu title")
    try assertTrue(report.summary.hasPrefix("Succeeded in "), "inline feedback should include elapsed time")
}

func testInvalidArgumentsAreReportedWithoutExecutingScript() throws {
    let temp = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: temp) }
    let script = temp.appendingPathComponent("must-not-run.sh")
    let marker = temp.appendingPathComponent("ran")
    try """
    #!/bin/sh
    touch "\(marker.path)"
    """.write(to: script, atomically: true, encoding: .utf8)
    try makeExecutable(script)
    let report = ScriptRunner().run(
        configuration: ScriptConfiguration(path: script.path, arguments: "'unfinished"), isDark: true
    )
    try assertFalse(report.succeeded, "invalid arguments must fail")
    try assertTrue(report.errorMessage?.contains("unbalanced quote") == true, "argument error should be actionable")
    try assertFalse(FileManager.default.fileExists(atPath: marker.path), "invalid command must not execute")
    try assertEqual(report.menuTitle, "Last run: Dark · could not run", "validation failure menu title")
}

func testExecutionReportsDescribeFailuresAndTimeouts() throws {
    let temp = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: temp) }
    let script = temp.appendingPathComponent("failure.sh")
    try """
    #!/bin/sh
    printf 'useful error' >&2
    exit 7
    """.write(to: script, atomically: true, encoding: .utf8)
    try makeExecutable(script)
    let failure = ScriptRunner(timeout: 2).run(configuration: ScriptConfiguration(path: script.path, arguments: ""), isDark: true)
    try assertEqual(failure.summary, "Failed with exit code 7.", "failure feedback")
    try assertTrue(failure.details.contains("useful error"), "failure details should include stderr")

    try """
    #!/bin/sh
    printf 'started'
    exec /bin/sleep 10
    """.write(to: script, atomically: true, encoding: .utf8)
    let timeout = ScriptRunner(timeout: 0.2).run(configuration: ScriptConfiguration(path: script.path, arguments: ""), isDark: false)
    try assertTrue(timeout.timedOut, "configured run should report timeouts")
    try assertEqual(timeout.menuTitle, "Last run: Light · timed out", "timeout menu title")
    try assertEqual(timeout.summary, "Timed out after 0.2 s.", "fractional timeout should not be rounded to zero")
    try assertTrue(timeout.details.contains("started"), "timeout should preserve partial output")
}

func testExecutionReportCanBeRestoredWithoutLosingDetails() throws {
    let report = ScriptRunner().run(configuration: ScriptConfiguration(path: "/missing/script", arguments: "'two words'"), isDark: true)
    let restored = try JSONDecoder().decode(ScriptRunReport.self, from: JSONEncoder().encode(report))
    try assertEqual(restored, report, "saved last run should retain all report fields")
    try assertEqual(restored.details, report.details, "restored details should remain available")
    try assertTrue(restored.errorMessage?.contains("File not found") == true, "missing script should have a clear error")
}

func testConfigurationRejectsDirectoriesAndNonExecutableFiles() throws {
    let temp = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: temp) }
    try assertEqual(ScriptConfiguration(path: temp.path, arguments: "").problem, "Choose a script file, not a folder.", "directory validation")
    let script = temp.appendingPathComponent("not-executable.sh")
    try "#!/bin/sh\n".write(to: script, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: script.path)
    try assertTrue(ScriptConfiguration(path: script.path, arguments: "").problem?.contains("not executable") == true, "execute permissions should be checked")
}

func testSchedulerUsesManualConfigurationCapturedWhenRequested() throws {
    let temp = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: temp) }
    let script = temp.appendingPathComponent("record.sh")
    let output = temp.appendingPathComponent("argument.txt")
    try """
    #!/bin/sh
    printf '%s' "$1" > "\(output.path)"
    """.write(to: script, atomically: true, encoding: .utf8)
    try makeExecutable(script)
    let defaults = MemoryDefaults(values: [DefaultsKeys.darkPath: script.path, DefaultsKeys.darkArgs: "original"])
    let started = DispatchSemaphore(value: 0)
    let release = DispatchSemaphore(value: 0)
    let finished = DispatchSemaphore(value: 0)
    defer { release.signal() }
    let scheduler = ThemeScriptScheduler(defaults: defaults) { _ in
        started.signal()
        release.wait()
    }
    scheduler.start(isDark: true)
    try awaitSignal(started, "automatic run should start")
    let snapshot = ScriptConfiguration(isDark: true, defaults: defaults)
    scheduler.runManually(isDark: true) {
        _ = ScriptRunner(timeout: 2).run(configuration: snapshot, isDark: true)
        finished.signal()
    }
    defaults.set("edited", forKey: DefaultsKeys.darkArgs)
    release.signal()
    try awaitSignal(finished, "queued manual test should finish")
    try assertEqual(try String(contentsOf: output, encoding: .utf8), "original", "queued test must execute its original configuration")
}
