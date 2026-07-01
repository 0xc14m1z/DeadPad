import Cocoa

private struct DeviceSurface {
    let index: Int
    let widthCm: Double
    let heightCm: Double
    let builtIn: Bool
}

private final class DevicesPreviewView: NSView {
    var devices: [DeviceSurface] = [] {
        didSet {
            needsDisplay = true
        }
    }
    var matchActiveAreaEnabled = false {
        didSet {
            needsDisplay = true
        }
    }

    override var isFlipped: Bool {
        true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        NSColor.windowBackgroundColor.setFill()
        bounds.fill()

        let available = bounds.insetBy(dx: 14, dy: 12)
        guard !devices.isEmpty else {
            drawPlaceholder(in: available)
            return
        }

        let gap = devices.count > 1
            ? min(CGFloat(14), available.height / CGFloat(devices.count * 5))
            : 0
        let totalGap = gap * CGFloat(max(devices.count - 1, 0))
        let maxWidthCm = devices
            .map { max($0.widthCm, 0.01) }
            .max() ?? 1
        let totalHeightCm = devices.reduce(0.0) { total, device in
            total + max(device.heightCm, 0.01)
        }
        let widthScale = available.width / CGFloat(maxWidthCm)
        let heightScale = max(available.height - totalGap, 1) / CGFloat(totalHeightCm)
        let scale = max(min(widthScale, heightScale), 0.01)
        let scaledHeight = CGFloat(totalHeightCm) * scale + totalGap
        var y = available.minY + max((available.height - scaledHeight) / 2.0, 0)
        let referenceDevice = activeAreaReferenceDevice()

        for device in devices.sorted(by: { $0.index < $1.index }) {
            let rectWidth = CGFloat(max(device.widthCm, 0.01)) * scale
            let rectHeight = CGFloat(max(device.heightCm, 0.01)) * scale
            let rect = NSRect(
                x: available.midX - rectWidth / 2.0,
                y: y,
                width: rectWidth,
                height: rectHeight
            )

            drawDevice(device, in: rect, reference: referenceDevice)
            y += rectHeight + gap
        }
    }

    private func drawDevice(_ device: DeviceSurface, in rect: NSRect, reference: DeviceSurface?) {
        let color = colorForDevice(at: device.index)
        let radius = min(rect.height * 0.10, 8)
        let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
        let activeRect = matchedActiveRect(for: device, reference: reference, in: rect)

        color.withAlphaComponent(0.16).setFill()
        path.fill()
        color.setStroke()
        path.lineWidth = 2.0
        path.stroke()

        if let activeRect {
            let activeRadius = min(activeRect.height * 0.10, 8)
            drawDisabledOverlay(
                in: rect,
                activeRect: activeRect,
                outerRadius: radius,
                activeRadius: activeRadius
            )
        }

        drawLabel(for: device, in: activeRect ?? rect)
    }

    private func drawLabel(for device: DeviceSurface, in rect: NSRect) {
        guard rect.width >= 72, rect.height >= 26 else {
            return
        }

        let label = String(
            format: "Trackpad %d (%@)\n%.2f x %.2f cm",
            device.index,
            device.builtIn ? "built-in" : "external",
            device.widthCm,
            device.heightCm
        )
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraph
        ]
        let textHeight = min(rect.height - 8, 30)
        let textRect = NSRect(
            x: rect.minX + 6,
            y: rect.midY - textHeight / 2.0,
            width: rect.width - 12,
            height: textHeight
        )

        (label as NSString).draw(
            with: textRect,
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attributes
        )
    }

    private func drawPlaceholder(in rect: NSRect) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12),
            .foregroundColor: NSColor.secondaryLabelColor,
            .paragraphStyle: paragraph
        ]
        ("No devices found" as NSString).draw(
            with: rect,
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attributes
        )
    }

    private func activeAreaReferenceDevice() -> DeviceSurface? {
        devices.first { $0.builtIn } ?? devices.first { $0.index == 0 } ?? devices.first
    }

    private func matchedActiveRect(
        for device: DeviceSurface,
        reference: DeviceSurface?,
        in rect: NSRect
    ) -> NSRect? {
        guard matchActiveAreaEnabled,
              let reference,
              reference.index != device.index else {
            return nil
        }

        let deviceWidth = max(device.widthCm, 0.01)
        let deviceHeight = max(device.heightCm, 0.01)
        let activeWidthRatio = min(reference.widthCm, deviceWidth) / deviceWidth
        let activeHeightRatio = min(reference.heightCm, deviceHeight) / deviceHeight
        let activeWidth = rect.width * CGFloat(activeWidthRatio)
        let activeHeight = rect.height * CGFloat(activeHeightRatio)

        guard activeWidth < rect.width - 0.5 || activeHeight < rect.height - 0.5 else {
            return nil
        }

        return NSRect(
            x: rect.midX - activeWidth / 2.0,
            y: rect.minY,
            width: activeWidth,
            height: activeHeight
        )
    }

    private func drawDisabledOverlay(
        in rect: NSRect,
        activeRect: NSRect,
        outerRadius: CGFloat,
        activeRadius: CGFloat
    ) {
        let outerPath = NSBezierPath(
            roundedRect: rect,
            xRadius: outerRadius,
            yRadius: outerRadius
        )
        let activePath = NSBezierPath(
            roundedRect: activeRect,
            xRadius: activeRadius,
            yRadius: activeRadius
        )
        let maskPath = NSBezierPath()
        maskPath.append(outerPath)
        maskPath.append(activePath)
        maskPath.windingRule = .evenOdd

        NSGraphicsContext.saveGraphicsState()
        maskPath.addClip()

        NSColor.systemRed.withAlphaComponent(0.07).setFill()
        rect.fill()

        let hatchPath = NSBezierPath()
        let spacing: CGFloat = 16
        var x = rect.minX - rect.height
        while x < rect.maxX {
            hatchPath.move(to: NSPoint(x: x, y: rect.maxY))
            hatchPath.line(to: NSPoint(x: x + rect.height, y: rect.minY))
            x += spacing
        }

        NSColor.systemRed.withAlphaComponent(0.75).setStroke()
        hatchPath.lineWidth = 1.4
        hatchPath.stroke()

        NSGraphicsContext.restoreGraphicsState()

        NSColor.systemRed.withAlphaComponent(0.65).setStroke()
        activePath.lineWidth = 1.2
        activePath.stroke()
    }

    private func colorForDevice(at index: Int) -> NSColor {
        let colors: [NSColor] = [
            .controlAccentColor,
            .systemGreen,
            .systemOrange,
            .systemPurple,
            .systemPink,
            .systemTeal
        ]

        return colors[index % colors.count]
    }
}

final class DeadPadAppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var window: NSWindow?
    private weak var statusLabel: NSTextField?
    private weak var deviceDimensionsLabel: NSTextField?
    private weak var devicesPreviewView: DevicesPreviewView?
    private weak var startButton: NSButton?
    private weak var stopButton: NSButton?
    private weak var restartButton: NSButton?
    private weak var startAtLoginCheckbox: NSButton?
    private weak var matchActiveAreaButton: NSButton?
    private var deviceSurfaces: [DeviceSurface] = []
    private var matchActiveAreaEnabled = false
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

        let frame = NSRect(x: 0, y: 0, width: 420, height: 480)
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

        let statusLabel = label(
            frame: NSRect(x: 22, y: 432, width: 360, height: 20),
            text: "Status: Stopped",
            fontSize: 13,
            bold: false
        )
        content.addSubview(statusLabel)
        self.statusLabel = statusLabel

        let previewTitleLabel = label(
            frame: NSRect(x: 22, y: 364, width: 260, height: 18),
            text: "Trackpads",
            fontSize: 13,
            bold: true
        )
        content.addSubview(previewTitleLabel)

        let deviceDimensionsLabel = label(
            frame: NSRect(x: 270, y: 364, width: 128, height: 18),
            text: "Loading...",
            fontSize: 12,
            bold: false
        )
        deviceDimensionsLabel.alignment = .right
        content.addSubview(deviceDimensionsLabel)
        self.deviceDimensionsLabel = deviceDimensionsLabel

        let devicesPreviewView = DevicesPreviewView(frame: NSRect(x: 22, y: 132, width: 376, height: 220))
        content.addSubview(devicesPreviewView)
        self.devicesPreviewView = devicesPreviewView

        let startAtLoginCheckbox = NSButton(frame: NSRect(x: 20, y: 400, width: 220, height: 24))
        startAtLoginCheckbox.setButtonType(.switch)
        startAtLoginCheckbox.title = "Start at login"
        startAtLoginCheckbox.target = self
        startAtLoginCheckbox.action = #selector(toggleStartAtLogin(_:))
        content.addSubview(startAtLoginCheckbox)
        self.startAtLoginCheckbox = startAtLoginCheckbox

        let matchActiveAreaButton = button(
            frame: NSRect(x: 242, y: 398, width: 156, height: 28),
            title: "Match active area",
            action: #selector(matchActiveArea(_:))
        )
        content.addSubview(matchActiveAreaButton)
        self.matchActiveAreaButton = matchActiveAreaButton

        let startButton = button(
            frame: NSRect(x: 22, y: 62, width: 92, height: 30),
            title: "Start",
            action: #selector(startFilter(_:))
        )
        content.addSubview(startButton)
        self.startButton = startButton

        let stopButton = button(
            frame: NSRect(x: 128, y: 62, width: 92, height: 30),
            title: "Stop",
            action: #selector(stopFilter(_:))
        )
        content.addSubview(stopButton)
        self.stopButton = stopButton

        let restartButton = button(
            frame: NSRect(x: 234, y: 62, width: 104, height: 30),
            title: "Restart",
            action: #selector(restartFilter(_:))
        )
        content.addSubview(restartButton)
        self.restartButton = restartButton

        let accessibilityButton = button(
            frame: NSRect(x: 22, y: 22, width: 154, height: 30),
            title: "Accessibility",
            action: #selector(openAccessibilitySettings(_:))
        )
        content.addSubview(accessibilityButton)

        let logButton = button(
            frame: NSRect(x: 190, y: 22, width: 70, height: 30),
            title: "Log",
            action: #selector(openLog(_:))
        )
        content.addSubview(logButton)

        let quitButton = button(
            frame: NSRect(x: 274, y: 22, width: 64, height: 30),
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
        refreshDevicePreview()
        updateAppState(status: isFilterRunning ? "Running" : "Stopped")
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    private func refreshDevicePreview() {
        let devices = loadDeviceSurfaces()
        deviceSurfaces = devices
        devicesPreviewView?.devices = devices
        devicesPreviewView?.matchActiveAreaEnabled = matchActiveAreaEnabled

        guard !devices.isEmpty else {
            deviceDimensionsLabel?.stringValue = "Unavailable"
            return
        }

        deviceDimensionsLabel?.stringValue = devices.count == 1
            ? "1 device"
            : "\(devices.count) devices"
    }

    private func loadDeviceSurfaces() -> [DeviceSurface] {
        let helperPath = self.helperPath
        guard FileManager.default.isExecutableFile(atPath: helperPath) else {
            return []
        }

        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: helperPath)
        process.arguments = ["--list-devices"]
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
        } catch {
            return []
        }

        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            return []
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else {
            return []
        }

        return parseDeviceSurfaces(from: output)
    }

    private func parseDeviceSurfaces(from output: String) -> [DeviceSurface] {
        let pattern = #"^\[(\d+)\].*builtIn=(yes|no).*surface=([0-9]+(?:\.[0-9]+)?)cm x ([0-9]+(?:\.[0-9]+)?)cm"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return []
        }

        var devices: [DeviceSurface] = []
        for line in output.split(whereSeparator: \.isNewline) {
            let line = String(line)
            let range = NSRange(line.startIndex..<line.endIndex, in: line)
            guard let match = regex.firstMatch(in: line, range: range),
                  let indexRange = Range(match.range(at: 1), in: line),
                  let builtInRange = Range(match.range(at: 2), in: line),
                  let widthRange = Range(match.range(at: 3), in: line),
                  let heightRange = Range(match.range(at: 4), in: line),
                  let index = Int(line[indexRange]),
                  let width = Double(line[widthRange]),
                  let height = Double(line[heightRange]) else {
                continue
            }

            devices.append(DeviceSurface(
                index: index,
                widthCm: width,
                heightCm: height,
                builtIn: line[builtInRange] == "yes"
            ))
        }

        return devices.sorted { $0.index < $1.index }
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

    @objc private func matchActiveArea(_ sender: Any?) {
        matchActiveAreaEnabled = true

        if deviceSurfaces.isEmpty {
            refreshDevicePreview()
        } else {
            devicesPreviewView?.matchActiveAreaEnabled = true
        }

        appendLogLine("DeadPad app enabled Match active area.")

        if isFilterRunning {
            restartAfterStop = true
            stopFilter(nil)
        }
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
        var arguments = [
            "--left-cm", "2",
            "--right-cm", "2",
            "--policy", "all",
            "--verbose"
        ]

        if let matchedZones = matchedActiveAreaDeadZones() {
            arguments = [
                "--device", "\(matchedZones.deviceIndex)",
                "--left-cm", formatCm(matchedZones.left),
                "--right-cm", formatCm(matchedZones.right),
                "--top-cm", formatCm(matchedZones.top),
                "--bottom-cm", formatCm(matchedZones.bottom),
                "--policy", "all",
                "--verbose"
            ]
        }

        return arguments
    }

    private func matchedActiveAreaDeadZones() -> (
        deviceIndex: Int,
        left: Double,
        right: Double,
        top: Double,
        bottom: Double
    )? {
        guard matchActiveAreaEnabled else {
            return nil
        }

        if deviceSurfaces.isEmpty {
            deviceSurfaces = loadDeviceSurfaces()
        }

        guard let reference = activeAreaReferenceDevice(),
              let target = matchedActiveAreaTargetDevice(reference: reference) else {
            return nil
        }

        let horizontalExcess = max(target.widthCm - reference.widthCm, 0)
        let verticalExcess = max(target.heightCm - reference.heightCm, 0)

        return (
            deviceIndex: target.index,
            left: horizontalExcess / 2.0,
            right: horizontalExcess / 2.0,
            top: 0,
            bottom: verticalExcess
        )
    }

    private func activeAreaReferenceDevice() -> DeviceSurface? {
        deviceSurfaces.first { $0.builtIn }
            ?? deviceSurfaces.first { $0.index == 0 }
            ?? deviceSurfaces.first
    }

    private func matchedActiveAreaTargetDevice(reference: DeviceSurface) -> DeviceSurface? {
        deviceSurfaces
            .filter { $0.index != reference.index }
            .max { left, right in
                let leftScore = (left.builtIn ? 0 : 1_000_000) + left.widthCm * left.heightCm
                let rightScore = (right.builtIn ? 0 : 1_000_000) + right.widthCm * right.heightCm
                return leftScore < rightScore
            }
    }

    private func formatCm(_ value: Double) -> String {
        String(format: "%.4f", value)
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

@main
enum DeadPadApplication {
    private static let delegate = DeadPadAppDelegate()

    static func main() {
        let application = NSApplication.shared
        application.delegate = delegate
        application.run()
    }
}
