import Foundation

// Keep test preferences in memory instead of touching the app's saved settings.
final class MemoryDefaults: UserDefaults, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Any]
    let acknowledged = DispatchSemaphore(value: 0)

    init(values: [String: Any] = [:]) {
        self.values = values
        super.init(suiteName: "ThemeSyncTests-\(UUID().uuidString)")!
    }

    override func object(forKey key: String) -> Any? {
        lock.lock()
        defer { lock.unlock() }
        return values[key]
    }

    override func string(forKey key: String) -> String? {
        object(forKey: key) as? String
    }

    override func bool(forKey key: String) -> Bool {
        object(forKey: key) as? Bool ?? false
    }

    override func set(_ value: Any?, forKey key: String) {
        lock.lock()
        defer { lock.unlock() }
        values[key] = value
    }

    override func removeObject(forKey key: String) {
        lock.lock()
        values.removeValue(forKey: key)
        lock.unlock()
        if key == DefaultsKeys.pendingThemeChange { acknowledged.signal() }
    }

    func snapshot() -> [String: Any] {
        lock.lock()
        defer { lock.unlock() }
        return values
    }
}

final class RunRecorder {
    private let lock = NSLock()
    private var modes: [Bool] = []
    let started = DispatchSemaphore(value: 0)

    @discardableResult
    func record(_ isDark: Bool) -> Int {
        lock.lock()
        let index = modes.count
        modes.append(isDark)
        lock.unlock()
        started.signal()
        return index
    }

    func snapshot() -> [Bool] {
        lock.lock()
        defer { lock.unlock() }
        return modes
    }
}

func awaitSignal(_ semaphore: DispatchSemaphore, _ message: String) throws {
    try assertTrue(semaphore.wait(timeout: .now() + 3) == .success, message)
}

func testSchedulerSkipsUnchangedThemeAfterCompletedRun() throws {
    let defaults = MemoryDefaults()
    let firstRuns = RunRecorder()
    let first = ThemeScriptScheduler(defaults: defaults) { firstRuns.record($0) }
    first.start(isDark: true)
    try awaitSignal(defaults.acknowledged, "initial theme run should finish")
    try assertEqual(firstRuns.snapshot(), [true], "initial theme run")

    let restartedRuns = RunRecorder()
    let restarted = ThemeScriptScheduler(defaults: defaults) { restartedRuns.record($0) }
    restarted.start(isDark: true)
    restarted.themeDidChange(isDark: true)
    restarted.runManually(isDark: false)
    try awaitSignal(restartedRuns.started, "manual run should execute")
    try assertEqual(restartedRuns.snapshot(), [false], "unchanged theme should not rerun on restart")
    try assertTrue(defaults.object(forKey: DefaultsKeys.pendingThemeChange) == nil, "completed run should clear recovery")
}

func testSchedulerRecoversQueuedThemeAfterRestart() throws {
    let defaults = MemoryDefaults()
    let firstRuns = RunRecorder()
    let release = DispatchSemaphore(value: 0)
    defer { release.signal() }
    let first = ThemeScriptScheduler(defaults: defaults) { isDark in
        if firstRuns.record(isDark) == 0 { release.wait() }
    }
    first.start(isDark: true)
    try awaitSignal(firstRuns.started, "first run should start")
    first.themeDidChange(isDark: false)
    try assertEqual(firstRuns.snapshot(), [true], "light mode should still be queued")
    let saved = defaults.snapshot()

    // Recreate the scheduler from preferences saved before the queued run began.
    // Recovery follows the current system theme, including a change while closed.
    for currentMode in [false, true] {
        let restored = MemoryDefaults(values: saved)
        let runs = RunRecorder()
        let restarted = ThemeScriptScheduler(defaults: restored) { runs.record($0) }
        restarted.start(isDark: currentMode)
        try awaitSignal(restored.acknowledged, "unfinished theme should run after restart")
        try assertEqual(runs.snapshot(), [currentMode], "recovery should use the current system theme")
        try assertTrue(restored.object(forKey: DefaultsKeys.pendingThemeChange) == nil, "recovered run should be acknowledged")
    }
}

func testSchedulerKeepsNewerThemePendingWhenOlderRunCompletes() throws {
    let defaults = MemoryDefaults()
    let runs = RunRecorder()
    let release = DispatchSemaphore(value: 0)
    defer { release.signal(); release.signal() }
    let scheduler = ThemeScriptScheduler(defaults: defaults) { isDark in
        runs.record(isDark)
        release.wait()
    }
    scheduler.start(isDark: true)
    try awaitSignal(runs.started, "dark script should start")
    scheduler.themeDidChange(isDark: false)
    release.signal()
    try awaitSignal(runs.started, "queued light script should start")
    try assertTrue(defaults.object(forKey: DefaultsKeys.pendingThemeChange) != nil, "older completion must not clear newer recovery")
    release.signal()
    try awaitSignal(defaults.acknowledged, "newest run should finish")
    try assertEqual(runs.snapshot(), [true, false], "theme changes should run serially")
}

func testSchedulerRecoversInProgressThemeAfterRestart() throws {
    let defaults = MemoryDefaults()
    let firstRuns = RunRecorder()
    let release = DispatchSemaphore(value: 0)
    defer { release.signal() }
    let first = ThemeScriptScheduler(defaults: defaults) { isDark in
        firstRuns.record(isDark)
        release.wait()
    }
    first.start(isDark: true)
    try awaitSignal(firstRuns.started, "theme script should be running")

    let restored = MemoryDefaults(values: defaults.snapshot())
    let recoveredRuns = RunRecorder()
    let restarted = ThemeScriptScheduler(defaults: restored) { recoveredRuns.record($0) }
    restarted.start(isDark: true)
    try awaitSignal(restored.acknowledged, "interrupted in-progress script should be retried")
    try assertEqual(recoveredRuns.snapshot(), [true], "same theme should recover an interrupted run")
}

func testSchedulerCoalescesLatestThemeAndIgnoresDuplicates() throws {
    let defaults = MemoryDefaults()
    let runs = RunRecorder()
    let release = DispatchSemaphore(value: 0)
    defer { release.signal() }
    let scheduler = ThemeScriptScheduler(defaults: defaults) { isDark in
        if runs.record(isDark) == 0 { release.wait() }
    }
    scheduler.start(isDark: true)
    try awaitSignal(runs.started, "first run should start")
    scheduler.themeDidChange(isDark: true)
    scheduler.themeDidChange(isDark: false)
    scheduler.themeDidChange(isDark: true)
    scheduler.themeDidChange(isDark: false)
    scheduler.themeDidChange(isDark: false)
    release.signal()
    try awaitSignal(defaults.acknowledged, "latest theme should finish")
    try assertEqual(runs.snapshot(), [true, false], "only the latest queued theme should execute")
}

func testSchedulerManualRunsPreserveQueuedThemeChanges() throws {
    let defaults = MemoryDefaults()
    let runs = RunRecorder()
    let release = DispatchSemaphore(value: 0)
    defer { release.signal() }
    let scheduler = ThemeScriptScheduler(defaults: defaults) { isDark in
        if runs.record(isDark) == 0 { release.wait() }
    }
    scheduler.start(isDark: true)
    try awaitSignal(runs.started, "first run should start")
    scheduler.themeDidChange(isDark: false)
    scheduler.runManually(isDark: false)
    scheduler.runManually(isDark: true)
    release.signal()
    try awaitSignal(runs.started, "automatic light script should run")
    try awaitSignal(runs.started, "latest manual script should run")
    try awaitSignal(defaults.acknowledged, "automatic change should finish")
    try assertEqual(runs.snapshot(), [true, false, true], "manual coalescing must preserve the automatic change")
    try assertFalse(defaults.bool(forKey: DefaultsKeys.lastIsDark), "manual run must not change the observed theme")
}

func testSchedulerManualRunDoesNotAcknowledgeInterruptedThemeChange() throws {
    let defaults = MemoryDefaults(values: [
        DefaultsKeys.lastIsDark: true,
        DefaultsKeys.pendingThemeChange: "interrupted-run"
    ])
    let runs = RunRecorder()
    let scheduler = ThemeScriptScheduler(defaults: defaults) { runs.record($0) }
    scheduler.runManually(isDark: false)
    try awaitSignal(runs.started, "manual light script should run")
    scheduler.runManually(isDark: true)
    try awaitSignal(runs.started, "next manual script should run")
    try assertEqual(defaults.string(forKey: DefaultsKeys.pendingThemeChange), "interrupted-run", "manual completion must not acknowledge automatic work")
    try assertTrue(defaults.bool(forKey: DefaultsKeys.lastIsDark), "manual run must not change the observed theme")
}
