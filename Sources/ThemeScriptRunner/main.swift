import SwiftUI
import AppKit
import os.log

private enum DefaultsKeys {
    static let darkPath = "scriptPathDark"
    static let lightPath = "scriptPathLight"
    static let darkArgs = "scriptArgsDark"
    static let lightArgs = "scriptArgsLight"
}

private final class ThemeWatcher: ObservableObject {
    @AppStorage(DefaultsKeys.darkPath) private var scriptPathDark: String = ""
    @AppStorage(DefaultsKeys.lightPath) private var scriptPathLight: String = ""
    @AppStorage(DefaultsKeys.darkArgs) private var scriptArgsDark: String = ""
    @AppStorage(DefaultsKeys.lightArgs) private var scriptArgsLight: String = ""

    private var observer: NSObjectProtocol?
    private var lastIsDark: Bool?
    private let logger = Logger(subsystem: "com.themeScriptRunner", category: "ThemeWatcher")

    func start() {
        updateAndRunIfNeeded(force: true)

        observer = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updateAndRunIfNeeded(force: false)
        }
    }

    deinit {
        if let observer = observer {
            DistributedNotificationCenter.default().removeObserver(observer)
        }
    }

    private func updateAndRunIfNeeded(force: Bool) {
        let isDark = isDarkMode()
        if !force, let lastIsDark = lastIsDark, lastIsDark == isDark {
            return
        }

        lastIsDark = isDark
        let path = isDark ? scriptPathDark : scriptPathLight
        let args = isDark ? scriptArgsDark : scriptArgsLight
        runScriptIfNeeded(path: path, args: args, isDark: isDark)
    }

    private func isDarkMode() -> Bool {
        let appearance = NSApp.effectiveAppearance
        let match = appearance.bestMatch(from: [.darkAqua, .aqua])
        return match == .darkAqua
    }

    private func runScriptIfNeeded(path: String, args: String, isDark: Bool) {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { 
            logger.debug("No script path configured for \(isDark ? "dark" : "light") mode")
            return 
        }
        
        // Validate script path exists and is executable
        guard FileManager.default.fileExists(atPath: trimmed) else {
            logger.error("Script not found: \(trimmed)")
            return
        }
        
        guard FileManager.default.isExecutableFile(atPath: trimmed) else {
            logger.error("Script is not executable: \(trimmed)")
            return
        }

        let escapedPath = shellEscape(trimmed)
        let trimmedArgs = args.trimmingCharacters(in: .whitespacesAndNewlines)
        let command = trimmedArgs.isEmpty ? escapedPath : "\(escapedPath) \(trimmedArgs)"
        
        logger.info("Running \(isDark ? "dark" : "light") mode script: \(trimmed)")
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", command]
        
        // Set timeout
        let timer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: false) { _ in
            if process.isRunning {
                process.terminate()
                self.logger.warning("Script execution timed out after 30 seconds: \(trimmed)")
            }
        }

        do {
            try process.run()
            process.waitUntilExit()
            timer.invalidate()
            
            let exitCode = process.terminationStatus
            if exitCode == 0 {
                logger.info("Script completed successfully: \(trimmed)")
            } else {
                logger.error("Script failed with exit code \(exitCode): \(trimmed)")
            }
        } catch {
            timer.invalidate()
            logger.error("Failed to run \(isDark ? "dark" : "light") script: \(error.localizedDescription)")
        }
    }

    private func shellEscape(_ input: String) -> String {
        let escaped = input.replacingOccurrences(of: "'", with: "'\\''")
        return "'\(escaped)'"
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
            button.image = NSImage(systemSymbolName: "circle.lefthalf.filled", accessibilityDescription: "Theme Scripts")
            button.imagePosition = .imageLeft
        }
        item.isVisible = true

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Open Settings", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q"))

        item.menu = menu
        statusItem = item
    }

    @objc private func openSettings() {
        if let window = settingsWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let hosting = NSHostingController(rootView: SettingsView())
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 180),
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
                print("Warning: \(name) script path does not exist: \(trimmed)")
            } else if !FileManager.default.isExecutableFile(atPath: trimmed) {
                print("Warning: \(name) script is not executable: \(trimmed)")
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
