import Cocoa

final class DeadPadAppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var window: NSWindow?
    private weak var statusLabel: NSTextField?
    private weak var startButton: NSButton?
    private weak var stopButton: NSButton?
    private weak var restartButton: NSButton?
    private weak var startAtLoginCheckbox: NSButton?
    private var task: Process?
    private var logHandle: FileHandle?
    private var logPath = ""
    private var restartAfterStop = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        prepareLogPath()
        buildStatusItem()
        updateAppState(status: "Stopped")
        startFilter(nil)
    }

    func applicationWillTerminate(_ notification: Notification) {
        restartAfterStop = false
        stopFilter(nil)
    }

    private func prepareLogPath() {
        let logsURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/DeadPad", isDirectory: true)

        try? FileManager.default.createDirectory(
            at: logsURL,
            withIntermediateDirectories: true
        )

        let logURL = logsURL.appendingPathComponent("deadpad.log")
        logPath = logURL.path

        if !FileManager.default.fileExists(atPath: logPath) {
            FileManager.default.createFile(atPath: logPath, contents: Data())
        }
    }

    private func buildStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem?.button?.title = "DP"
        statusItem?.button?.toolTip = "DeadPad"
        statusItem?.button?.target = self
        statusItem?.button?.action = #selector(showWindow(_:))
    }

    private func buildWindow() {
        if window != nil {
            return
        }

        let frame = NSRect(x: 0, y: 0, width: 360, height: 238)
        let window = NSWindow(
            contentRect: frame,
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "DeadPad"
        window.isReleasedWhenClosed = false
        window.center()
        self.window = window

        let content = window.contentView ?? NSView(frame: frame)
        window.contentView = content

        let titleLabel = label(
            frame: NSRect(x: 22, y: 190, width: 250, height: 24),
            text: "DeadPad",
            fontSize: 18,
            bold: true
        )
        content.addSubview(titleLabel)

        let statusLabel = label(
            frame: NSRect(x: 22, y: 166, width: 300, height: 20),
            text: "Status: Stopped",
            fontSize: 13,
            bold: false
        )
        content.addSubview(statusLabel)
        self.statusLabel = statusLabel

        let startAtLoginCheckbox = NSButton(frame: NSRect(x: 20, y: 130, width: 220, height: 24))
        startAtLoginCheckbox.setButtonType(.switch)
        startAtLoginCheckbox.title = "Start at login"
        startAtLoginCheckbox.target = self
        startAtLoginCheckbox.action = #selector(toggleStartAtLogin(_:))
        content.addSubview(startAtLoginCheckbox)
        self.startAtLoginCheckbox = startAtLoginCheckbox

        let startButton = button(
            frame: NSRect(x: 22, y: 86, width: 92, height: 30),
            title: "Start",
            action: #selector(startFilter(_:))
        )
        content.addSubview(startButton)
        self.startButton = startButton

        let stopButton = button(
            frame: NSRect(x: 128, y: 86, width: 92, height: 30),
            title: "Stop",
            action: #selector(stopFilter(_:))
        )
        content.addSubview(stopButton)
        self.stopButton = stopButton

        let restartButton = button(
            frame: NSRect(x: 234, y: 86, width: 104, height: 30),
            title: "Restart",
            action: #selector(restartFilter(_:))
        )
        content.addSubview(restartButton)
        self.restartButton = restartButton

        let accessibilityButton = button(
            frame: NSRect(x: 22, y: 42, width: 154, height: 30),
            title: "Accessibility",
            action: #selector(openAccessibilitySettings(_:))
        )
        content.addSubview(accessibilityButton)

        let logButton = button(
            frame: NSRect(x: 190, y: 42, width: 70, height: 30),
            title: "Log",
            action: #selector(openLog(_:))
        )
        content.addSubview(logButton)

        let quitButton = button(
            frame: NSRect(x: 274, y: 42, width: 64, height: 30),
            title: "Quit",
            action: #selector(quitApp(_:))
        )
        content.addSubview(quitButton)

        refreshStartAtLoginCheckbox()
    }

    private func label(frame: NSRect, text: String, fontSize: CGFloat, bold: Bool) -> NSTextField {
        let label = NSTextField(frame: frame)
        label.stringValue = text
        label.isEditable = false
        label.isSelectable = false
        label.isBezeled = false
        label.drawsBackground = false
        label.font = bold ? .boldSystemFont(ofSize: fontSize) : .systemFont(ofSize: fontSize)
        return label
    }

    private func button(frame: NSRect, title: String, action: Selector) -> NSButton {
        let button = NSButton(frame: frame)
        button.bezelStyle = .rounded
        button.title = title
        button.target = self
        button.action = action
        return button
    }

    @objc private func showWindow(_ sender: Any?) {
        buildWindow()
        refreshStartAtLoginCheckbox()
        updateAppState(status: isFilterRunning ? "Running" : "Stopped")
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    private var launchAgentURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/com.local.deadpad.app.plist")
    }

    private var isStartAtLoginEnabled: Bool {
        FileManager.default.fileExists(atPath: launchAgentURL.path)
    }

    private func setStartAtLogin(enabled: Bool) throws {
        if !enabled {
            if FileManager.default.fileExists(atPath: launchAgentURL.path) {
                try FileManager.default.removeItem(at: launchAgentURL)
            }
            return
        }

        let agentsURL = launchAgentURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: agentsURL,
            withIntermediateDirectories: true
        )

        let plist: [String: Any] = [
            "Label": "com.local.deadpad.app",
            "ProgramArguments": ["/usr/bin/open", Bundle.main.bundlePath],
            "RunAtLoad": true
        ]

        let data = try PropertyListSerialization.data(
            fromPropertyList: plist,
            format: .xml,
            options: 0
        )
        try data.write(to: launchAgentURL, options: .atomic)
    }

    private func refreshStartAtLoginCheckbox() {
        startAtLoginCheckbox?.state = isStartAtLoginEnabled ? .on : .off
    }

    @objc private func toggleStartAtLogin(_ sender: Any?) {
        let enabled = startAtLoginCheckbox?.state == .on

        do {
            try setStartAtLogin(enabled: enabled)
        } catch {
            refreshStartAtLoginCheckbox()
            showError(title: "Could not update login setting", detail: error.localizedDescription)
        }
    }

    private var isFilterRunning: Bool {
        task?.isRunning == true
    }

    private var helperPath: String {
        if let bundledPath = Bundle.main.path(forResource: "deadpad", ofType: nil) {
            return bundledPath
        }

        return (FileManager.default.currentDirectoryPath as NSString)
            .appendingPathComponent("deadpad")
    }

    private func appendLogLine(_ line: String) {
        let entry = "\n[\(Date())] \(line)\n"
        guard let data = entry.data(using: .utf8),
              let handle = FileHandle(forWritingAtPath: logPath) else {
            return
        }

        handle.seekToEndOfFile()
        handle.write(data)
        handle.closeFile()
    }

    private func openLogHandle() -> FileHandle? {
        guard let handle = FileHandle(forWritingAtPath: logPath) else {
            return nil
        }

        handle.seekToEndOfFile()
        return handle
    }

    private var deadPadArguments: [String] {
        [
            "--left-cm", "2",
            "--right-cm", "2",
            "--policy", "all",
            "--verbose"
        ]
    }

    @objc private func startFilter(_ sender: Any?) {
        if isFilterRunning {
            return
        }

        let helperPath = self.helperPath
        guard FileManager.default.isExecutableFile(atPath: helperPath) else {
            updateAppState(status: "Helper missing")
            showError(
                title: "DeadPad helper not found",
                detail: "Expected executable helper at:\n\(helperPath)"
            )
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: helperPath)
        process.arguments = deadPadArguments
        process.currentDirectoryURL = URL(
            fileURLWithPath: (helperPath as NSString).deletingLastPathComponent
        )

        logHandle = openLogHandle()
        process.standardOutput = logHandle
        process.standardError = logHandle

        process.terminationHandler = { [weak self] finishedProcess in
            DispatchQueue.main.async {
                guard let self, self.task === finishedProcess else {
                    return
                }

                let status = finishedProcess.terminationStatus
                self.logHandle?.closeFile()
                self.logHandle = nil
                self.task = nil

                if self.restartAfterStop {
                    self.restartAfterStop = false
                    self.startFilter(nil)
                } else {
                    self.updateAppState(status: "Stopped (\(status))")
                }
            }
        }

        task = process

        do {
            try process.run()
        } catch {
            logHandle?.closeFile()
            logHandle = nil
            task = nil
            updateAppState(status: "Launch failed")
            showError(title: "Could not start DeadPad", detail: error.localizedDescription)
            return
        }

        appendLogLine("DeadPad app started helper.")
        updateAppState(status: "Running")
    }

    @objc private func stopFilter(_ sender: Any?) {
        if !isFilterRunning {
            return
        }

        appendLogLine("DeadPad app stopping helper.")
        task?.terminate()
        updateAppState(status: "Stopping")
    }

    @objc private func restartFilter(_ sender: Any?) {
        if isFilterRunning {
            restartAfterStop = true
            stopFilter(nil)
        } else {
            startFilter(nil)
        }
    }

    @objc private func quitApp(_ sender: Any?) {
        NSApp.terminate(nil)
    }

    @objc private func openAccessibilitySettings(_ sender: Any?) {
        let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        )

        if let url {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func openLog(_ sender: Any?) {
        if !logPath.isEmpty {
            NSWorkspace.shared.open(URL(fileURLWithPath: logPath))
        }
    }

    private func updateAppState(status: String) {
        let running = isFilterRunning

        statusLabel?.stringValue = "Status: \(status)"
        startButton?.isEnabled = !running
        stopButton?.isEnabled = running
        restartButton?.isEnabled = running
        statusItem?.button?.toolTip = "DeadPad: \(status)"
    }

    private func showError(title: String, detail: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = detail
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}

let application = NSApplication.shared
let delegate = DeadPadAppDelegate()
application.delegate = delegate
application.run()
