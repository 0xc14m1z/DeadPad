# DeadPad Plan

## Problem

The user is using an external Apple-style trackpad that is physically larger
than the built-in MacBook trackpad. While typing, the user's palms naturally rest
on areas that would normally be outside the built-in trackpad surface, but on
the larger external trackpad those same resting positions generate accidental
touches, pointer movement, clicks, drags, or scroll gestures.

The goal is to create a small personal macOS utility that can precisely define
"dead zones" on the physical trackpad surface, especially vertical bands on the
left and right sides of the device. Touches that start inside those areas should
not produce useful input.

This project is not intended for App Store distribution. Private APIs and local
macOS permissions are acceptable if they make the tool practical for personal
use.

## Constraints

macOS does not provide a public, global API for filtering individual raw
trackpad fingers before the system gesture recognizer processes them.

Public APIs such as AppKit touch events are only available inside the current
application's own views. They are not suitable for globally reading physical
trackpad coordinates while the user types in other applications.

Global event APIs such as CoreGraphics event taps can suppress resulting pointer,
click, drag, and scroll events, but they do not directly expose per-finger
physical touch coordinates.

Therefore the current approach combines two layers:

- Read raw touch coordinates through the private
  `MultitouchSupport.framework`.
- Suppress generated mouse, drag, click, and scroll events through a
  CoreGraphics HID event tap when the active touch frame indicates that the
  touch began inside a configured dead zone.

This is lighter than writing a DriverKit/HID driver and is suitable for a local
personal utility, but it is not a perfect per-finger kernel-level filter.

## Current Implementation

The current prototype lives in:

```text
/Users/morgandam/Documents/repos/DeadPad
```

It provides a small command-line utility named `deadpad`.

It now also builds a lightweight macOS menu bar app named `DeadPad.app`. The app
packages `deadpad` as an internal helper. Clicking the `DP` menu bar item opens
a small control window with start, stop, restart, Start at login, Accessibility
settings, log-opening, and quit actions.

Implemented features:

- Loads `/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport`
  dynamically with `dlopen`.
- Lists detected multitouch devices.
- Reads the physical sensor dimensions of each device.
- Automatically prefers the external, non-built-in trackpad when available.
- Supports dead zones in normalized units or centimeters.
- Supports left, right, top, and bottom dead zones.
- Converts centimeter-based zones into normalized coordinates using the detected
  trackpad size.
- Provides a monitor mode that prints raw touch coordinates without blocking
  input.
- Provides a filtering mode that suppresses mouse movement, clicks, drags, and
  scroll events while a dead-zone touch is active.
- Supports `--policy all` and `--policy any`.
- Supports `--invert-x` and `--invert-y` for coordinate calibration.
- Includes convenience scripts:
  - `monitor.command`
  - `run.command`
- Builds a menu bar app:
  - `DeadPad.app`
- Includes an example LaunchAgent plist:
  - `com.local.deadpad.plist.example`

On the tested machine, the devices were detected as:

```text
[0] builtIn=yes surface=12.48cm x 7.68cm
[1] builtIn=no  surface=15.60cm x 11.04cm
```

For the external trackpad, a `2cm` dead zone on each side maps to approximately
`12.8%` of the trackpad width.

## Current Test Flow

Build the project:

```sh
cd /Users/morgandam/Documents/repos/DeadPad
make
```

Run the menu bar app:

```sh
open DeadPad.app
```

List devices:

```sh
./deadpad --list-devices
```

Monitor touches without blocking:

```sh
./deadpad --monitor --device 1 --left-cm 2 --right-cm 2
```

Expected behavior:

- Touching the left edge should show `x` close to `0.000` and `dead=yes`.
- Touching the center should show `dead=no`.
- Touching the right edge should show `x` close to `1.000` and `dead=yes`.

If left and right are reversed, rerun with:

```sh
./deadpad --monitor --device 1 --left-cm 2 --right-cm 2 --invert-x
```

Run the filter:

```sh
./deadpad --device 1 --left-cm 2 --right-cm 2 --policy all
```

The first filtering run may require enabling Accessibility permission for either
the `deadpad` binary or the Terminal application that launched it:

```text
System Settings > Privacy & Security > Accessibility
```

Depending on the macOS configuration, Input Monitoring permission may also be
needed.

## Policy Behavior

`--policy all` is the default and more conservative mode.

It blocks generated events only when all currently active touches started inside
a dead zone. This is intended to allow the user to rest a palm on a side area
while still using a finger in the center of the trackpad.

`--policy any` is stricter.

It blocks generated events whenever any active touch started inside a dead zone.
This can be useful if accidental input still leaks through, but it may also block
intentional center gestures while a palm is touching a side zone.

## Known Limitations

The utility cannot remove a single dead-zone finger from the system trackpad
gesture recognizer. It can only decide whether to suppress the resulting global
mouse, drag, click, and scroll events.

Because the raw touch API is private, macOS updates could change behavior or
break compatibility.

The current version is a command-line tool rather than a menu bar app. It has no
visual editor for drawing dead zones yet.

The current LaunchAgent file is only an example. It should be used after manual
testing confirms that the filter behaves correctly and permissions are granted.

## Next Steps

Recommended next improvements:

- Add a small menu bar app wrapper for starting, stopping, and showing current
  status.
- Add a calibration UI that lets the user drag dead-zone boundaries visually.
- Store configuration in a user config file instead of requiring command-line
  arguments.
- Add a launch-at-login installer/uninstaller command.
- Improve event-source discrimination if possible, so external trackpad events
  can be separated more reliably from mouse or built-in trackpad events.
- Add structured logging for suppressed event counts and active dead-zone
  contacts.
- Experiment with lower-level HID filtering only if the event-tap approach is
  not precise enough in daily use.
