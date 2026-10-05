import SwiftUI
import AppKit
import ServiceManagement
import os.log

private final class ThemeWatcher: ObservableObject {
    @Published private(set) var lastRun: ScriptRunReport? = {
        guard let data = UserDefaults.standard.data(forKey: DefaultsKeys.lastRun) else { return nil }
        return try? JSONDecoder().decode(ScriptRunReport.self, from: data)
    }()
    @Published private(set) var testStates: [Bool: ScriptTestState] = [:]
    @Published private(set) var isTesting = false

    private var observer: NSObjectProtocol?
    private let logger = Logger(subsystem: "com.likewinter.theme-sync", category: "ThemeWatcher")
    private let runner = ScriptRunner()
    private lazy var scheduler = ThemeScriptScheduler { [weak self] isDark in
        self?.executeScript(isDark: isDark)
    }

    var onModeChange: ((Bool) -> Void)?

    func start() {
        let isDark = isDarkMode()
        onModeChange?(isDark)
        scheduler.start(isDark: isDark)

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
        scheduler.themeDidChange(isDark: isDark)
    }

    func runForMode(isDark: Bool) {
        guard !isTesting else { return }
        let configuration = ScriptConfiguration(isDark: isDark)
        isTesting = true
        testStates[isDark] = .queued
        scheduler.runManually(isDark: isDark) { [weak self] in
            guard let self else { return }
            DispatchQueue.main.async { self.testStates[isDark] = .running }
            let report = self.runner.run(configuration: configuration, isDark: isDark)
            self.publish(report, isTest: true)
        }
    }

    private func isDarkMode() -> Bool {
        let appearance = NSApp.effectiveAppearance
        let match = appearance.bestMatch(from: [.darkAqua, .aqua])
        return match == .darkAqua
    }

    private func executeScript(isDark: Bool) {
        let configuration = ScriptConfiguration(isDark: isDark)
        guard !configuration.path.isEmpty else {
            logger.debug("No script path configured for \(isDark ? "dark" : "light") mode")
            return
        }

        logger.info("Running \(isDark ? "dark" : "light") mode script: \(configuration.path)")
        publish(runner.run(configuration: configuration, isDark: isDark), isTest: false)
    }

    private func publish(_ report: ScriptRunReport, isTest: Bool) {
        if report.succeeded {
            logger.info("Script completed: \(report.path)")
        } else {
            logger.error("Script did not succeed: \(report.summary)")
        }
        if let data = try? JSONEncoder().encode(report) {
            UserDefaults.standard.set(data, forKey: DefaultsKeys.lastRun)
        }
        DispatchQueue.main.async {
            self.lastRun = report
            if isTest {
                self.testStates[report.isDark] = .finished(report)
                self.isTesting = false
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private var settingsWindow: NSWindow?
    private let watcher = ThemeWatcher()
    private var lastRunItem: NSMenuItem?
    private var darkRunItem: NSMenuItem?
    private var lightRunItem: NSMenuItem?
    private var detailsPopover: NSPopover?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMainMenu()
        setupMenuBar()
        watcher.onModeChange = { [weak self] isDark in
            self?.updateIcon(isDark: isDark)
        }
        watcher.start()
        let defaults = UserDefaults.standard
        let isFirstLaunch = !defaults.bool(forKey: DefaultsKeys.hasLaunched)
        defaults.set(true, forKey: DefaultsKeys.hasLaunched)
        if isFirstLaunch && ScriptConfiguration(isDark: true).path.isEmpty && ScriptConfiguration(isDark: false).path.isEmpty {
            openSettings()
        }
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
        menu.delegate = self
        menu.addItem(NSMenuItem(title: "Open Settings", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(.separator())
        let lastRun = NSMenuItem(title: "No script has run yet", action: #selector(showLastRun), keyEquivalent: "")
        lastRun.target = self
        menu.addItem(lastRun)
        lastRunItem = lastRun
        let darkRun = NSMenuItem(title: "Run Dark Script", action: #selector(runDarkScript), keyEquivalent: "")
        let lightRun = NSMenuItem(title: "Run Light Script", action: #selector(runLightScript), keyEquivalent: "")
        darkRun.target = self
        lightRun.target = self
        menu.addItem(darkRun)
        menu.addItem(lightRun)
        darkRunItem = darkRun
        lightRunItem = lightRun
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q"))

        item.menu = menu
        statusItem = item
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        lastRunItem?.title = watcher.lastRun?.menuTitle ?? "No script has run yet"
    }

    @objc func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem === lastRunItem { return watcher.lastRun != nil }
        if menuItem === darkRunItem || menuItem === lightRunItem { return !watcher.isTesting }
        return true
    }

    @objc private func showLastRun() {
        guard let report = watcher.lastRun, let button = statusItem?.button else { return }
        detailsPopover?.close()
        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: RunDetailsView(report: report))
        popover.contentSize = NSSize(width: 460, height: 280)
        detailsPopover = popover
        // Let the menu finish closing before presenting the transient popover.
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
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

        let hosting = NSHostingController(rootView: SettingsView(watcher: watcher))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 580, height: 280),
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

private struct RunDetailsView: View {
    let report: ScriptRunReport

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("\(report.modeName) script · \(report.status)")
                .font(.headline)
            ScrollView {
                Text(report.details)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 220)
        }
        .padding(16)
        .frame(width: 460)
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
    @ObservedObject var watcher: ThemeWatcher
    @AppStorage(DefaultsKeys.darkPath) private var scriptPathDark: String = ""
    @AppStorage(DefaultsKeys.lightPath) private var scriptPathLight: String = ""
    @AppStorage(DefaultsKeys.darkArgs) private var scriptArgsDark: String = ""
    @AppStorage(DefaultsKeys.lightArgs) private var scriptArgsLight: String = ""
    @State private var loginEnabled = false
    @State private var loginError: String?
    @State private var loginNeedsApproval = false

    private let logger = Logger(subsystem: "com.likewinter.theme-sync", category: "Settings")

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text("Script on Dark").frame(width: 100, alignment: .leading)
                    TextField("", text: $scriptPathDark)
                        .accessibilityLabel("Dark script path")
                    Button("Choose…") { scriptPathDark = pickScriptPath(current: scriptPathDark) }
                    Button("Test") { watcher.runForMode(isDark: true) }
                        .disabled(watcher.isTesting || scriptPathDark.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .help("Run the dark script without changing system appearance.")
                        .accessibilityLabel("Test dark script")
                }
                HStack(spacing: 8) {
                    Text("Args on Dark").frame(width: 100, alignment: .leading)
                    TextField("", text: $scriptArgsDark)
                        .accessibilityLabel("Dark script arguments")
                }
                scriptFeedback(isDark: true)
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Dark mode script")
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text("Script on Light").frame(width: 100, alignment: .leading)
                    TextField("", text: $scriptPathLight)
                        .accessibilityLabel("Light script path")
                    Button("Choose…") { scriptPathLight = pickScriptPath(current: scriptPathLight) }
                    Button("Test") { watcher.runForMode(isDark: false) }
                        .disabled(watcher.isTesting || scriptPathLight.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .help("Run the light script without changing system appearance.")
                        .accessibilityLabel("Test light script")
                }
                HStack(spacing: 8) {
                    Text("Args on Light").frame(width: 100, alignment: .leading)
                    TextField("", text: $scriptArgsLight)
                        .accessibilityLabel("Light script arguments")
                }
                scriptFeedback(isDark: false)
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Light mode script")
            Text("Scripts receive THEME_MODE=dark or THEME_MODE=light as an environment variable.")
                .font(.caption)
                .foregroundColor(.secondary)
            Divider()
            Toggle("Launch at Login", isOn: Binding(
                get: { loginEnabled },
                set: updateLaunchAtLogin
            ))
            if let loginError {
                Label(loginError, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundColor(.red)
                    .fixedSize(horizontal: false, vertical: true)
            } else if loginNeedsApproval {
                HStack(alignment: .firstTextBaseline) {
                    Text("Allow ThemeSync in System Settings to enable launch at login.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Button("Open System Settings") { SMAppService.openSystemSettingsLoginItems() }
                        .buttonStyle(.link)
                }
            }
        }
        .padding(20)
        .frame(width: 580)
        .onAppear(perform: refreshLoginStatus)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshLoginStatus()
        }
    }

    @ViewBuilder
    private func scriptFeedback(isDark: Bool) -> some View {
        let configuration = ScriptConfiguration(
            path: isDark ? scriptPathDark : scriptPathLight,
            arguments: isDark ? scriptArgsDark : scriptArgsLight
        )
        VStack(alignment: .leading, spacing: 0) {
            if let state = watcher.testStates[isDark] {
                switch state {
                case .queued:
                    Text("Waiting for the current script to finish…").foregroundColor(.secondary)
                case .running:
                    Text("Testing \(isDark ? "dark" : "light") script…").foregroundColor(.secondary)
                case .finished(let report):
                    if report.path == configuration.path && report.arguments == configuration.arguments {
                        Text(report.summary).foregroundColor(report.succeeded ? .secondary : .red)
                            .textSelection(.enabled)
                    } else if !configuration.path.isEmpty, let problem = configuration.problem {
                        Text(problem).foregroundColor(.red)
                    }
                }
            } else if !configuration.path.isEmpty, let problem = configuration.problem {
                Text(problem).foregroundColor(.red)
            }
        }
        .font(.caption)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.leading, 108)
    }

    private func refreshLoginStatus() {
        let status = SMAppService.mainApp.status
        loginEnabled = status == .enabled || status == .requiresApproval
        loginNeedsApproval = status == .requiresApproval
    }

    private func updateLaunchAtLogin(_ enabled: Bool) {
        loginError = nil
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            loginError = "Could not update launch at login: \(error.localizedDescription)"
            logger.error("Failed to update launch at login: \(error.localizedDescription)")
        }
        refreshLoginStatus()
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
