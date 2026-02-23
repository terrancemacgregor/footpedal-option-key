import Foundation
import IOKit
import IOKit.hid
import CoreGraphics
import Cocoa

// MARK: - Configuration

struct PedalConfig {
    static var vendorID: Int = 0x3553   // 13651 decimal - FootSwitch
    static var productID: Int = 0xB001  // 45057 decimal - FootSwitch

    static let configFile = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config/footpedal/config.json")
}

// MARK: - Event Injection

func injectOptionKey(keyDown: Bool) {
    let keyCode: CGKeyCode = 58  // Left Option key

    guard let source = CGEventSource(stateID: .privateState) else {
        return
    }

    guard let event = CGEvent(source: source) else {
        return
    }

    event.type = .flagsChanged
    event.setIntegerValueField(.keyboardEventKeycode, value: Int64(keyCode))

    if keyDown {
        event.flags = .maskAlternate
    } else {
        event.flags = []
    }

    event.post(tap: .cghidEventTap)
}

// MARK: - Status Update Protocol

protocol PedalStatusDelegate: AnyObject {
    func pedalConnected()
    func pedalDisconnected()
    func pedalPressed()
    func pedalReleased()
}

// MARK: - HID Manager

class FootPedalManager {
    private var hidManager: IOHIDManager?
    private(set) var isPressed = false
    private var matchedDevice: IOHIDDevice?
    private var eventTap: CFMachPort?
    private var pedalConnected = false
    private var lastEventTime: UInt64 = 0
    private let debounceNanoseconds: UInt64 = 100_000_000
    private var lastPedalHIDEventTime: UInt64 = 0
    private let pedalKeystrokeWindowNanoseconds: UInt64 = 150_000_000  // 150ms

    var isEnabled = true
    weak var delegate: PedalStatusDelegate?

    init() {
        loadConfig()
        setupEventTap()
    }

    private func currentNanoseconds() -> UInt64 {
        var timebase = mach_timebase_info_data_t()
        mach_timebase_info(&timebase)
        return mach_absolute_time() * UInt64(timebase.numer) / UInt64(timebase.denom)
    }

    private func shouldProcessEvent() -> Bool {
        let now = currentNanoseconds()

        if now - lastEventTime < debounceNanoseconds {
            return false
        }

        lastEventTime = now
        return true
    }

    private func isWithinPedalKeystrokeWindow() -> Bool {
        let now = currentNanoseconds()
        return now - lastPedalHIDEventTime < pedalKeystrokeWindowNanoseconds
    }

    private func setupEventTap() {
        let eventMask = (1 << CGEventType.keyDown.rawValue) |
                        (1 << CGEventType.keyUp.rawValue) |
                        (1 << CGEventType.flagsChanged.rawValue) |
                        (1 << CGEventType.leftMouseDown.rawValue) |
                        (1 << CGEventType.leftMouseUp.rawValue) |
                        (1 << CGEventType.rightMouseDown.rawValue) |
                        (1 << CGEventType.rightMouseUp.rawValue) |
                        (1 << CGEventType.leftMouseDragged.rawValue) |
                        (1 << CGEventType.rightMouseDragged.rawValue)

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
                guard let refcon = refcon else { return Unmanaged.passUnretained(event) }
                let manager = Unmanaged<FootPedalManager>.fromOpaque(refcon).takeUnretainedValue()
                return manager.handleKeyEvent(proxy: proxy, type: type, event: event)
            },
            userInfo: selfPtr
        )

        guard let tap = eventTap else {
            return
        }

        let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    private func handleKeyEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // Re-enable tap if it was disabled by timeout
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        guard pedalConnected && isEnabled else {
            return Unmanaged.passUnretained(event)
        }

        // Block "b" key (keycode 11) when the pedal is pressed OR within 150ms of
        // any pedal HID event. The timing window handles the race condition where a
        // rapid tap causes isPressed to flip back to false before the pedal's "b"
        // keystroke reaches the event tap.
        if (isPressed || isWithinPedalKeystrokeWindow()) && (type == .keyDown || type == .keyUp) {
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
            if keyCode == 11 {
                return nil
            }
        }

        if isPressed {
            var flags = event.flags
            flags.insert(.maskAlternate)
            event.flags = flags
        }

        return Unmanaged.passUnretained(event)
    }

    private func loadConfig() {
        let configPath = PedalConfig.configFile

        if FileManager.default.fileExists(atPath: configPath.path) {
            do {
                let data = try Data(contentsOf: configPath)
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let vid = json["vendorID"] as? Int,
                   let pid = json["productID"] as? Int {
                    PedalConfig.vendorID = vid
                    PedalConfig.productID = pid
                }
            } catch {
                // Use defaults
            }
        }
    }

    func start() {
        hidManager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))

        guard let manager = hidManager else {
            return
        }

        let matchingDict: [String: Any] = [
            kIOHIDVendorIDKey as String: PedalConfig.vendorID,
            kIOHIDProductIDKey as String: PedalConfig.productID
        ]

        IOHIDManagerSetDeviceMatching(manager, matchingDict as CFDictionary)

        let context = Unmanaged.passUnretained(self).toOpaque()

        IOHIDManagerRegisterDeviceMatchingCallback(manager, { context, result, sender, device in
            guard let ctx = context else { return }
            let manager = Unmanaged<FootPedalManager>.fromOpaque(ctx).takeUnretainedValue()
            manager.deviceConnected(device)
        }, context)

        IOHIDManagerRegisterDeviceRemovalCallback(manager, { context, result, sender, device in
            guard let ctx = context else { return }
            let manager = Unmanaged<FootPedalManager>.fromOpaque(ctx).takeUnretainedValue()
            manager.deviceDisconnected(device)
        }, context)

        IOHIDManagerRegisterInputValueCallback(manager, { context, result, sender, value in
            guard let ctx = context else { return }
            let manager = Unmanaged<FootPedalManager>.fromOpaque(ctx).takeUnretainedValue()
            manager.handleInput(value)
        }, context)

        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
    }

    private func deviceConnected(_ device: IOHIDDevice) {
        matchedDevice = device
        pedalConnected = true
        IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeSeizeDevice))

        DispatchQueue.main.async {
            self.delegate?.pedalConnected()
        }
    }

    private func deviceDisconnected(_ device: IOHIDDevice) {
        pedalConnected = false
        IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
        matchedDevice = nil

        if isPressed {
            injectOptionKey(keyDown: false)
            isPressed = false
        }

        DispatchQueue.main.async {
            self.delegate?.pedalDisconnected()
        }
    }

    private func handleInput(_ value: IOHIDValue) {
        guard isEnabled else { return }

        let element = IOHIDValueGetElement(value)
        let usagePage = IOHIDElementGetUsagePage(element)
        let usage = IOHIDElementGetUsage(element)
        let intValue = IOHIDValueGetIntegerValue(value)

        // Record timestamp for every pedal HID event so the event tap can
        // block the pedal's "b" keystroke even on rapid taps.
        lastPedalHIDEventTime = currentNanoseconds()

        if usagePage == kHIDPage_KeyboardOrKeypad {
            let pressed = intValue != 0
            if pressed != isPressed && shouldProcessEvent() {
                isPressed = pressed
                injectOptionKey(keyDown: pressed)
                DispatchQueue.main.async {
                    if pressed {
                        self.delegate?.pedalPressed()
                    } else {
                        self.delegate?.pedalReleased()
                    }
                }
            }
            return
        }

        if usagePage == kHIDPage_Button {
            let pressed = intValue != 0
            if pressed != isPressed && shouldProcessEvent() {
                isPressed = pressed
                injectOptionKey(keyDown: pressed)
                DispatchQueue.main.async {
                    if pressed {
                        self.delegate?.pedalPressed()
                    } else {
                        self.delegate?.pedalReleased()
                    }
                }
            }
            return
        }

        if usagePage == kHIDPage_Consumer {
            let pressed = intValue != 0
            if pressed != isPressed && shouldProcessEvent() {
                isPressed = pressed
                injectOptionKey(keyDown: pressed)
                DispatchQueue.main.async {
                    if pressed {
                        self.delegate?.pedalPressed()
                    } else {
                        self.delegate?.pedalReleased()
                    }
                }
            }
            return
        }

        if usagePage == kHIDPage_GenericDesktop {
            if usage >= 0x80 && usage <= 0x83 {
                let pressed = intValue != 0
                if pressed != isPressed && shouldProcessEvent() {
                    isPressed = pressed
                    injectOptionKey(keyDown: pressed)
                    DispatchQueue.main.async {
                        if pressed {
                            self.delegate?.pedalPressed()
                        } else {
                            self.delegate?.pedalReleased()
                        }
                    }
                }
            }
            return
        }
    }

    func stop() {
        if isPressed {
            injectOptionKey(keyDown: false)
        }

        if let manager = hidManager {
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        }
    }
}

// MARK: - App Delegate with Menu Bar

class AppDelegate: NSObject, NSApplicationDelegate, PedalStatusDelegate {
    var statusItem: NSStatusItem!
    var pedalManager: FootPedalManager!
    var isPedalConnected = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Create status bar item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        updateStatusIcon(connected: false, pressed: false)

        // Create menu
        let menu = NSMenu()

        let statusMenuItem = NSMenuItem(title: "Pedal: Disconnected", action: nil, keyEquivalent: "")
        statusMenuItem.tag = 100
        menu.addItem(statusMenuItem)

        menu.addItem(NSMenuItem.separator())

        let enableItem = NSMenuItem(title: "Enabled", action: #selector(toggleEnabled), keyEquivalent: "e")
        enableItem.state = .on
        enableItem.tag = 101
        menu.addItem(enableItem)

        menu.addItem(NSMenuItem.separator())

        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q"))

        statusItem.menu = menu

        // Start pedal manager
        pedalManager = FootPedalManager()
        pedalManager.delegate = self
        pedalManager.start()
    }

    func updateStatusIcon(connected: Bool, pressed: Bool, enabled: Bool = true) {
        if let button = statusItem.button {
            let showPressed = pressed && enabled
            let imageName = showPressed ? "footprint-on" : "footprint-off"
            let bundle = Bundle.main

            if let imagePath = bundle.pathForImageResource(imageName),
               let image = NSImage(contentsOfFile: imagePath) {
                image.size = NSSize(width: 18, height: 18)
                image.isTemplate = !showPressed
                button.image = image
                button.title = ""
                button.contentTintColor = nil
            } else {
                // Fallback to SF Symbols
                let symbolName = showPressed ? "foot.fill" : "foot"
                if let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "Foot Pedal") {
                    image.isTemplate = !showPressed
                    button.image = image
                    button.title = ""
                    button.contentTintColor = showPressed ? .controlAccentColor : nil
                } else {
                    button.title = "🦶"
                    button.image = nil
                }
            }

            button.alphaValue = enabled ? 1.0 : 0.3
        }
    }

    func updateMenu() {
        if let menu = statusItem.menu,
           let statusItem = menu.item(withTag: 100) {
            if !pedalManager.isEnabled {
                statusItem.title = "Pedal: Disabled"
            } else {
                statusItem.title = isPedalConnected ? "Pedal: Connected" : "Pedal: Disconnected"
            }
        }
    }

    @objc func toggleEnabled() {
        let wasPressed = pedalManager.isPressed
        pedalManager.isEnabled.toggle()
        let enabled = pedalManager.isEnabled

        // Release Option key if disabling while pedal is held
        if !enabled && wasPressed {
            injectOptionKey(keyDown: false)
        }

        if let menu = statusItem.menu,
           let enableItem = menu.item(withTag: 101) {
            enableItem.state = enabled ? .on : .off
        }

        updateStatusIcon(connected: isPedalConnected, pressed: false, enabled: enabled)
        updateMenu()
    }

    @objc func quit() {
        pedalManager.stop()
        NSApp.terminate(nil)
    }

    // MARK: - PedalStatusDelegate

    func pedalConnected() {
        isPedalConnected = true
        updateStatusIcon(connected: true, pressed: false, enabled: pedalManager.isEnabled)
        updateMenu()
    }

    func pedalDisconnected() {
        isPedalConnected = false
        updateStatusIcon(connected: false, pressed: false, enabled: pedalManager.isEnabled)
        updateMenu()
    }

    func pedalPressed() {
        updateStatusIcon(connected: true, pressed: true, enabled: pedalManager.isEnabled)
    }

    func pedalReleased() {
        updateStatusIcon(connected: true, pressed: false, enabled: pedalManager.isEnabled)
    }
}

// MARK: - Main

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
