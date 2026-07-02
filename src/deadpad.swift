import ApplicationServices
import CoreFoundation
import Darwin
import Foundation

typealias DeviceRef = UnsafeRawPointer?
typealias ContactFrameCallback = @convention(c) (
    DeviceRef,
    UnsafeMutablePointer<MTTouch>?,
    Int32,
    Double,
    Int32
) -> Void

typealias MTDeviceCreateListFn = @convention(c) () -> CFArray?
typealias MTDeviceStartFn = @convention(c) (DeviceRef, CInt) -> CInt
typealias MTDeviceStopFn = @convention(c) (DeviceRef) -> Void
typealias MTRegisterContactFrameCallbackFn = @convention(c) (DeviceRef, ContactFrameCallback?) -> Void
typealias MTUnregisterContactFrameCallbackFn = @convention(c) (DeviceRef, ContactFrameCallback?) -> Void
typealias MTDeviceIsBuiltInFn = @convention(c) (DeviceRef) -> Bool
typealias MTDeviceGetDeviceIDFn = @convention(c) (DeviceRef, UnsafeMutablePointer<UInt64>?) -> CInt
typealias MTDeviceGetSensorSurfaceDimensionsFn = @convention(c) (
    DeviceRef,
    UnsafeMutablePointer<Int32>?,
    UnsafeMutablePointer<Int32>?
) -> CInt

enum BlockPolicy {
    case allDead
    case anyDead
}

struct Options {
    var leftNorm = 0.125
    var rightNorm = 0.125
    var topNorm = 0.0
    var bottomNorm = 0.0
    var leftCm = 0.0
    var rightCm = 0.0
    var topCm = 0.0
    var bottomCm = 0.0
    var hasLeftCm = false
    var hasRightCm = false
    var hasTopCm = false
    var hasBottomCm = false
    var invertX = false
    var invertY = false
    var deviceIndex = -1
    var graceMs = 120
    var policy = BlockPolicy.allDead
    var listDevices = false
    var monitorOnly = false
    var streamTouches = false
    var verbose = false
}

struct TouchSlot {
    var present = false
    var pathIndex: Int32 = 0
    var startedDead = false
    var x = 0.0
    var y = 0.0
    var lastSeenMs: UInt64 = 0
}

struct MultitouchAPI {
    var handle: UnsafeMutableRawPointer?
    var createList: MTDeviceCreateListFn?
    var start: MTDeviceStartFn?
    var stop: MTDeviceStopFn?
    var registerContactFrame: MTRegisterContactFrameCallbackFn?
    var unregisterContactFrame: MTUnregisterContactFrameCallbackFn?
    var isBuiltIn: MTDeviceIsBuiltInFn?
    var getDeviceID: MTDeviceGetDeviceIDFn?
    var getSensorSurfaceDimensions: MTDeviceGetSensorSurfaceDimensionsFn?
}

final class DeadPadRuntime {
    var options = Options()
    var multitouch = MultitouchAPI()
    var selectedDevice: DeviceRef = nil
    var streamDevices: [DeviceRef] = []
    var eventTap: CFMachPort?
    var shouldStop = false

    private var deviceIndices: [UInt: Int] = [:]
    private var touches = Array(repeating: TouchSlot(), count: 64)
    private var blockUntilMs: UInt64 = 0
    private var suppressedEvents: UInt32 = 0
    private var blockedFrames: UInt32 = 0
    private var activeTouches: UInt32 = 0
    private var lastLogMs: UInt64 = 0
    private let lock = NSLock()

    func parseArguments(_ arguments: [String]) -> Bool {
        var index = 1
        while index < arguments.count {
            let arg = arguments[index]
            let next = index + 1 < arguments.count ? arguments[index + 1] : nil

            switch arg {
            case "--help", "-h":
                printUsage(program: arguments[0])
                exit(0)
            case "--list-devices":
                options.listDevices = true
            case "--monitor":
                options.monitorOnly = true
                options.verbose = true
            case "--stream-touches":
                options.streamTouches = true
                options.monitorOnly = true
            case "--verbose":
                options.verbose = true
            case "--invert-x":
                options.invertX = true
            case "--invert-y":
                options.invertY = true
            case "--device":
                guard let next, let value = parseInt(next) else {
                    return false
                }
                options.deviceIndex = value
                index += 1
            case "--left":
                guard let next, let value = parseDouble(next) else {
                    return false
                }
                options.leftNorm = clamp01(value)
                index += 1
            case "--right":
                guard let next, let value = parseDouble(next) else {
                    return false
                }
                options.rightNorm = clamp01(value)
                index += 1
            case "--top":
                guard let next, let value = parseDouble(next) else {
                    return false
                }
                options.topNorm = clamp01(value)
                index += 1
            case "--bottom":
                guard let next, let value = parseDouble(next) else {
                    return false
                }
                options.bottomNorm = clamp01(value)
                index += 1
            case "--left-cm":
                guard let next, let value = parseDouble(next) else {
                    return false
                }
                options.leftCm = value
                options.hasLeftCm = true
                index += 1
            case "--right-cm":
                guard let next, let value = parseDouble(next) else {
                    return false
                }
                options.rightCm = value
                options.hasRightCm = true
                index += 1
            case "--top-cm":
                guard let next, let value = parseDouble(next) else {
                    return false
                }
                options.topCm = value
                options.hasTopCm = true
                index += 1
            case "--bottom-cm":
                guard let next, let value = parseDouble(next) else {
                    return false
                }
                options.bottomCm = value
                options.hasBottomCm = true
                index += 1
            case "--grace-ms":
                guard let next, let value = parseInt(next) else {
                    return false
                }
                options.graceMs = max(0, value)
                index += 1
            case "--policy":
                guard let next else {
                    return false
                }
                if next == "all" {
                    options.policy = .allDead
                } else if next == "any" {
                    options.policy = .anyDead
                } else {
                    return false
                }
                index += 1
            default:
                writeStderr("Unknown or incomplete option: \(arg)\n")
                return false
            }

            index += 1
        }

        return true
    }

    func printUsage(program: String) {
        writeStderr("""
        Usage: \(program) [options]

        Options:
          --list-devices              Print multitouch devices and exit.
          --monitor                   Print touches and block decisions; do not suppress events.
          --stream-touches            Stream touch points for UI previews; do not suppress events.
          --device INDEX              Use device at INDEX from --list-devices.
          --left N                    Left dead zone as normalized width, default 0.125.
          --right N                   Right dead zone as normalized width, default 0.125.
          --top N                     Top dead zone as normalized height, default 0.
          --bottom N                  Bottom dead zone as normalized height, default 0.
          --left-cm CM                Left dead zone in cm, using device surface width.
          --right-cm CM               Right dead zone in cm, using device surface width.
          --top-cm CM                 Top dead zone in cm, using device surface height.
          --bottom-cm CM              Bottom dead zone in cm, using device surface height.
          --policy all|any            all: block only if all active touches began dead; any: stricter.
                                      Default: all.
          --grace-ms MS               Continue blocking briefly after a dead touch frame. Default 120.
          --invert-x                  Flip x coordinate if calibration shows left/right inverted.
          --invert-y                  Flip y coordinate if calibration shows top/bottom inverted.
          --verbose                   Print block statistics once per second.
          --help                      Show this help.

        Examples:
          \(program) --list-devices
          \(program) --monitor --left-cm 2 --right-cm 2
          \(program) --left-cm 1.8 --right-cm 1.8 --policy all
        """)
        writeStderr("\n")
    }

    func loadMultitouchAPI() {
        let path = "/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport"
        guard let handle = dlopen(path, RTLD_LAZY | RTLD_LOCAL) else {
            let error = dlerror().map { String(cString: $0) } ?? "unknown error"
            writeStderr("Could not load \(path): \(error)\n")
            exit(2)
        }

        multitouch.handle = handle
        multitouch.createList = requireSymbol(handle, "MTDeviceCreateList", as: MTDeviceCreateListFn.self)
        multitouch.start = requireSymbol(handle, "MTDeviceStart", as: MTDeviceStartFn.self)
        multitouch.stop = requireSymbol(handle, "MTDeviceStop", as: MTDeviceStopFn.self)
        multitouch.registerContactFrame =
            requireSymbol(handle, "MTRegisterContactFrameCallback", as: MTRegisterContactFrameCallbackFn.self)
        multitouch.unregisterContactFrame =
            requireSymbol(handle, "MTUnregisterContactFrameCallback", as: MTUnregisterContactFrameCallbackFn.self)
        multitouch.isBuiltIn = optionalSymbol(handle, "MTDeviceIsBuiltIn", as: MTDeviceIsBuiltInFn.self)
        multitouch.getDeviceID = optionalSymbol(handle, "MTDeviceGetDeviceID", as: MTDeviceGetDeviceIDFn.self)
        multitouch.getSensorSurfaceDimensions =
            optionalSymbol(handle, "MTDeviceGetSensorSurfaceDimensions", as: MTDeviceGetSensorSurfaceDimensionsFn.self)
    }

    func createDeviceList() -> CFArray {
        guard let createList = multitouch.createList, let devices = createList() else {
            writeStderr("MTDeviceCreateList returned NULL.\n")
            exit(3)
        }
        return devices
    }

    func getSurfaceDimensions(device: DeviceRef) -> (width: Int32, height: Int32)? {
        guard let getSensorSurfaceDimensions = multitouch.getSensorSurfaceDimensions else {
            return nil
        }

        var width: Int32 = 0
        var height: Int32 = 0
        let result = getSensorSurfaceDimensions(device, &width, &height)
        if result == 0, width > 0, height > 0 {
            return (width, height)
        }
        if width > 0, height > 0 {
            return (width, height)
        }
        return nil
    }

    func printDevice(index: Int, device: DeviceRef) {
        let builtIn = multitouch.isBuiltIn?(device) ?? false
        var deviceID: UInt64 = 0
        if let getDeviceID = multitouch.getDeviceID {
            _ = getDeviceID(device, &deviceID)
        }

        writeStderr("[\(index)] id=\(deviceID) builtIn=\(builtIn ? "yes" : "no")")
        if let dimensions = getSurfaceDimensions(device: device) {
            let widthCm = Double(dimensions.width) / 1000.0
            let heightCm = Double(dimensions.height) / 1000.0
            writeStderr(String(format: " surface=%.2fcm x %.2fcm", widthCm, heightCm))
        } else {
            writeStderr(" surface=unknown")
        }
        writeStderr("\n")
    }

    func rememberDeviceIndices(from devices: CFArray) {
        deviceIndices.removeAll()
        let count = CFArrayGetCount(devices)
        for index in 0..<count {
            let device = CFArrayGetValueAtIndex(devices, index)
            deviceIndices[deviceKey(device)] = index
        }
    }

    func chooseDevice(from devices: CFArray) -> DeviceRef {
        let count = CFArrayGetCount(devices)
        if count <= 0 {
            writeStderr("No multitouch devices found.\n")
            exit(3)
        }

        if options.deviceIndex >= 0 {
            if options.deviceIndex >= count {
                writeStderr("Device index \(options.deviceIndex) is out of range. Available: 0..\(count - 1)\n")
                exit(3)
            }
            return CFArrayGetValueAtIndex(devices, options.deviceIndex)
        }

        var bestIndex = 0
        var bestScore = -1.0

        for index in 0..<count {
            let device = CFArrayGetValueAtIndex(devices, index)
            let builtIn = multitouch.isBuiltIn?(device) ?? false
            var area = 1.0
            if let dimensions = getSurfaceDimensions(device: device) {
                area = Double(dimensions.width) * Double(dimensions.height)
            }

            let score = area + (builtIn ? 0.0 : 1e12)
            if score > bestScore {
                bestScore = score
                bestIndex = index
            }
        }

        return CFArrayGetValueAtIndex(devices, bestIndex)
    }

    func resolveCmZones(device: DeviceRef) {
        let dimensions = getSurfaceDimensions(device: device)
        if dimensions == nil,
           options.hasLeftCm || options.hasRightCm || options.hasTopCm || options.hasBottomCm {
            writeStderr("Cannot use --*-cm options because the device surface size is unknown.\n")
            exit(4)
        }

        let widthCm = Double(dimensions?.width ?? 0) / 1000.0
        let heightCm = Double(dimensions?.height ?? 0) / 1000.0

        if options.hasLeftCm {
            options.leftNorm = clamp01(options.leftCm / widthCm)
        }
        if options.hasRightCm {
            options.rightNorm = clamp01(options.rightCm / widthCm)
        }
        if options.hasTopCm {
            options.topNorm = clamp01(options.topCm / heightCm)
        }
        if options.hasBottomCm {
            options.bottomNorm = clamp01(options.bottomCm / heightCm)
        }

        if dimensions != nil {
            writeStderr(String(
                format: "Selected surface %.2fcm x %.2fcm. Dead zones: left %.2fcm, right %.2fcm, top %.2fcm, bottom %.2fcm.\n",
                widthCm,
                heightCm,
                options.leftNorm * widthCm,
                options.rightNorm * widthCm,
                options.topNorm * heightCm,
                options.bottomNorm * heightCm
            ))
        } else {
            writeStderr(String(
                format: "Selected surface size unknown. Dead zones: left %.1f%%, right %.1f%%, top %.1f%%, bottom %.1f%%.\n",
                options.leftNorm * 100.0,
                options.rightNorm * 100.0,
                options.topNorm * 100.0,
                options.bottomNorm * 100.0
            ))
        }
    }

    func registerTouchCallback(device: DeviceRef) {
        multitouch.registerContactFrame?(device, contactFrameCallback)
    }

    func unregisterTouchCallback(device: DeviceRef) {
        multitouch.unregisterContactFrame?(device, contactFrameCallback)
    }

    func startDevice(device: DeviceRef) {
        guard let start = multitouch.start else {
            return
        }

        let result = start(device, 0)
        if result != 0 {
            writeStderr("MTDeviceStart returned \(result). Continuing in case callbacks still arrive.\n")
        }
    }

    func stopDevice(device: DeviceRef) {
        multitouch.stop?(device)
    }

    func contactFrame(device: DeviceRef, touches touchesPointer: UnsafeMutablePointer<MTTouch>?, touchCount: Int32) {
        guard let touchesPointer else {
            return
        }

        if options.streamTouches {
            streamTouchFrame(device: device, touches: touchesPointer, touchCount: touchCount)
            return
        }

        let now = nowMs()
        var touchStartLogs: [String] = []
        var snapshot: (active: UInt32, dead: UInt32, blocking: Bool)

        lock.lock()
        for index in touches.indices {
            if touches[index].present, now - touches[index].lastSeenMs > 2000 {
                touches[index] = TouchSlot()
            }
        }

        if touchCount > 0 {
            for index in 0..<Int(touchCount) {
                let touch = touchesPointer[index]
                let x = normalizedX(touch)
                let y = normalizedY(touch)

                if isReleaseState(touch.state, touch.zTotal) {
                    clearTouchSlot(pathIndex: touch.pathIndex)
                    continue
                }

                if !isContactState(touch.state, touch.zTotal) {
                    continue
                }

                guard let slotIndex = allocateTouchSlot(pathIndex: touch.pathIndex) else {
                    continue
                }

                let newTouch = touches[slotIndex].lastSeenMs == 0
                if newTouch {
                    touches[slotIndex].startedDead = isDeadZone(x: x, y: y)
                    if options.monitorOnly || options.verbose {
                        touchStartLogs.append(String(
                            format: "touch start path=%d state=%d x=%.3f y=%.3f dead=%@\n",
                            touch.pathIndex,
                            touch.state,
                            x,
                            y,
                            touches[slotIndex].startedDead ? "yes" : "no"
                        ))
                    }
                }

                touches[slotIndex].x = x
                touches[slotIndex].y = y
                touches[slotIndex].lastSeenMs = now
            }
        }

        var active: UInt32 = 0
        var dead: UInt32 = 0
        for slot in touches where slot.present && now - slot.lastSeenMs <= 250 {
            active += 1
            if slot.startedDead {
                dead += 1
            }
        }

        var blocking = false
        if dead > 0 {
            blocking = options.policy == .anyDead ? true : dead == active
        }

        activeTouches = active
        if blocking {
            blockUntilMs = now + UInt64(options.graceMs)
            blockedFrames += 1
        }

        snapshot = (active, dead, blocking)
        lock.unlock()

        for line in touchStartLogs {
            writeStderr(line)
        }
        printFrameLog(now: now, touchCount: touchCount, active: snapshot.active, dead: snapshot.dead, blocking: snapshot.blocking)
    }

    func shouldSuppressEventNow() -> Bool {
        let now = nowMs()
        lock.lock()
        let shouldSuppress = now <= blockUntilMs
        if shouldSuppress {
            suppressedEvents += 1
        }
        lock.unlock()
        return shouldSuppress
    }

    func createEventTap() {
        let mask = eventMask(.leftMouseDown) |
            eventMask(.leftMouseUp) |
            eventMask(.rightMouseDown) |
            eventMask(.rightMouseUp) |
            eventMask(.mouseMoved) |
            eventMask(.leftMouseDragged) |
            eventMask(.rightMouseDragged) |
            eventMask(.otherMouseDown) |
            eventMask(.otherMouseUp) |
            eventMask(.otherMouseDragged) |
            eventMask(.scrollWheel)

        eventTap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: eventTapCallback,
            userInfo: nil
        )

        guard let eventTap else {
            writeStderr("Could not create HID event tap. Grant Accessibility permission and try again.\n")
            exit(5)
        }

        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0) else {
            writeStderr("Could not create run loop source for HID event tap.\n")
            exit(5)
        }

        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)
    }

    func reenableEventTapIfNeeded() {
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: true)
        }
    }

    func printSelectedSummary() {
        writeStderr("Policy=\(options.policy == .allDead ? "all" : "any"), grace=\(options.graceMs)ms, mode=\(options.monitorOnly ? "monitor" : "filter"). Press Ctrl-C to stop.\n")
        writeStderr(String(
            format: "Dead zone normalized: left=%.3f right=%.3f top=%.3f bottom=%.3f%@%@\n",
            options.leftNorm,
            options.rightNorm,
            options.topNorm,
            options.bottomNorm,
            options.invertX ? " invertX" : "",
            options.invertY ? " invertY" : ""
        ))
    }

    private func normalizedX(_ touch: MTTouch) -> Double {
        let x = clamp01(Double(touch.normalized.position.x))
        return options.invertX ? 1.0 - x : x
    }

    private func normalizedY(_ touch: MTTouch) -> Double {
        let y = clamp01(Double(touch.normalized.position.y))
        return options.invertY ? 1.0 - y : y
    }

    private func isDeadZone(x: Double, y: Double) -> Bool {
        if x <= options.leftNorm {
            return true
        }
        if x >= 1.0 - options.rightNorm {
            return true
        }
        if y <= options.bottomNorm {
            return true
        }
        if y >= 1.0 - options.topNorm {
            return true
        }
        return false
    }

    private func findTouchSlot(pathIndex: Int32) -> Int? {
        touches.firstIndex { $0.present && $0.pathIndex == pathIndex }
    }

    private func allocateTouchSlot(pathIndex: Int32) -> Int? {
        if let existingIndex = findTouchSlot(pathIndex: pathIndex) {
            return existingIndex
        }

        guard let emptyIndex = touches.firstIndex(where: { !$0.present }) else {
            return nil
        }

        touches[emptyIndex] = TouchSlot(
            present: true,
            pathIndex: pathIndex,
            startedDead: false,
            x: 0.0,
            y: 0.0,
            lastSeenMs: 0
        )
        return emptyIndex
    }

    private func clearTouchSlot(pathIndex: Int32) {
        if let index = findTouchSlot(pathIndex: pathIndex) {
            touches[index] = TouchSlot()
        }
    }

    private func printFrameLog(now: UInt64, touchCount: Int32, active: UInt32, dead: UInt32, blocking: Bool) {
        guard options.verbose else {
            return
        }

        lock.lock()
        if now - lastLogMs < 1000 {
            lock.unlock()
            return
        }
        lastLogMs = now
        let suppressed = suppressedEvents
        let blocked = blockedFrames
        suppressedEvents = 0
        blockedFrames = 0
        lock.unlock()

        writeStderr("touches=\(touchCount) active=\(active) dead-start=\(dead) blocking=\(blocking ? "yes" : "no") suppressed/s=\(suppressed) blockedFrames/s=\(blocked)\n")
    }

    private func streamTouchFrame(
        device: DeviceRef,
        touches touchesPointer: UnsafeMutablePointer<MTTouch>,
        touchCount: Int32
    ) {
        let deviceIndex = deviceIndices[deviceKey(device)] ?? -1

        if touchCount <= 0 {
            writeStdout("touch-clear device=\(deviceIndex)\n")
            return
        }

        for index in 0..<Int(touchCount) {
            let touch = touchesPointer[index]

            if isReleaseState(touch.state, touch.zTotal) {
                writeStdout("touch-end device=\(deviceIndex) path=\(touch.pathIndex)\n")
                continue
            }

            guard isContactState(touch.state, touch.zTotal) else {
                continue
            }

            let x = normalizedX(touch)
            let y = normalizedY(touch)
            writeStdout(String(
                format: "touch device=%d path=%d x=%.5f y=%.5f\n",
                deviceIndex,
                touch.pathIndex,
                x,
                y
            ))
        }
    }
}

let runtime = DeadPadRuntime()

func writeStdout(_ text: String) {
    if let data = text.data(using: .utf8) {
        FileHandle.standardOutput.write(data)
    }
}

func writeStderr(_ text: String) {
    if let data = text.data(using: .utf8) {
        FileHandle.standardError.write(data)
    }
}

func clamp01(_ value: Double) -> Double {
    if value < 0.0 {
        return 0.0
    }
    if value > 1.0 {
        return 1.0
    }
    return value
}

func parseDouble(_ value: String) -> Double? {
    guard let parsed = Double(value), parsed.isFinite else {
        return nil
    }
    return parsed
}

func parseInt(_ value: String) -> Int? {
    Int(value)
}

func nowMs() -> UInt64 {
    UInt64(Date().timeIntervalSince1970 * 1000.0)
}

func deviceKey(_ device: DeviceRef) -> UInt {
    guard let device else {
        return 0
    }

    return UInt(bitPattern: device)
}

func requireSymbol<T>(_ handle: UnsafeMutableRawPointer, _ name: String, as type: T.Type) -> T {
    guard let symbol = dlsym(handle, name) else {
        writeStderr("Missing MultitouchSupport symbol: \(name)\n")
        exit(2)
    }
    return unsafeBitCast(symbol, to: T.self)
}

func optionalSymbol<T>(_ handle: UnsafeMutableRawPointer, _ name: String, as type: T.Type) -> T? {
    guard let symbol = dlsym(handle, name) else {
        return nil
    }
    return unsafeBitCast(symbol, to: T.self)
}

func isContactState(_ state: Int32, _ zTotal: Float) -> Bool {
    if state == 3 || state == 4 || state == 5 {
        return true
    }
    return zTotal > 0.001
}

func isReleaseState(_ state: Int32, _ zTotal: Float) -> Bool {
    if state == 6 || state == 7 {
        return true
    }
    return zTotal <= 0.001
}

func isSuppressibleEvent(_ type: CGEventType) -> Bool {
    switch type {
    case .leftMouseDown,
         .leftMouseUp,
         .rightMouseDown,
         .rightMouseUp,
         .mouseMoved,
         .leftMouseDragged,
         .rightMouseDragged,
         .otherMouseDown,
         .otherMouseUp,
         .otherMouseDragged,
         .scrollWheel:
        return true
    default:
        return false
    }
}

func eventMask(_ type: CGEventType) -> CGEventMask {
    CGEventMask(1) << CGEventMask(type.rawValue)
}

func requestAccessibilityPrompt() {
    let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
    let options = [key: true] as CFDictionary
    let trusted = AXIsProcessTrustedWithOptions(options)

    if !trusted {
        writeStderr("""
        Accessibility permission is not granted yet. macOS may show a prompt.
        If the event tap fails, enable this binary or Terminal in:
        System Settings > Privacy & Security > Accessibility.
        """)
        writeStderr("\n")
    }
}

func signalHandler(_ signal: Int32) {
    runtime.shouldStop = true
    CFRunLoopStop(CFRunLoopGetMain())
}

func keepAliveTimerCallback(timer: CFRunLoopTimer?, info: UnsafeMutableRawPointer?) {
}

func contactFrameCallback(
    device: DeviceRef,
    touches: UnsafeMutablePointer<MTTouch>?,
    touchCount: Int32,
    timestamp: Double,
    frame: Int32
) {
    runtime.contactFrame(device: device, touches: touches, touchCount: touchCount)
}

func eventTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        runtime.reenableEventTapIfNeeded()
        return Unmanaged.passUnretained(event)
    }

    if !isSuppressibleEvent(type) {
        return Unmanaged.passUnretained(event)
    }

    if runtime.shouldSuppressEventNow() {
        return nil
    }

    return Unmanaged.passUnretained(event)
}

func runDeadPad() -> Int32 {
    if !runtime.parseArguments(CommandLine.arguments) {
        runtime.printUsage(program: CommandLine.arguments[0])
        return 1
    }

    signal(SIGINT, signalHandler)
    signal(SIGTERM, signalHandler)

    runtime.loadMultitouchAPI()
    let devices = runtime.createDeviceList()
    let count = CFArrayGetCount(devices)

    if runtime.options.listDevices {
        for index in 0..<count {
            runtime.printDevice(index: index, device: CFArrayGetValueAtIndex(devices, index))
        }
        return 0
    }

    runtime.rememberDeviceIndices(from: devices)

    if runtime.options.streamTouches {
        for index in 0..<count {
            let device = CFArrayGetValueAtIndex(devices, index)
            runtime.streamDevices.append(device)
            runtime.registerTouchCallback(device: device)
            runtime.startDevice(device: device)
        }

        let timer = CFRunLoopTimerCreate(
            kCFAllocatorDefault,
            CFAbsoluteTimeGetCurrent() + 3600.0,
            3600.0,
            0,
            0,
            keepAliveTimerCallback,
            nil
        )

        if let timer {
            CFRunLoopAddTimer(CFRunLoopGetMain(), timer, .commonModes)
        }

        CFRunLoopRun()

        if let timer {
            CFRunLoopRemoveTimer(CFRunLoopGetMain(), timer, .commonModes)
        }

        for device in runtime.streamDevices {
            runtime.unregisterTouchCallback(device: device)
            runtime.stopDevice(device: device)
        }

        return 0
    }

    runtime.selectedDevice = runtime.chooseDevice(from: devices)
    writeStderr("Selected multitouch device:\n")
    let selectedIndex = CFArrayGetFirstIndexOfValue(
        devices,
        CFRange(location: 0, length: count),
        runtime.selectedDevice
    )
    runtime.printDevice(index: selectedIndex, device: runtime.selectedDevice)
    runtime.resolveCmZones(device: runtime.selectedDevice)
    runtime.printSelectedSummary()

    runtime.registerTouchCallback(device: runtime.selectedDevice)
    runtime.startDevice(device: runtime.selectedDevice)

    if !runtime.options.monitorOnly {
        requestAccessibilityPrompt()
        runtime.createEventTap()
    }

    let timer = CFRunLoopTimerCreate(
        kCFAllocatorDefault,
        CFAbsoluteTimeGetCurrent() + 3600.0,
        3600.0,
        0,
        0,
        keepAliveTimerCallback,
        nil
    )

    if let timer {
        CFRunLoopAddTimer(CFRunLoopGetMain(), timer, .commonModes)
    }

    CFRunLoopRun()

    if let timer {
        CFRunLoopRemoveTimer(CFRunLoopGetMain(), timer, .commonModes)
    }

    if runtime.selectedDevice != nil {
        runtime.unregisterTouchCallback(device: runtime.selectedDevice)
        runtime.stopDevice(device: runtime.selectedDevice)
    }

    writeStderr("Stopped.\n")
    return 0
}

@main
enum DeadPadCommand {
    static func main() {
        exit(runDeadPad())
    }
}
