import SwiftUI
import AppKit
import ServiceManagement
import os.log

private enum DefaultsKeys {
    static let darkPath = "scriptPathDark"
    static let lightPath = "scriptPathLight"
    static let darkArgs = "scriptArgsDark"
    static let lightArgs = "scriptArgsLight"
    static let lastIsDark = "lastIsDark"
}

private final class ThemeWatcher: ObservableObject {
    private var observer: NSObjectProtocol?
    private let logger = Logger(subsystem: "com.themeScriptRunner", category: "ThemeWatcher")
    private let runner = ScriptRunner()
    private let executionQueue = DispatchQueue(label: "ThemeSync.ScriptRunner", qos: .utility)

    // Coalescing state: requests arriving while a script runs collapse to the
    // latest mode, which executes once the current run finishes.
    private let stateLock = NSLock()
    private var pendingMode: Bool?
    private var isExecuting = false

    var onModeChange: ((Bool) -> Void)?

    private var scriptPathDark: String {
        UserDefaults.standard.string(forKey: DefaultsKeys.darkPath) ?? ""
    }
    private var scriptPathLight: String {
        UserDefaults.standard.string(forKey: DefaultsKeys.lightPath) ?? ""
    }
    private var scriptArgsDark: String {
        UserDefaults.standard.string(forKey: DefaultsKeys.darkArgs) ?? ""
    }
    private var scriptArgsLight: String {
        UserDefaults.standard.string(forKey: DefaultsKeys.lightArgs) ?? ""
    }
    private var lastIsDark: Bool? {
        get {
            guard UserDefaults.standard.object(forKey: DefaultsKeys.lastIsDark) != nil else { return nil }
            return UserDefaults.standard.bool(forKey: DefaultsKeys.lastIsDark)
        }
        set {
            if let newValue {
                UserDefaults.standard.set(newValue, forKey: DefaultsKeys.lastIsDark)
            } else {
                UserDefaults.standard.removeObject(forKey: DefaultsKeys.lastIsDark)
            }
        }
    }

    func start() {
        let isDark = isDarkMode()
        onModeChange?(isDark)
        if lastIsDark != isDark {
            lastIsDark = isDark
            runForMode(isDark: isDark)
        }

        observer = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updateAndRunIfNeeded()
        }
    }

    deinit {
        if let observer = observer {
            DistributedNotificationCenter.default().removeObserver(observer)
        }
    }

    private func updateAndRunIfNeeded() {
        let isDark = isDarkMode()
        onModeChange?(isDark)
        if lastIsDark == isDark { return }

        lastIsDark = isDark
        runForMode(isDark: isDark)
    }

    func runForMode(isDark: Bool) {
        stateLock.lock()
        pendingMode = isDark
        let shouldStart = !isExecuting
        if shouldStart { isExecuting = true }
        stateLock.unlock()

        guard shouldStart else { return }

        executionQueue.async { [weak self] in
            guard let self else { return }
            while let isDark = self.takePendingMode() {
                self.executeScript(isDark: isDark)
            }
        }
    }

    private func takePendingMode() -> Bool? {
        stateLock.lock()
        defer { stateLock.unlock() }
        guard let isDark = pendingMode else {
            isExecuting = false
            return nil
        }
        pendingMode = nil
        return isDark
    }

    private func isDarkMode() -> Bool {
        let appearance = NSApp.effectiveAppearance
        let match = appearance.bestMatch(from: [.darkAqua, .aqua])
        return match == .darkAqua
    }

    private func executeScript(isDark: Bool) {
        let path = (isDark ? scriptPathDark : scriptPathLight).trimmingCharacters(in: .whitespacesAndNewlines)
        let args = (isDark ? scriptArgsDark : scriptArgsLight).trimmingCharacters(in: .whitespacesAndNewlines)

        guard !path.isEmpty else {
            logger.debug("No script path configured for \(isDark ? "dark" : "light") mode")
            return
        }

        // Validate script path exists and is executable
        guard FileManager.default.fileExists(atPath: path) else {
            logger.error("Script not found: \(path)")
            return
        }

        guard FileManager.default.isExecutableFile(atPath: path) else {
            logger.error("Script is not executable: \(path)")
            return
        }

        logger.info("Running \(isDark ? "dark" : "light") mode script: \(path)")

        do {
            let result = try runner.run(
                path: path,
                arguments: args,
                environment: ["THEME_MODE": isDark ? "dark" : "light"]
            )

            if result.timedOut {
                logger.warning("Script execution timed out after 30 seconds: \(path)")
            } else if result.exitCode == 0 {
                logger.info("Script completed successfully: \(path)")
            } else if result.terminatedBySignal {
                logger.error("Script killed by signal \(result.exitCode): \(path)")
            } else {
                logger.error("Script failed with exit code \(result.exitCode): \(path)")
            }
        } catch {
            logger.error("Failed to run \(isDark ? "dark" : "light") script: \(error.localizedDescription)")
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var settingsWindow: NSWindow?
    private let watcher = ThemeWatcher()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)
        setupMainMenu()
        setupMenuBar()
        watcher.onModeChange = { [weak self] isDark in
            self?.updateIcon(isDark: isDark)
        }
        watcher.start()
    }

    private func setupMainMenu() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit ThemeSync", action: #selector(quitApp), keyEquivalent: "q")
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        NSApp.mainMenu = mainMenu
    }

    private func setupMenuBar() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.title = "TS"
            button.imagePosition = .imageLeft
        }
        item.isVisible = true

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Open Settings", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Run Dark Script", action: #selector(runDarkScript), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Run Light Script", action: #selector(runLightScript), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q"))

        item.menu = menu
        statusItem = item
    }

    private func updateIcon(isDark: Bool) {
        let symbolName = isDark ? "moon.fill" : "sun.max.fill"
        statusItem?.button?.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: isDark ? "Dark mode" : "Light mode")
    }

    @objc private func runDarkScript() {
        watcher.runForMode(isDark: true)
    }

    @objc private func runLightScript() {
        watcher.runForMode(isDark: false)
    }

    @objc private func openSettings() {
        if let window = settingsWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let hosting = NSHostingController(rootView: SettingsView())
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 180),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.center()
        window.contentViewController = hosting
        window.title = "ThemeSync"
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow = window
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}

@main
struct MainApp {
    static let delegate = AppDelegate()

    static func main() {
        let app = NSApplication.shared
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}

private struct SettingsView: View {
    @AppStorage(DefaultsKeys.darkPath) private var scriptPathDark: String = ""
    @AppStorage(DefaultsKeys.lightPath) private var scriptPathLight: String = ""
    @AppStorage(DefaultsKeys.darkArgs) private var scriptArgsDark: String = ""
    @AppStorage(DefaultsKeys.lightArgs) private var scriptArgsLight: String = ""

    private let logger = Logger(subsystem: "com.themeScriptRunner", category: "Settings")

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Text("Script on Dark")
                TextField("", text: $scriptPathDark)
                Button("Choose…") { scriptPathDark = pickScriptPath(current: scriptPathDark) }
            }
            HStack(spacing: 8) {
                Text("Args on Dark")
                TextField("", text: $scriptArgsDark)
            }
            HStack(spacing: 8) {
                Text("Script on Light")
                TextField("", text: $scriptPathLight)
                Button("Choose…") { scriptPathLight = pickScriptPath(current: scriptPathLight) }
            }
            HStack(spacing: 8) {
                Text("Args on Light")
                TextField("", text: $scriptArgsLight)
            }
            Text("Scripts receive THEME_MODE=dark or THEME_MODE=light as an environment variable.")
                .font(.caption)
                .foregroundColor(.secondary)
            Divider()
            Toggle("Launch at Login", isOn: Binding(
                get: { SMAppService.mainApp.status == .enabled },
                set: { enabled in
                    do {
                        if enabled {
                            try SMAppService.mainApp.register()
                        } else {
                            try SMAppService.mainApp.unregister()
                        }
                    } catch {
                        logger.error("Failed to update launch at login: \(error.localizedDescription)")
                    }
                }
            ))
        }
        .padding(20)
        .frame(minWidth: 520)
        .onAppear {
            // Validate existing paths on settings open
            validateScriptPaths()
        }
    }
    
    private func validateScriptPaths() {
        for (path, name) in [(scriptPathDark, "Dark"), (scriptPathLight, "Light")] {
            let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            
            if !FileManager.default.fileExists(atPath: trimmed) {
                logger.warning("\(name) script path does not exist: \(trimmed)")
            } else if !FileManager.default.isExecutableFile(atPath: trimmed) {
                logger.warning("\(name) script is not executable: \(trimmed)")
            }
        }
    }

    private func pickScriptPath(current: String) -> String {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.title = "Choose Script"
        panel.prompt = "Choose"
        panel.allowedContentTypes = [.shellScript, .executable]

        if !current.isEmpty {
            let url = URL(fileURLWithPath: current)
            if FileManager.default.fileExists(atPath: current) {
                panel.directoryURL = url.deletingLastPathComponent()
            }
        }

        let response = panel.runModal()
        guard response == .OK, let url = panel.url else { return current }
        
        // Validate the selected file is executable
        let path = url.path
        if !FileManager.default.isExecutableFile(atPath: path) {
            // Show alert about non-executable file
            let alert = NSAlert()
            alert.messageText = "File Not Executable"
            alert.informativeText = "The selected file is not executable. Please choose an executable script or make the file executable."
            alert.alertStyle = .warning
            alert.runModal()
            return current
        }
        
        return path
    }
}
