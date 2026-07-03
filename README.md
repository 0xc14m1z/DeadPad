# DeadPad

DeadPad is a small personal macOS utility written in Swift. It reads raw
trackpad touch coordinates through Apple's private
`MultitouchSupport.framework`, then uses a CoreGraphics HID event tap to
suppress mouse, drag, click, and scroll events when touches start inside
configured dead zones.

`src/DeadPadCoreTypes.h` only declares the private multitouch C structs so
Swift can read the raw callback memory with the correct ABI layout.

This is intentionally not App Store software. It uses private macOS APIs and is
meant for personal use.

## Build

```sh
make
```

This builds `DeadPad.app` and places the internal `deadpad` helper inside the
app bundle.

## Xcode

Open the project:

```sh
open DeadPad.xcodeproj
```

Select the `DeadPad` scheme and press Run. The app target builds the Swift
`deadpad` helper in a build phase, then places it in
`DeadPad.app/Contents/Resources`.

## Menu bar app

Run:

```sh
open DeadPad.app
```

The app appears as `DP` in the macOS menu bar. Click `DP` to open the DeadPad
window. The window shows proportional rectangles for detected devices using
their physical surface sizes. Device 0 is rounded, and the other devices appear
below it in different colors.

The `Match active area` checkbox uses the built-in trackpad as the reference
surface when enabled. Extra trackpads show red diagonal hatching over the
disabled area, and the helper is restarted with matching centimeter dead zones
when the filter is already running. Turning it off hides the overlay and returns
the helper to the default dead-zone settings.

While the window is open, active touches are shown as small moving dots on the
corresponding trackpad preview. The dots turn green only while the trackpad is
pressed/clicked, and turn yellow when `Match active area` is enabled and the
touch is inside a disabled area.

The window contains:

- `Start`
- `Stop`
- `Restart`
- `Start at login`
- `Match active area`
- `Accessibility`
- `Log`
- `Quit`

Logs are written to:

```text
~/Library/Logs/DeadPad/deadpad.log
```

The `Start at login` checkbox creates or removes this user LaunchAgent:

```text
~/Library/LaunchAgents/com.local.deadpad.app.plist
```

## First run

Open `DeadPad.app`, click the `DP` menu bar item, and press `Start`.

On first launch, macOS may ask for Accessibility permission. The filter starts
only after the permission is granted and `Start` is pressed again.

## Permissions

The first filtering run requires Accessibility permission. macOS may show a
prompt. If the event tap cannot be created, enable `DeadPad` or its bundled
`deadpad` helper in:

System Settings > Privacy & Security > Accessibility

Depending on your macOS privacy settings, you may also need Input Monitoring.

If pressing `Start` opens System Settings and the status changes to
`Needs Accessibility`, enable `DeadPad` or the bundled `deadpad` helper in that
Accessibility list, then press `Start` again. If the entry was already enabled,
toggle it off and on once to refresh macOS's permission.

## Important limitation

macOS does not expose a public API to remove only one finger from the system
trackpad recognizer. This tool blocks the resulting pointer/scroll/click events
when the raw touch frame says they likely came from a dead-zone contact.

DeadPad currently uses a conservative policy: it blocks generated events only
when all active touches started in dead zones. This is usually better if you
rest a palm on the side and use a finger in the center.

For a fully per-finger filter, the next step would be a lower-level HID/DriverKit
filter, which is much heavier.
