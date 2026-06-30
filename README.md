# DeadPad

`deadpad` is a small personal macOS utility that reads raw trackpad touch
coordinates through Apple's private `MultitouchSupport.framework`, then uses a
CoreGraphics HID event tap to suppress mouse, drag, click, and scroll events
when touches start inside configured dead zones.

This is intentionally not App Store software. It uses private macOS APIs and is
meant for personal use.

## Build

```sh
make
```

This builds both:

- `deadpad`, the command-line helper.
- `DeadPad.app`, a small menu bar app that launches the helper in the
  background.

To build only one target:

```sh
make cli
make app
```

## Menu bar app

Run:

```sh
open DeadPad.app
```

The app appears as `DP` in the macOS menu bar. It starts the filter
automatically with:

```text
--left-cm 2 --right-cm 2 --policy all --verbose
```

The menu contains:

- `Start Filter`
- `Stop Filter`
- `Restart Filter`
- `Open Accessibility Settings`
- `Open Log`
- `Quit DeadPad`

Logs are written to:

```text
~/Library/Logs/DeadPad/deadpad.log
```

## First run

List detected multitouch devices:

```sh
./deadpad --list-devices
```

On the machine used for this build, the external trackpad was detected as:

```text
[1] builtIn=no surface=15.60cm x 11.04cm
```

So a `2cm` dead zone on each side is about `12.8%` of the width.

Monitor coordinates without blocking anything:

```sh
./deadpad --monitor --left-cm 2 --right-cm 2
```

Touch the left and right edges of the trackpad. The log should show `x` near
`0.000` on the left and near `1.000` on the right. If it is reversed, add
`--invert-x`.

Run the filter:

```sh
./deadpad --left-cm 2 --right-cm 2 --policy all
```

Or double-click/run:

```sh
./monitor.command
./run.command
```

If the side palms still trigger movement/clicks while you type, try the stricter
policy:

```sh
./deadpad --left-cm 2 --right-cm 2 --policy any
```

Stop with `Ctrl-C`.

## Permissions

The first filtering run requires Accessibility permission. macOS may show a
prompt. If the event tap cannot be created, enable either `deadpad` or the
Terminal app used to launch it in:

System Settings > Privacy & Security > Accessibility

Depending on your macOS privacy settings, you may also need Input Monitoring.

When using `DeadPad.app`, macOS may show the app or its bundled `deadpad` helper
in the Accessibility list. Enable whichever entry macOS adds.

## Optional login launch

After testing the command manually, you can adapt
`com.local.deadpad.plist.example` as a LaunchAgent. The included example already
points at this folder and uses `--left-cm 2 --right-cm 2 --policy all`.

Manual permission testing first is strongly recommended, because background
launches cannot guide you through macOS privacy prompts as clearly as Terminal
can.

## Options

```text
--list-devices              Print multitouch devices and exit.
--monitor                   Print touches and decisions; do not suppress events.
--device INDEX              Use a specific device from --list-devices.
--left N                    Left dead zone as normalized width.
--right N                   Right dead zone as normalized width.
--top N                     Top dead zone as normalized height.
--bottom N                  Bottom dead zone as normalized height.
--left-cm CM                Left dead zone in centimeters.
--right-cm CM               Right dead zone in centimeters.
--top-cm CM                 Top dead zone in centimeters.
--bottom-cm CM              Bottom dead zone in centimeters.
--policy all|any            all allows a center touch to keep working; any is stricter.
--grace-ms MS               Keep blocking briefly after a dead-zone frame.
--invert-x                  Flip left/right calibration.
--invert-y                  Flip top/bottom calibration.
--verbose                   Print block stats once per second.
```

## Important limitation

macOS does not expose a public API to remove only one finger from the system
trackpad recognizer. This tool blocks the resulting pointer/scroll/click events
when the raw touch frame says they likely came from a dead-zone contact.

That means:

- `--policy all` blocks only when all active touches started in dead zones. This
  is usually better if you rest a palm on the side and use a finger in the
  center.
- `--policy any` blocks when any active touch started in a dead zone. This is
  more aggressive and can block intentional center use while a palm is touching
  a side zone.

For a fully per-finger filter, the next step would be a lower-level HID/DriverKit
filter, which is much heavier.
