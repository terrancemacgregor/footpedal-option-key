import Foundation
import IOKit
import IOKit.hid
import CoreGraphics
import Cocoa

// MARK: - Configuration

struct PedalConfig {
    static var vendorID: Int = 0x1A86
    static var productID: Int = 0xE026

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
    private var isPressed = false
    private var matchedDevice: IOHIDDevice?
    private var eventTap: CFMachPort?
    private var pedalConnected = false
    private var lastEventTime: UInt64 = 0
    private let debounceNanoseconds: UInt64 = 100_000_000

    var isEnabled = true
    weak var delegate: PedalStatusDelegate?

    init() {
        loadConfig()
        setupEventTap()
    }

    private func shouldProcessEvent() -> Bool {
        var timebase = mach_timebase_info_data_t()
        mach_timebase_info(&timebase)
        let now = mach_absolute_time() * UInt64(timebase.numer) / UInt64(timebase.denom)

        if now - lastEventTime < debounceNanoseconds {
            return false
        }

        lastEventTime = now
        return true
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
        guard pedalConnected && isEnabled else {
            return Unmanaged.passUnretained(event)
        }

        if type == .keyDown || type == .keyUp {
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

    func updateStatusIcon(connected: Bool, pressed: Bool) {
        if let button = statusItem.button {
            // Use SF Symbols for cleaner look
            let symbolName: String
            if pressed {
                symbolName = "foot.fill"
            } else if connected {
                symbolName = "circle.fill"
            } else {
                symbolName = "circle"
            }

            if let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "Foot Pedal") {
                image.isTemplate = true  // Adapts to menu bar appearance
                button.image = image
                button.title = ""
            } else {
                // Fallback for older macOS
                if pressed {
                    button.title = "●"
                } else if connected {
                    button.title = "◉"
                } else {
                    button.title = "○"
                }
                button.image = nil
            }
        }
    }

    func updateMenu() {
        if let menu = statusItem.menu,
           let statusItem = menu.item(withTag: 100) {
            statusItem.title = isPedalConnected ? "Pedal: Connected" : "Pedal: Disconnected"
        }
    }

    @objc func toggleEnabled() {
        pedalManager.isEnabled.toggle()
        if let menu = statusItem.menu,
           let enableItem = menu.item(withTag: 101) {
            enableItem.state = pedalManager.isEnabled ? .on : .off
        }
    }

    @objc func quit() {
        pedalManager.stop()
        NSApp.terminate(nil)
    }

    // MARK: - PedalStatusDelegate

    func pedalConnected() {
        isPedalConnected = true
        updateStatusIcon(connected: true, pressed: false)
        updateMenu()
    }

    func pedalDisconnected() {
        isPedalConnected = false
        updateStatusIcon(connected: false, pressed: false)
        updateMenu()
    }

    func pedalPressed() {
        updateStatusIcon(connected: true, pressed: true)
    }

    func pedalReleased() {
        updateStatusIcon(connected: true, pressed: false)
    }
}

// MARK: - Main

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
