import Foundation
import IOKit
import IOKit.hid
import CoreGraphics

// MARK: - Configuration

/// iKKEGOL USB Foot Pedal typical identifiers
/// Run `discover-pedal.sh` to find your specific device's Vendor ID and Product ID
struct PedalConfig {
    // Common iKKEGOL foot pedal identifiers (FS2007U1SW)
    // These may vary - use discover-pedal.sh to find your exact values
    static var vendorID: Int = 0x1A86   // QinHeng Electronics (common for iKKEGOL)
    static var productID: Int = 0xE026  // USB foot pedal

    // Alternative common VID/PID combinations for iKKEGOL pedals:
    // VID: 0x0C45 (Microdia), PID: 0x7403
    // VID: 0x1A86 (QinHeng), PID: 0xE026
    // VID: 0x04D9 (Holtek), PID: varies

    static let configFile = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config/footpedal/config.json")
}

// MARK: - Event Injection

/// Injects Option key press/release events into the macOS event system
func injectOptionKey(keyDown: Bool) {
    let keyCode: CGKeyCode = 58  // Left Option key

    guard let source = CGEventSource(stateID: .privateState) else {
        print("Error: Could not create event source")
        return
    }

    // Create a flagsChanged event - this is what modifier keys actually generate
    guard let event = CGEvent(source: source) else {
        print("Error: Could not create event")
        return
    }

    event.type = .flagsChanged
    event.setIntegerValueField(.keyboardEventKeycode, value: Int64(keyCode))

    if keyDown {
        event.flags = .maskAlternate
    } else {
        event.flags = []
    }

    // Post at HID level for better compatibility
    event.post(tap: .cghidEventTap)

    let action = keyDown ? "pressed" : "released"
    print("Option key \(action)")
}

// MARK: - HID Manager

class FootPedalManager {
    private var hidManager: IOHIDManager?
    private var isPressed = false
    private var matchedDevice: IOHIDDevice?
    private var eventTap: CFMachPort?
    private var pedalConnected = false

    init() {
        loadConfig()
        setupEventTap()
    }

    /// Set up a CGEventTap to block the "b" key and add Option modifier while pedal is held
    private func setupEventTap() {
        // Include keyboard, mouse, and flags events
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
            print("Warning: Could not create event tap for blocking pedal keystrokes")
            print("         Add app to Accessibility in System Preferences")
            return
        }

        let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        print("Event tap installed for blocking pedal keystrokes")
    }

    /// Handle events - block "b" and add Option modifier when pedal is held
    private func handleKeyEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        guard pedalConnected else {
            return Unmanaged.passUnretained(event)
        }

        // For keyboard events, block "b" from the pedal
        if type == .keyDown || type == .keyUp {
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
            // Key code 11 = "b" on US keyboard - block it
            if keyCode == 11 {
                return nil
            }
        }

        // If pedal is held down, add Option modifier to all events
        if isPressed {
            var flags = event.flags
            flags.insert(.maskAlternate)
            event.flags = flags
        }

        return Unmanaged.passUnretained(event)
    }

    /// Load configuration from file if it exists
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
                    print("Loaded config: VID=0x\(String(vid, radix: 16)), PID=0x\(String(pid, radix: 16))")
                }
            } catch {
                print("Warning: Could not load config file: \(error)")
            }
        }
    }

    func start() {
        print("FootPedal → Option Key Remapper")
        print("================================")
        print("Looking for device: VID=0x\(String(PedalConfig.vendorID, radix: 16)), PID=0x\(String(PedalConfig.productID, radix: 16))")
        print("")

        // Create HID Manager
        hidManager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))

        guard let manager = hidManager else {
            print("Error: Could not create HID Manager")
            exit(1)
        }

        // Set up device matching for the specific foot pedal
        let matchingDict: [String: Any] = [
            kIOHIDVendorIDKey as String: PedalConfig.vendorID,
            kIOHIDProductIDKey as String: PedalConfig.productID
        ]

        IOHIDManagerSetDeviceMatching(manager, matchingDict as CFDictionary)

        // Register callbacks
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

        // Schedule with run loop
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)

        // Open the HID Manager
        let openResult = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        if openResult != kIOReturnSuccess {
            print("Error: Could not open HID Manager (code: \(openResult))")
            print("Make sure the application has Input Monitoring permission in System Preferences.")
            exit(1)
        }

        print("Waiting for foot pedal...")
        print("Press Ctrl+C to exit")
        print("")

        // Run the event loop
        CFRunLoopRun()
    }

    private func deviceConnected(_ device: IOHIDDevice) {
        matchedDevice = device

        // Get device info
        let vendorID = getDeviceProperty(device, key: kIOHIDVendorIDKey) ?? 0
        let productID = getDeviceProperty(device, key: kIOHIDProductIDKey) ?? 0
        let product = getDeviceStringProperty(device, key: kIOHIDProductKey) ?? "Unknown"
        let manufacturer = getDeviceStringProperty(device, key: kIOHIDManufacturerKey) ?? "Unknown"

        // Mark pedal as connected (enables "b" key blocking)
        pedalConnected = true

        // Try to seize the device exclusively
        let seizeResult = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeSeizeDevice))
        if seizeResult == kIOReturnSuccess {
            print("✓ Foot pedal connected and seized exclusively!")
        } else {
            print("✓ Foot pedal connected (blocking 'b' key via event tap)")
        }

        print("  Manufacturer: \(manufacturer)")
        print("  Product: \(product)")
        print("  VID: 0x\(String(vendorID, radix: 16)), PID: 0x\(String(productID, radix: 16))")
        print("")
        print("Ready! Step on pedal to activate Option key.")
        print("")
    }

    private func deviceDisconnected(_ device: IOHIDDevice) {
        print("✗ Foot pedal disconnected")

        // Stop blocking "b" key
        pedalConnected = false

        // Close the seized device
        IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
        matchedDevice = nil

        // Release Option key if it was pressed when device disconnected
        if isPressed {
            injectOptionKey(keyDown: false)
            isPressed = false
        }
    }

    private func handleInput(_ value: IOHIDValue) {
        let element = IOHIDValueGetElement(value)
        let usagePage = IOHIDElementGetUsagePage(element)
        let usage = IOHIDElementGetUsage(element)
        let intValue = IOHIDValueGetIntegerValue(value)

        // Debug output (uncomment for troubleshooting)
        // print("Input: usagePage=\(usagePage), usage=\(usage), value=\(intValue)")

        // Handle keyboard usage page (0x07)
        if usagePage == kHIDPage_KeyboardOrKeypad {
            // Any key press/release from the pedal
            let pressed = intValue != 0

            if pressed != isPressed {
                isPressed = pressed
                injectOptionKey(keyDown: pressed)
            }
            return
        }

        // Handle button usage page (0x09)
        if usagePage == kHIDPage_Button {
            let pressed = intValue != 0

            if pressed != isPressed {
                isPressed = pressed
                injectOptionKey(keyDown: pressed)
            }
            return
        }

        // Handle consumer usage page (0x0C) - some pedals use this
        if usagePage == kHIDPage_Consumer {
            let pressed = intValue != 0

            if pressed != isPressed {
                isPressed = pressed
                injectOptionKey(keyDown: pressed)
            }
            return
        }

        // Handle generic desktop page (0x01) - for generic controls
        if usagePage == kHIDPage_GenericDesktop {
            // Some pedals send generic desktop events
            if usage >= 0x80 && usage <= 0x83 {  // System controls
                let pressed = intValue != 0
                if pressed != isPressed {
                    isPressed = pressed
                    injectOptionKey(keyDown: pressed)
                }
            }
            return
        }
    }

    private func getDeviceProperty(_ device: IOHIDDevice, key: String) -> Int? {
        guard let value = IOHIDDeviceGetProperty(device, key as CFString) else {
            return nil
        }
        return (value as? NSNumber)?.intValue
    }

    private func getDeviceStringProperty(_ device: IOHIDDevice, key: String) -> String? {
        guard let value = IOHIDDeviceGetProperty(device, key as CFString) else {
            return nil
        }
        return value as? String
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

// MARK: - Signal Handling

var manager: FootPedalManager?

func signalHandler(signal: Int32) {
    print("\nShutting down...")
    manager?.stop()
    exit(0)
}

// MARK: - Main

signal(SIGINT, signalHandler)
signal(SIGTERM, signalHandler)

manager = FootPedalManager()
manager?.start()
