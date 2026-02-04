import SwiftUI
import AppKit

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
        guard !trimmed.isEmpty else { return }

        let escapedPath = shellEscape(trimmed)
        let trimmedArgs = args.trimmingCharacters(in: .whitespacesAndNewlines)
        let command = trimmedArgs.isEmpty ? escapedPath : "\(escapedPath) \(trimmedArgs)"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", command]

        do {
            try process.run()
        } catch {
            print("ThemeScriptRunner: failed to run \(isDark ? "dark" : "light") script: \(error)")
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
        appMenu.addItem(withTitle: "Quit Theme Script Runner", action: #selector(quitApp), keyEquivalent: "q")
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
        window.title = "Theme Script Runner"
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
    }

    private func pickScriptPath(current: String) -> String {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.title = "Choose Script"
        panel.prompt = "Choose"

        if !current.isEmpty {
            panel.directoryURL = URL(fileURLWithPath: current).deletingLastPathComponent()
        }

        let response = panel.runModal()
        guard response == .OK, let url = panel.url else { return current }
        return url.path
    }
}
