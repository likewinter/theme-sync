import Foundation

enum DefaultsKeys {
    static let darkPath = "scriptPathDark"
    static let lightPath = "scriptPathLight"
    static let darkArgs = "scriptArgsDark"
    static let lightArgs = "scriptArgsLight"
    static let lastIsDark = "lastIsDark"
    static let pendingThemeChange = "pendingThemeChange"
}

final class ThemeScriptScheduler {
    private struct Request {
        let isDark: Bool
        let themeChangeID: String?
    }

    private let defaults: UserDefaults
    private let execute: (Bool) -> Void
    private let queue = DispatchQueue(label: "ThemeSync.ScriptRunner", qos: .utility)
    private let lock = NSLock()
    private var pending: [Request] = []
    private var isExecuting = false

    init(defaults: UserDefaults = .standard, execute: @escaping (Bool) -> Void) {
        self.defaults = defaults
        self.execute = execute
    }

    func start(isDark: Bool) {
        requestTheme(isDark: isDark, recoverPending: true)
    }

    func themeDidChange(isDark: Bool) {
        requestTheme(isDark: isDark, recoverPending: false)
    }

    func runManually(isDark: Bool) {
        lock.lock()
        enqueue(Request(isDark: isDark, themeChangeID: nil))
        let shouldStart = beginExecutionIfNeeded()
        lock.unlock()
        if shouldStart { drainQueue() }
    }

    private func requestTheme(isDark: Bool, recoverPending: Bool) {
        lock.lock()
        let hasLastMode = defaults.object(forKey: DefaultsKeys.lastIsDark) != nil
        let sameMode = hasLastMode && defaults.bool(forKey: DefaultsKeys.lastIsDark) == isDark
        let needsRecovery = recoverPending && defaults.object(forKey: DefaultsKeys.pendingThemeChange) != nil
        guard !sameMode || needsRecovery else {
            lock.unlock()
            return
        }

        let requestID = UUID().uuidString
        // Record unfinished work before updating the observed theme. A restart
        // must recover the current theme even if the previous run never began.
        defaults.set(requestID, forKey: DefaultsKeys.pendingThemeChange)
        defaults.set(isDark, forKey: DefaultsKeys.lastIsDark)
        enqueue(Request(isDark: isDark, themeChangeID: requestID))
        let shouldStart = beginExecutionIfNeeded()
        lock.unlock()
        if shouldStart { drainQueue() }
    }

    private func enqueue(_ request: Request) {
        // Coalesce each source independently so a manual test cannot discard
        // an automatic theme change. At most two requests remain queued.
        pending.removeAll { ($0.themeChangeID == nil) == (request.themeChangeID == nil) }
        pending.append(request)
    }

    private func beginExecutionIfNeeded() -> Bool {
        guard !isExecuting else { return false }
        isExecuting = true
        return true
    }

    private func drainQueue() {
        queue.async { [weak self] in
            guard let self else { return }
            while let request = self.takeNextRequest() {
                self.execute(request.isDark)
                self.complete(request)
            }
        }
    }

    private func takeNextRequest() -> Request? {
        lock.lock()
        defer { lock.unlock() }
        guard !pending.isEmpty else {
            isExecuting = false
            return nil
        }
        return pending.removeFirst()
    }

    private func complete(_ request: Request) {
        guard let requestID = request.themeChangeID else { return }
        lock.lock()
        defer { lock.unlock() }
        // An older run must not acknowledge a newer, still-queued change.
        if defaults.string(forKey: DefaultsKeys.pendingThemeChange) == requestID {
            defaults.removeObject(forKey: DefaultsKeys.pendingThemeChange)
        }
    }
}
