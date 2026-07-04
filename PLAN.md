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

It builds a lightweight Swift macOS menu bar app named `DeadPad.app`.
`src/DeadPadCoreTypes.h` remains as an ABI bridge for private multitouch struct
layout; the runtime logic itself is Swift. The app packages `deadpad` as an
internal helper rather than exposing CLI launch scripts. Clicking the `DP` menu
bar item opens a Trackpad Matcher-style window with a native macOS title bar, a
centered Magic Trackpad stage, and two animated switch rows. The window can
match the Magic Trackpad active area to the built-in trackpad by animating the
blue active area, fading in disabled-area hatching, and passing the corresponding
centimeter dead zones to the helper. When the window is open, live touches are
rendered as moving dots on the stage.

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
- Provides a stream mode for the app preview that reports live touch positions
  without suppressing input.
- Provides a filtering mode that suppresses mouse movement, clicks, drags, and
  scroll events while a dead-zone touch is active.
- Uses a conservative all-active-touches filtering policy.
- Builds a menu bar app:
  - `DeadPad.app`
- Includes an Xcode project:
  - `DeadPad.xcodeproj`

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

Open the `DP` menu bar item, verify that detected trackpads render in the
window, and enable `Riduci area attiva` to verify the active-area animation.

The first filtering run may require enabling Accessibility permission for
`DeadPad` or its bundled `deadpad` helper:

```text
System Settings > Privacy & Security > Accessibility
```

Depending on the macOS configuration, Input Monitoring permission may also be
needed.

## Policy Behavior

DeadPad uses a conservative mode: it blocks generated events only when all
currently active touches started inside a dead zone. This is intended to allow
the user to rest a palm on a side area while still using a finger in the center
of the trackpad.

## Known Limitations

The utility cannot remove a single dead-zone finger from the system trackpad
gesture recognizer. It can only decide whether to suppress the resulting global
mouse, drag, click, and scroll events.

Because the raw touch API is private, macOS updates could change behavior or
break compatibility.

The current menu bar app has a fixed active-area matching control. It does not
yet have a freeform visual editor for drawing arbitrary dead zones.

## Next Steps

Recommended next improvements:

- Add a calibration UI that lets the user drag dead-zone boundaries visually.
- Store configuration in a user config file.
- Improve event-source discrimination if possible, so external trackpad events
  can be separated more reliably from mouse or built-in trackpad events.
- Add structured logging for suppressed event counts and active dead-zone
  contacts.
- Experiment with lower-level HID filtering only if the event-tap approach is
  not precise enough in daily use.
