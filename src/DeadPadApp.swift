import Cocoa
import QuartzCore

private struct DeviceSurface {
    let index: Int
    let widthCm: Double
    let heightCm: Double
    let builtIn: Bool
}

private struct TouchIndicator {
    let deviceIndex: Int
    let pathIndex: Int
    let x: Double
    let y: Double
    let lastSeen: Date
}

private enum MatcherColors {
    static let window = dynamic(
        light: NSColor(calibratedRed: 0.985, green: 0.987, blue: 0.992, alpha: 1),
        dark: NSColor(calibratedRed: 0.140, green: 0.146, blue: 0.160, alpha: 1)
    )
    static let panel = dynamic(
        light: .white,
        dark: NSColor(calibratedRed: 0.165, green: 0.170, blue: 0.186, alpha: 1)
    )
    static let foreground = dynamic(
        light: NSColor(calibratedRed: 0.190, green: 0.198, blue: 0.220, alpha: 1),
        dark: NSColor(calibratedRed: 0.940, green: 0.945, blue: 0.955, alpha: 1)
    )
    static let muted = dynamic(
        light: NSColor(calibratedRed: 0.455, green: 0.475, blue: 0.520, alpha: 1),
        dark: NSColor(calibratedRed: 0.625, green: 0.645, blue: 0.690, alpha: 1)
    )
    static let faint = dynamic(
        light: NSColor(calibratedRed: 0.620, green: 0.640, blue: 0.680, alpha: 1),
        dark: NSColor(calibratedRed: 0.470, green: 0.490, blue: 0.530, alpha: 1)
    )
    static let hairline = dynamic(
        light: NSColor(calibratedRed: 0.900, green: 0.910, blue: 0.930, alpha: 1),
        dark: NSColor(calibratedRed: 0.285, green: 0.295, blue: 0.320, alpha: 1)
    )
    static let accent = dynamic(
        light: NSColor(calibratedRed: 0.310, green: 0.400, blue: 0.900, alpha: 1),
        dark: NSColor(calibratedRed: 0.480, green: 0.575, blue: 1.000, alpha: 1)
    )
    static let padFill = dynamic(
        light: NSColor(calibratedRed: 0.940, green: 0.945, blue: 0.955, alpha: 1),
        dark: NSColor(calibratedRed: 0.245, green: 0.255, blue: 0.280, alpha: 1)
    )
    static let padEdge = dynamic(
        light: NSColor(calibratedRed: 0.805, green: 0.820, blue: 0.850, alpha: 1),
        dark: NSColor(calibratedRed: 0.355, green: 0.370, blue: 0.405, alpha: 1)
    )
    static let padOff = dynamic(
        light: NSColor(calibratedRed: 0.860, green: 0.865, blue: 0.880, alpha: 0.62),
        dark: NSColor(calibratedRed: 0.205, green: 0.215, blue: 0.235, alpha: 0.68)
    )

    private static func dynamic(light: NSColor, dark: NSColor) -> NSColor {
        if #available(macOS 10.14, *) {
            return NSColor(name: nil) { appearance in
                let match = appearance.bestMatch(from: [.darkAqua, .aqua])
                return match == .darkAqua ? dark : light
            }
        }

        return light
    }
}

private final class MatcherRootView: NSView {
    override var isFlipped: Bool {
        true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        MatcherColors.window.setFill()
        bounds.fill()
    }
}

private final class RowsPanelView: NSView {
    override var isFlipped: Bool {
        true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let panelPath = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 11, yRadius: 11)
        MatcherColors.panel.setFill()
        panelPath.fill()
        MatcherColors.hairline.setStroke()
        panelPath.lineWidth = 1
        panelPath.stroke()

        let separator = NSBezierPath()
        separator.move(to: NSPoint(x: 0, y: bounds.midY))
        separator.line(to: NSPoint(x: bounds.width, y: bounds.midY))
        separator.lineWidth = 1
        MatcherColors.hairline.setStroke()
        separator.stroke()
    }
}

private final class ToggleSwitch: NSControl {
    var isOn = false
    private var knobProgress: CGFloat = 0 {
        didSet {
            needsDisplay = true
        }
    }
    private var animationTimer: Timer?
    private var animationStart = CACurrentMediaTime()
    private var animationFrom: CGFloat = 0
    private var animationTo: CGFloat = 0

    override var isFlipped: Bool {
        true
    }

    override var acceptsFirstResponder: Bool {
        true
    }

    func setOn(_ on: Bool, animated: Bool) {
        isOn = on
        animate(to: on ? 1 : 0, duration: animated ? 0.25 : 0)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let trackRect = bounds.insetBy(dx: 0, dy: 0)
        let trackColor = blend(from: MatcherColors.hairline, to: MatcherColors.accent, progress: knobProgress)
        trackColor.setFill()
        NSBezierPath(roundedRect: trackRect, xRadius: trackRect.height / 2, yRadius: trackRect.height / 2).fill()

        let knobSize: CGFloat = 22
        let knobX = 2 + (bounds.width - knobSize - 4) * knobProgress
        let knobRect = NSRect(x: knobX, y: 2, width: knobSize, height: knobSize)
        NSColor.white.setFill()
        NSBezierPath(ovalIn: knobRect).fill()
        NSColor(calibratedWhite: 0, alpha: 0.18).setStroke()
        NSBezierPath(ovalIn: knobRect).stroke()
    }

    override func mouseDown(with event: NSEvent) {
        setOn(!isOn, animated: true)
        sendAction(action, to: target)
    }

    override func keyDown(with event: NSEvent) {
        if event.charactersIgnoringModifiers == " " || event.keyCode == 36 {
            setOn(!isOn, animated: true)
            sendAction(action, to: target)
        } else {
            super.keyDown(with: event)
        }
    }

    private func animate(to target: CGFloat, duration: TimeInterval) {
        animationTimer?.invalidate()
        guard duration > 0 else {
            knobProgress = target
            return
        }

        animationStart = CACurrentMediaTime()
        animationFrom = knobProgress
        animationTo = target
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] timer in
            guard let self else {
                timer.invalidate()
                return
            }

            let elapsed = CACurrentMediaTime() - self.animationStart
            let t = min(max(elapsed / duration, 0), 1)
            let eased = self.ease(t)
            self.knobProgress = self.animationFrom + (self.animationTo - self.animationFrom) * eased

            if t >= 1 {
                timer.invalidate()
                self.animationTimer = nil
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        animationTimer = timer
    }

    private func ease(_ t: CGFloat) -> CGFloat {
        t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2
    }

    private func blend(from: NSColor, to: NSColor, progress: CGFloat) -> NSColor {
        let fromRGB = from.usingColorSpace(.deviceRGB) ?? from
        let toRGB = to.usingColorSpace(.deviceRGB) ?? to
        return NSColor(
            calibratedRed: fromRGB.redComponent + (toRGB.redComponent - fromRGB.redComponent) * progress,
            green: fromRGB.greenComponent + (toRGB.greenComponent - fromRGB.greenComponent) * progress,
            blue: fromRGB.blueComponent + (toRGB.blueComponent - fromRGB.blueComponent) * progress,
            alpha: fromRGB.alphaComponent + (toRGB.alphaComponent - fromRGB.alphaComponent) * progress
        )
    }
}

private final class DevicesPreviewView: NSView {
    var devices: [DeviceSurface] = [] {
        didSet {
            needsDisplay = true
        }
    }
    var matchActiveAreaEnabled = false {
        didSet {
            animateReduction(to: matchActiveAreaEnabled ? 1 : 0)
        }
    }
    var touchIndicators: [Int: [TouchIndicator]] = [:] {
        didSet {
            needsDisplay = true
        }
    }
    var touchPressed = false {
        didSet {
            needsDisplay = true
        }
    }
    private var reductionProgress: CGFloat = 0 {
        didSet {
            needsDisplay = true
        }
    }
    private var reductionTimer: Timer?
    private var reductionStart = CACurrentMediaTime()
    private var reductionFrom: CGFloat = 0
    private var reductionTo: CGFloat = 0

    override var isFlipped: Bool {
        true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        drawPrototypeStage()
    }

    private func drawPrototypeStage() {
        let magicRect = NSRect(
            x: bounds.midX - 107,
            y: bounds.midY - 74,
            width: 214,
            height: 148
        )
        let magicPath = roundedPath(in: magicRect, radius: 16)
        let activeRect = interpolatedActiveRect(in: magicRect)
        let activePath = roundedPath(
            in: activeRect,
            topRadius: interpolate(from: 11, to: 16),
            bottomRadius: interpolate(from: 11, to: 10)
        )

        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowBlurRadius = 10
        shadow.shadowOffset = NSSize(width: 0, height: -2)
        shadow.shadowColor = NSColor(calibratedWhite: 0, alpha: 0.06)
        shadow.set()
        MatcherColors.padFill.setFill()
        magicPath.fill()
        NSGraphicsContext.restoreGraphicsState()

        MatcherColors.padEdge.setStroke()
        magicPath.lineWidth = 1
        magicPath.stroke()

        drawDisabledHatching(in: magicRect, clippedBy: magicPath)
        drawReferenceOutline(in: activeRect)

        MatcherColors.accent.withAlphaComponent(interpolate(from: 0.16, to: 0.20)).setFill()
        activePath.fill()
        MatcherColors.accent.setStroke()
        activePath.lineWidth = 1.5
        activePath.stroke()

        drawActiveAreaLabel(in: activeRect)
        drawMagicLabel(below: magicRect)

        if let target = targetDevice() {
            drawStageTouchIndicators(deviceIndex: target.index, in: magicRect, activeRect: reductionProgress > 0.01 ? activeRect : nil)
        }
    }

    private func targetDevice() -> DeviceSurface? {
        let reference = activeAreaReferenceDevice()
        return devices
            .filter { $0.index != reference?.index }
            .max { left, right in
                let leftScore = (left.builtIn ? 0 : 1_000_000) + left.widthCm * left.heightCm
                let rightScore = (right.builtIn ? 0 : 1_000_000) + right.widthCm * right.heightCm
                return leftScore < rightScore
            }
            ?? devices.first
    }

    private func interpolatedActiveRect(in magicRect: NSRect) -> NSRect {
        let off = magicRect.insetBy(dx: 6, dy: 6)
        let on = NSRect(
            x: magicRect.midX - 59,
            y: magicRect.minY - 1,
            width: 118,
            height: 92
        )

        return NSRect(
            x: interpolate(from: off.minX, to: on.minX),
            y: interpolate(from: off.minY, to: on.minY),
            width: interpolate(from: off.width, to: on.width),
            height: interpolate(from: off.height, to: on.height)
        )
    }

    private func drawDisabledHatching(in rect: NSRect, clippedBy clipPath: NSBezierPath) {
        guard reductionProgress > 0.001 else {
            return
        }

        NSGraphicsContext.saveGraphicsState()
        clipPath.addClip()

        MatcherColors.padOff.withAlphaComponent(0.60 * reductionProgress).setFill()
        rect.fill()

        let hatchPath = NSBezierPath()
        var x = rect.minX - rect.height
        while x < rect.maxX + rect.height {
            hatchPath.move(to: NSPoint(x: x, y: rect.maxY))
            hatchPath.line(to: NSPoint(x: x + rect.height, y: rect.minY))
            x += 10
        }

        MatcherColors.padOff.withAlphaComponent(0.95 * reductionProgress).setStroke()
        hatchPath.lineWidth = 1.2
        hatchPath.stroke()

        NSGraphicsContext.restoreGraphicsState()
    }

    private func drawReferenceOutline(in rect: NSRect) {
        guard reductionProgress > 0.001 else {
            return
        }

        let refPath = roundedPath(in: rect, topRadius: 16, bottomRadius: 10)
        let dash: [CGFloat] = [4, 4]
        refPath.setLineDash(dash, count: dash.count, phase: 0)
        MatcherColors.muted.withAlphaComponent(0.46 * reductionProgress).setStroke()
        refPath.lineWidth = 1.2
        refPath.stroke()

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        ("= Built-in · ~130 × 100 mm" as NSString).draw(
            with: NSRect(x: rect.minX + 4, y: rect.maxY - 17, width: rect.width - 8, height: 11),
            options: [.usesLineFragmentOrigin],
            attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 9, weight: .regular),
                .foregroundColor: MatcherColors.muted.withAlphaComponent(0.90 * reductionProgress),
                .paragraphStyle: paragraph
            ]
        )
    }

    private func drawActiveAreaLabel(in rect: NSRect) {
        let titleParagraph = NSMutableParagraphStyle()
        titleParagraph.alignment = .center
        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: MatcherColors.accent,
            .paragraphStyle: titleParagraph
        ]
        let subAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 9, weight: .regular),
            .foregroundColor: MatcherColors.accent.withAlphaComponent(0.75),
            .paragraphStyle: titleParagraph
        ]
        let titleRect = NSRect(x: rect.minX + 8, y: rect.midY - 17, width: rect.width - 16, height: 15)
        let subtitle = reductionProgress > 0.5 ? "matches built-in" : "full trackpad"
        let subtitleRect = NSRect(x: rect.minX + 8, y: rect.midY - 1, width: rect.width - 16, height: 13)

        ("Active area" as NSString).draw(with: titleRect, options: [.usesLineFragmentOrigin], attributes: titleAttributes)
        (subtitle as NSString).draw(with: subtitleRect, options: [.usesLineFragmentOrigin], attributes: subAttributes)
    }

    private func drawMagicLabel(below rect: NSRect) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let label = NSMutableAttributedString(
            string: "Magic Trackpad",
            attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 10, weight: .semibold),
                .foregroundColor: MatcherColors.muted
            ]
        )
        label.append(NSAttributedString(
            string: " · ~160 × 115 mm",
            attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 10, weight: .regular),
                .foregroundColor: MatcherColors.faint
            ]
        ))
        label.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: label.length))
        label.draw(with: NSRect(x: rect.minX - 40, y: rect.maxY + 8, width: rect.width + 80, height: 14))
    }

    private func drawStageTouchIndicators(deviceIndex: Int, in rect: NSRect, activeRect: NSRect?) {
        guard let touches = touchIndicators[deviceIndex] else {
            return
        }

        for touch in touches {
            let point = NSPoint(
                x: rect.minX + CGFloat(clampUnit(touch.x)) * rect.width,
                y: rect.minY + CGFloat(1.0 - clampUnit(touch.y)) * rect.height
            )
            let disabled = activeRect.map { !$0.contains(point) } ?? false
            let color: NSColor = disabled ? .systemYellow : (touchPressed ? .systemGreen : MatcherColors.accent)
            drawTouchDot(at: point, color: color)
        }
    }

    private func drawTouchDot(at point: NSPoint, color: NSColor) {
        let outer = NSRect(x: point.x - 6, y: point.y - 6, width: 12, height: 12)
        let inner = NSRect(x: point.x - 4, y: point.y - 4, width: 8, height: 8)
        NSColor.white.withAlphaComponent(0.95).setFill()
        NSBezierPath(ovalIn: outer).fill()
        color.setFill()
        NSBezierPath(ovalIn: inner).fill()
        color.withAlphaComponent(0.42).setStroke()
        NSBezierPath(ovalIn: outer).stroke()
    }

    private func animateReduction(to target: CGFloat) {
        reductionTimer?.invalidate()
        reductionStart = CACurrentMediaTime()
        reductionFrom = reductionProgress
        reductionTo = target

        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] timer in
            guard let self else {
                timer.invalidate()
                return
            }

            let elapsed = CACurrentMediaTime() - self.reductionStart
            let t = min(max(elapsed / 0.6, 0), 1)
            let eased = self.ease(t)
            self.reductionProgress = self.reductionFrom + (self.reductionTo - self.reductionFrom) * eased

            if t >= 1 {
                timer.invalidate()
                self.reductionTimer = nil
            }
        }

        RunLoop.main.add(timer, forMode: .common)
        reductionTimer = timer
    }

    private func interpolate(from: CGFloat, to: CGFloat) -> CGFloat {
        from + (to - from) * reductionProgress
    }

    private func ease(_ t: CGFloat) -> CGFloat {
        t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2
    }

    private func roundedPath(in rect: NSRect, radius: CGFloat) -> NSBezierPath {
        roundedPath(in: rect, topRadius: radius, bottomRadius: radius)
    }

    private func roundedPath(in rect: NSRect, topRadius: CGFloat, bottomRadius: CGFloat) -> NSBezierPath {
        let topRadius = min(topRadius, rect.width / 2, rect.height / 2)
        let bottomRadius = min(bottomRadius, rect.width / 2, rect.height / 2)
        let path = NSBezierPath()

        path.move(to: NSPoint(x: rect.minX + topRadius, y: rect.minY))
        path.line(to: NSPoint(x: rect.maxX - topRadius, y: rect.minY))
        path.curve(
            to: NSPoint(x: rect.maxX, y: rect.minY + topRadius),
            controlPoint1: NSPoint(x: rect.maxX - topRadius * 0.45, y: rect.minY),
            controlPoint2: NSPoint(x: rect.maxX, y: rect.minY + topRadius * 0.45)
        )
        path.line(to: NSPoint(x: rect.maxX, y: rect.maxY - bottomRadius))
        path.curve(
            to: NSPoint(x: rect.maxX - bottomRadius, y: rect.maxY),
            controlPoint1: NSPoint(x: rect.maxX, y: rect.maxY - bottomRadius * 0.45),
            controlPoint2: NSPoint(x: rect.maxX - bottomRadius * 0.45, y: rect.maxY)
        )
        path.line(to: NSPoint(x: rect.minX + bottomRadius, y: rect.maxY))
        path.curve(
            to: NSPoint(x: rect.minX, y: rect.maxY - bottomRadius),
            controlPoint1: NSPoint(x: rect.minX + bottomRadius * 0.45, y: rect.maxY),
            controlPoint2: NSPoint(x: rect.minX, y: rect.maxY - bottomRadius * 0.45)
        )
        path.line(to: NSPoint(x: rect.minX, y: rect.minY + topRadius))
        path.curve(
            to: NSPoint(x: rect.minX + topRadius, y: rect.minY),
            controlPoint1: NSPoint(x: rect.minX, y: rect.minY + topRadius * 0.45),
            controlPoint2: NSPoint(x: rect.minX + topRadius * 0.45, y: rect.minY)
        )
        path.close()
        return path
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
        drawTouchIndicators(for: device, in: rect, activeRect: activeRect)
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

    private func drawTouchIndicators(for device: DeviceSurface, in rect: NSRect, activeRect: NSRect?) {
        guard let touches = touchIndicators[device.index] else {
            return
        }

        for touch in touches {
            let point = NSPoint(
                x: rect.minX + CGFloat(clampUnit(touch.x)) * rect.width,
                y: rect.minY + CGFloat(1.0 - clampUnit(touch.y)) * rect.height
            )
            let outerRadius: CGFloat = 6
            let innerRadius: CGFloat = 4
            let outerRect = NSRect(
                x: point.x - outerRadius,
                y: point.y - outerRadius,
                width: outerRadius * 2,
                height: outerRadius * 2
            )
            let innerRect = NSRect(
                x: point.x - innerRadius,
                y: point.y - innerRadius,
                width: innerRadius * 2,
                height: innerRadius * 2
            )

            let disabled = activeRect.map { !$0.contains(point) } ?? false
            let indicatorColor: NSColor
            let strokeColor: NSColor

            if disabled {
                indicatorColor = .systemYellow
                strokeColor = .systemYellow
            } else if touchPressed {
                indicatorColor = .systemGreen
                strokeColor = .systemGreen
            } else {
                indicatorColor = .controlAccentColor
                strokeColor = .labelColor
            }

            NSColor.white.withAlphaComponent(0.95).setFill()
            NSBezierPath(ovalIn: outerRect).fill()
            indicatorColor.setFill()
            NSBezierPath(ovalIn: innerRect).fill()
            strokeColor.withAlphaComponent(disabled || touchPressed ? 0.42 : 0.28).setStroke()
            NSBezierPath(ovalIn: outerRect).stroke()
        }
    }

    private func clampUnit(_ value: Double) -> Double {
        min(max(value, 0), 1)
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

final class DeadPadAppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private weak var statusLabel: NSTextField?
    private weak var deviceDimensionsLabel: NSTextField?
    private weak var devicesPreviewView: DevicesPreviewView?
    private weak var startButton: NSButton?
    private weak var stopButton: NSButton?
    private weak var restartButton: NSButton?
    private weak var startAtLoginSwitch: ToggleSwitch?
    private weak var matchActiveAreaSwitch: ToggleSwitch?
    private weak var reduceSubtitleLabel: NSTextField?
    private var deviceSurfaces: [DeviceSurface] = []
    private var matchActiveAreaEnabled = false
    private var task: Process?
    private var logHandle: FileHandle?
    private var touchStreamTask: Process?
    private var touchStreamPipe: Pipe?
    private var touchStreamLogHandle: FileHandle?
    private var touchStreamBuffer = Data()
    private var activeTouchIndicators: [String: TouchIndicator] = [:]
    private var touchCleanupTimer: Timer?
    private var localClickMonitor: Any?
    private var globalClickMonitor: Any?
    private var touchPressed = false
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
        stopClickMonitors()
        stopTouchStream()
        stopFilter(nil)
    }

    private func prepareLogPath() {
        let logsURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/Deadpad", isDirectory: true)

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
        statusItem?.button?.toolTip = "Deadpad"
        statusItem?.button?.target = self
        statusItem?.button?.action = #selector(togglePopover(_:))
    }

    private func buildPopover() {
        if popover != nil {
            return
        }

        let frame = NSRect(x: 0, y: 0, width: 380, height: 450)
        let content = MatcherRootView(frame: frame)

        let explanation = explanatoryLabel(frame: NSRect(x: 22, y: 22, width: 336, height: 40))
        content.addSubview(explanation)

        let devicesPreviewView = DevicesPreviewView(frame: NSRect(x: 22, y: 86, width: 336, height: 196))
        content.addSubview(devicesPreviewView)
        self.devicesPreviewView = devicesPreviewView

        let rowsPanel = RowsPanelView(frame: NSRect(x: 22, y: 308, width: 336, height: 121))
        content.addSubview(rowsPanel)

        let reduceTitle = rowTitle(frame: NSRect(x: 16, y: 16, width: 220, height: 17), text: "Reduce active area")
        rowsPanel.addSubview(reduceTitle)
        let reduceSubtitle = rowSubtitle(frame: NSRect(x: 16, y: 36, width: 220, height: 14), text: "match it to the built-in trackpad")
        rowsPanel.addSubview(reduceSubtitle)
        self.reduceSubtitleLabel = reduceSubtitle

        let reduceSwitch = ToggleSwitch(frame: NSRect(x: 276, y: 17, width: 44, height: 26))
        reduceSwitch.target = self
        reduceSwitch.action = #selector(toggleMatchActiveArea(_:))
        rowsPanel.addSubview(reduceSwitch)
        self.matchActiveAreaSwitch = reduceSwitch

        let loginTitle = rowTitle(frame: NSRect(x: 16, y: 76, width: 220, height: 17), text: "Start at login")
        rowsPanel.addSubview(loginTitle)
        let loginSubtitle = rowSubtitle(frame: NSRect(x: 16, y: 96, width: 220, height: 14), text: "open Deadpad when you log in")
        rowsPanel.addSubview(loginSubtitle)

        let loginSwitch = ToggleSwitch(frame: NSRect(x: 276, y: 78, width: 44, height: 26))
        loginSwitch.target = self
        loginSwitch.action = #selector(toggleStartAtLogin(_:))
        rowsPanel.addSubview(loginSwitch)
        self.startAtLoginSwitch = loginSwitch

        refreshStartAtLoginCheckbox()
        refreshMatchActiveAreaCheckbox()

        let controller = NSViewController()
        controller.view = content

        let popover = NSPopover()
        popover.contentSize = frame.size
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        popover.contentViewController = controller
        self.popover = popover
    }

    func popoverDidClose(_ notification: Notification) {
        stopClickMonitors()
        stopTouchStream()
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

    private func explanatoryLabel(frame: NSRect) -> NSTextField {
        let label = NSTextField(frame: frame)
        label.isEditable = false
        label.isSelectable = false
        label.isBezeled = false
        label.drawsBackground = false
        label.maximumNumberOfLines = 2
        label.alignment = .center

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineSpacing = 1.5

        let text = "The highlighted region is the Magic Trackpad active area.\nTurn on Reduce active area to match the built-in trackpad."
        let attributed = NSMutableAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: 12.5),
            .foregroundColor: MatcherColors.muted,
            .paragraphStyle: paragraph
        ])
        for phrase in ["active area", "Reduce active area"] {
            let range = (text as NSString).range(of: phrase)
            if range.location != NSNotFound {
                attributed.addAttributes([
                    .font: NSFont.systemFont(ofSize: 12.5, weight: .semibold),
                    .foregroundColor: MatcherColors.foreground
                ], range: range)
            }
        }
        label.attributedStringValue = attributed
        return label
    }

    private func rowTitle(frame: NSRect, text: String) -> NSTextField {
        let label = label(frame: frame, text: text, fontSize: 13.5, bold: false)
        label.font = .systemFont(ofSize: 13.5, weight: .medium)
        label.textColor = MatcherColors.foreground
        return label
    }

    private func rowSubtitle(frame: NSRect, text: String) -> NSTextField {
        let label = label(frame: frame, text: text, fontSize: 11, bold: false)
        label.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        label.textColor = MatcherColors.muted
        return label
    }

    @objc private func togglePopover(_ sender: Any?) {
        guard let button = statusItem?.button else {
            return
        }

        buildPopover()

        if popover?.isShown == true {
            popover?.performClose(sender)
            return
        }

        refreshStartAtLoginCheckbox()
        refreshDevicePreview()
        updateAppState(status: isFilterRunning ? "Running" : "Stopped")
        popover?.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        startClickMonitors()
        startTouchStream()

        if !isFilterRunning {
            startFilter(nil)
        }
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
        startAtLoginSwitch?.setOn(isStartAtLoginEnabled, animated: false)
    }

    private func refreshMatchActiveAreaCheckbox() {
        matchActiveAreaSwitch?.setOn(matchActiveAreaEnabled, animated: false)
        reduceSubtitleLabel?.stringValue = matchActiveAreaEnabled
            ? "active area matches built-in"
            : "match it to the built-in trackpad"
    }

    @objc private func toggleMatchActiveArea(_ sender: Any?) {
        matchActiveAreaEnabled = matchActiveAreaSwitch?.isOn == true
        reduceSubtitleLabel?.stringValue = matchActiveAreaEnabled
            ? "active area matches built-in"
            : "match it to the built-in trackpad"

        if deviceSurfaces.isEmpty {
            refreshDevicePreview()
        } else {
            devicesPreviewView?.matchActiveAreaEnabled = matchActiveAreaEnabled
        }

        appendLogLine("Deadpad app \(matchActiveAreaEnabled ? "enabled" : "disabled") Reduce active area.")

        if isFilterRunning {
            restartAfterStop = true
            stopFilter(nil)
        }
    }

    @objc private func toggleStartAtLogin(_ sender: Any?) {
        let enabled = startAtLoginSwitch?.isOn == true

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

    private func startTouchStream() {
        if touchStreamTask?.isRunning == true {
            return
        }

        let helperPath = self.helperPath
        guard FileManager.default.isExecutableFile(atPath: helperPath) else {
            return
        }

        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: helperPath)
        process.arguments = ["--stream-touches"]
        process.standardOutput = pipe
        touchStreamLogHandle = openLogHandle()
        process.standardError = touchStreamLogHandle

        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                return
            }

            DispatchQueue.main.async {
                self?.handleTouchStreamData(data)
            }
        }

        process.terminationHandler = { [weak self] finishedProcess in
            DispatchQueue.main.async {
                guard let self, self.touchStreamTask === finishedProcess else {
                    return
                }

                self.touchStreamPipe?.fileHandleForReading.readabilityHandler = nil
                self.touchStreamTask = nil
                self.touchStreamPipe = nil
                self.touchStreamLogHandle?.closeFile()
                self.touchStreamLogHandle = nil
                self.activeTouchIndicators.removeAll()
                self.publishTouchIndicators()
            }
        }

        do {
            try process.run()
        } catch {
            pipe.fileHandleForReading.readabilityHandler = nil
            touchStreamLogHandle?.closeFile()
            touchStreamLogHandle = nil
            appendLogLine("Deadpad app could not start touch stream: \(error.localizedDescription)")
            return
        }

        touchStreamTask = process
        touchStreamPipe = pipe
        startTouchCleanupTimer()
    }

    private func stopTouchStream() {
        touchCleanupTimer?.invalidate()
        touchCleanupTimer = nil
        touchStreamPipe?.fileHandleForReading.readabilityHandler = nil

        if touchStreamTask?.isRunning == true {
            touchStreamTask?.terminate()
        }

        touchStreamTask = nil
        touchStreamPipe = nil
        touchStreamLogHandle?.closeFile()
        touchStreamLogHandle = nil
        touchStreamBuffer.removeAll()
        activeTouchIndicators.removeAll()
        publishTouchIndicators()
    }

    private func startClickMonitors() {
        if localClickMonitor != nil || globalClickMonitor != nil {
            return
        }

        let clickMask: NSEvent.EventTypeMask = [
            .leftMouseDown,
            .leftMouseUp,
            .rightMouseDown,
            .rightMouseUp,
            .otherMouseDown,
            .otherMouseUp
        ]

        localClickMonitor = NSEvent.addLocalMonitorForEvents(matching: clickMask) { [weak self] event in
            self?.handleClickEvent(event)
            return event
        }

        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: clickMask) { [weak self] event in
            DispatchQueue.main.async {
                self?.handleClickEvent(event)
            }
        }
    }

    private func stopClickMonitors() {
        if let localClickMonitor {
            NSEvent.removeMonitor(localClickMonitor)
        }
        if let globalClickMonitor {
            NSEvent.removeMonitor(globalClickMonitor)
        }

        localClickMonitor = nil
        globalClickMonitor = nil
        setTouchPressed(false)
    }

    private func handleClickEvent(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            setTouchPressed(true)
        case .leftMouseUp, .rightMouseUp, .otherMouseUp:
            setTouchPressed(false)
        default:
            break
        }
    }

    private func setTouchPressed(_ pressed: Bool) {
        guard touchPressed != pressed else {
            return
        }

        touchPressed = pressed
        devicesPreviewView?.touchPressed = pressed
    }

    private func startTouchCleanupTimer() {
        if touchCleanupTimer != nil {
            return
        }

        let timer = Timer(timeInterval: 0.08, repeats: true) { [weak self] _ in
            self?.removeStaleTouches()
        }
        RunLoop.main.add(timer, forMode: .common)
        touchCleanupTimer = timer
    }

    private func handleTouchStreamData(_ data: Data) {
        touchStreamBuffer.append(data)
        let newline = Data([0x0A])

        while let range = touchStreamBuffer.range(of: newline) {
            let lineData = touchStreamBuffer.subdata(in: touchStreamBuffer.startIndex..<range.lowerBound)
            touchStreamBuffer.removeSubrange(touchStreamBuffer.startIndex...range.lowerBound)

            guard let line = String(data: lineData, encoding: .utf8) else {
                continue
            }

            handleTouchStreamLine(line.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    private func handleTouchStreamLine(_ line: String) {
        guard !line.isEmpty else {
            return
        }

        let parts = line.split(separator: " ")
        guard let event = parts.first else {
            return
        }

        var values: [String: String] = [:]
        for part in parts.dropFirst() {
            let pair = part.split(separator: "=", maxSplits: 1)
            if pair.count == 2 {
                values[String(pair[0])] = String(pair[1])
            }
        }

        switch event {
        case "touch":
            guard let deviceText = values["device"],
                  let pathText = values["path"],
                  let xText = values["x"],
                  let yText = values["y"],
                  let deviceIndex = Int(deviceText),
                  let pathIndex = Int(pathText),
                  let x = Double(xText),
                  let y = Double(yText) else {
                return
            }

            activeTouchIndicators[touchKey(deviceIndex: deviceIndex, pathIndex: pathIndex)] = TouchIndicator(
                deviceIndex: deviceIndex,
                pathIndex: pathIndex,
                x: x,
                y: y,
                lastSeen: Date()
            )
            publishTouchIndicators()
        case "touch-end":
            guard let deviceText = values["device"],
                  let pathText = values["path"],
                  let deviceIndex = Int(deviceText),
                  let pathIndex = Int(pathText) else {
                return
            }

            activeTouchIndicators.removeValue(forKey: touchKey(deviceIndex: deviceIndex, pathIndex: pathIndex))
            publishTouchIndicators()
        case "touch-clear":
            guard let deviceText = values["device"],
                  let deviceIndex = Int(deviceText) else {
                return
            }

            activeTouchIndicators = activeTouchIndicators.filter { _, touch in
                touch.deviceIndex != deviceIndex
            }
            publishTouchIndicators()
        default:
            return
        }
    }

    private func removeStaleTouches() {
        let now = Date()
        let freshTouches = activeTouchIndicators.filter { _, touch in
            now.timeIntervalSince(touch.lastSeen) <= 0.25
        }

        guard freshTouches.count != activeTouchIndicators.count else {
            return
        }

        activeTouchIndicators = freshTouches
        publishTouchIndicators()
    }

    private func publishTouchIndicators() {
        var grouped: [Int: [TouchIndicator]] = [:]
        for touch in activeTouchIndicators.values {
            grouped[touch.deviceIndex, default: []].append(touch)
        }

        devicesPreviewView?.touchIndicators = grouped
    }

    private func touchKey(deviceIndex: Int, pathIndex: Int) -> String {
        "\(deviceIndex):\(pathIndex)"
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
                title: "Deadpad helper not found",
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
                } else if status == 5 {
                    self.updateAppState(status: "Needs Accessibility")
                    self.showAccessibilityRequiredAlert()
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
            showError(title: "Could not start Deadpad", detail: error.localizedDescription)
            return
        }

        appendLogLine("Deadpad app started helper.")
        updateAppState(status: "Running")
    }

    @objc private func stopFilter(_ sender: Any?) {
        if !isFilterRunning {
            return
        }

        appendLogLine("Deadpad app stopping helper.")
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
        statusItem?.button?.toolTip = "Deadpad: \(status)"
    }

    private func showError(title: String, detail: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = detail
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func showAccessibilityRequiredAlert() {
        showError(
            title: "Accessibility permission required",
            detail: """
            macOS blocked Deadpad's event tap, so the filter is not running yet.

            In System Settings > Privacy & Security > Accessibility, enable Deadpad or its bundled deadpad helper, then open the DP popover again.

            If it is already enabled, toggle it off and on once to refresh the permission.
            """
        )
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
