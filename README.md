# FootPedalOptionKey

A macOS utility that remaps a USB foot pedal to act as the Option key. Step on the pedal to hold Option, release to let go.

## Device

**iKKEGOL [Upgraded] USB Foot Pedal Switch** (Model: FS2007U1SW)

## Requirements

- macOS 12.0 (Monterey) or later
- Xcode Command Line Tools (`xcode-select --install`)
- Swift 5.7+

## Quick Start

### 1. Discover Your Pedal's USB IDs

```bash
./scripts/discover-pedal.sh
```

Follow the prompts to identify your pedal's Vendor ID and Product ID.

### 2. Configure the IDs

```bash
./scripts/configure-pedal.sh 0x3553 0xB001
```

Replace with your actual Vendor ID and Product ID from step 1.

### 3. Build

```bash
./scripts/build.sh
```

### 4. Install

```bash
./scripts/install.sh
```

### 5. Grant Permissions

**This is required for the app to work!**

1. Open **System Settings → Privacy & Security → Accessibility**
2. Click the **+** button
3. Navigate to `/Applications/FootPedalOptionKey.app`
4. Add the application and ensure it's toggled **ON**

### 6. Start the Service

```bash
./scripts/start.sh
```

The service will now start automatically on login.

## Usage

Once running, the foot pedal works like this:

- **Press pedal down** → Option key held
- **Release pedal** → Option key released

This works with any application. For example:
- Hold pedal + click = Option-click
- Hold pedal + drag = Option-drag (copy in Finder)
- Hold pedal + type = Option key combinations
- Hold pedal with Whisper = push-to-talk recording

## Scripts

| Script | Description |
|--------|-------------|
| `scripts/discover-pedal.sh` | Find your pedal's USB Vendor/Product IDs |
| `scripts/configure-pedal.sh` | Save your pedal's IDs to config |
| `scripts/build.sh` | Build the app bundle |
| `scripts/install.sh` | Install app and LaunchAgent |
| `scripts/start.sh` | Start the background service |
| `scripts/stop.sh` | Stop the background service |
| `scripts/status.sh` | Check service status and view logs |
| `scripts/uninstall.sh` | Remove everything |

## Logs

- Standard output: `/tmp/footpedal.log`
- Errors: `/tmp/footpedal.error.log`

View live logs:
```bash
tail -f /tmp/footpedal.log
```

## Configuration

Configuration is stored in `~/.config/footpedal/config.json`:

```json
{
    "vendorID": 13651,
    "productID": 45057
}
```

## Troubleshooting

### "Could not open HID Manager"

The app needs Accessibility permission. Go to System Settings → Privacy & Security → Accessibility and add `/Applications/FootPedalOptionKey.app`.

### "Waiting for foot pedal..." but nothing happens

1. Verify your pedal is connected: `system_profiler SPUSBDataType`
2. Check you have the correct Vendor ID and Product ID
3. Run `./scripts/discover-pedal.sh` to find the correct IDs

### Pedal detected but Option key not working

Ensure the app is added to **Accessibility** permissions and toggled ON.

### Service not starting

Check the error log:
```bash
cat /tmp/footpedal.error.log
```

## How It Works

1. The app uses IOKit's HID Manager to monitor the USB foot pedal by its Vendor ID and Product ID
2. When the pedal is pressed, it posts a `flagsChanged` event with the Option modifier
3. An event tap intercepts all keyboard/mouse events and adds the Option modifier flag while the pedal is held
4. The pedal's native "b" keystroke is blocked by the event tap
5. Your regular keyboard is completely unaffected

## Uninstall

```bash
./scripts/uninstall.sh
```

Then remove the app from Accessibility in System Settings.

## License

MIT
