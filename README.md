# TempBar

A small native macOS menu bar app that shows CPU and GPU die temperatures.

```
CPU 41°  GPU 35°
```

TempBar reads the temperature sensors directly through IOKit's HID event
system, so it needs **no sudo, kernel extension, or privacy permission**. Every
reading stays on the Mac.

## Requirements

- Apple Silicon Mac (the sensor names below are Apple Silicon specific)
- macOS 13 or later
- Swift 5.9 or later (Command Line Tools are enough; Xcode is not required)

## Install with Homebrew

```sh
brew tap inartaly/tap
brew trust inartaly/tap
brew install --cask tempbar
```

Homebrew 7 requires third-party taps to be trusted before it will load their
casks. Homebrew installs to `/Applications`; if you already installed TempBar
manually in `~/Applications`, remove that copy first to avoid two menu bar items.

Homebrew marks downloaded apps as quarantined. Because TempBar is ad-hoc signed
but not notarized, macOS may block the first launch. Allow it under
**System Settings → Privacy & Security**, or run:

```sh
xattr -dr com.apple.quarantine /Applications/TempBar.app
```

To remove preferences and the optional Start at Login agent when uninstalling:

```sh
brew uninstall --cask --zap tempbar
```

## Install a release

Download the latest `TempBar-*.zip` from the
[releases page](https://github.com/inartaly/TempBar/releases), unzip it, and move
`TempBar.app` to `~/Applications` or `/Applications`.

The release build is ad-hoc signed but not notarized, so macOS may block the
first launch. If that happens, allow TempBar under **System Settings → Privacy &
Security**, or remove the quarantine flag:

```sh
xattr -dr com.apple.quarantine ~/Applications/TempBar.app
```

## Build and install

```sh
cd ~/Projects/TempBar
./scripts/install.sh
```

The script builds a release binary, assembles `build/TempBar.app`, ad-hoc signs
it, copies it to `~/Applications/TempBar.app`, and launches it. Look for the
temperature readout in the menu bar.

To build without installing:

```sh
./scripts/build-app.sh release
open build/TempBar.app
```

## Menu

Clicking the menu bar item opens:

- **CPU / GPU summary** — hottest sensor, average of that group's sensors, and
  the number of sensors found.
- **Peak since launch** — highest CPU and GPU readings seen this session.
  `Display → Reset Session Peak` clears it.
- **Sensors** — every detected sensor with its current temperature.
- **Display**
  - Show CPU temperature
  - Show GPU temperature
  - Show CPU/GPU labels
  - Color values by temperature (green < 60 °C, orange 60–80 °C, red > 80 °C)
  - Use Fahrenheit
  - Menu Bar Value: hottest sensor, average of sensors, or hottest + average
  - Reset Session Peak
- **Refresh Rate** — 1, 2, 5, or 10 seconds.
- **Start at Login**
- **About TempBar**
- **Quit TempBar**

The menu bar value can therefore show either the hottest sensor or the average:

```
CPU 41°  GPU 35°            hottest
CPU 41°  GPU 35°            average
CPU 46° (41°)  GPU 38° (35°)  hottest + average
```

## Sensors

| Sensor name pattern | Group |
| --- | --- |
| `PMU tdie*` | CPU |
| `PMU tdev*`, `PMU2 tdev*` | GPU |

On the development machine TempBar finds 7 CPU sensors (`PMU tdie1`–`tdie7`)
and 9 GPU sensors (`PMU tdev1`–`tdev5`, `PMU2 tdev1`–`tdev4`). Values outside
0–130 °C are ignored as invalid calibration or placeholder readings.

Temperature sensor names are not a public API and vary between chips. If a Mac
exposes different sensor names, TempBar may show fewer sensors or no GPU
reading. Use the CLI dumps below to inspect what is available.

### Command line

```sh
~/Applications/TempBar.app/Contents/MacOS/TempBar --dump
~/Applications/TempBar.app/Contents/MacOS/TempBar --dump --json
```

`--dump` prints every sensor plus each group's hottest and average value;
`--json` emits the same data as JSON. Both exit after printing, so they can be
used in scripts.

## Start at Login

Enabling **Start at Login** writes a per-user LaunchAgent:

```
~/Library/LaunchAgents/com.inar.tempbar.plist
```

It is loaded by `launchd` at the next login. TempBar deliberately does not load
it immediately, which would start a second copy alongside the one you are
using. Disabling removes the plist and leaves the current copy running; it
simply will not come back at the next login.

If you move the app after enabling the login item, the menu item will show as
off the next time you launch TempBar from the new location. Turn it on again to
rewrite the path.

## Preferences

Settings live in the `com.inar.tempbar` user defaults domain:

```sh
defaults read com.inar.tempbar
defaults delete com.inar.tempbar   # reset to defaults; quit TempBar first
```

## Uninstall

```sh
# Quit TempBar from its menu, then:
rm -rf ~/Applications/TempBar.app
rm -f ~/Library/LaunchAgents/com.inar.tempbar.plist
defaults delete com.inar.tempbar
```

## How it works

- `Sources/CSensors` is a small C target. It creates an
  `IOHIDEventSystemClient` monitor, enumerates HID services, reads the
  `Product` name, and requests the temperature event. The private IOKit symbols
  are resolved with `dlsym`, so no private headers or SDK extras are needed.
- `Sources/TempBar` is a Swift/AppKit `NSStatusItem` app with no Dock icon
  (`LSUIElement`), built with SwiftPM. Sampling runs on a background queue, and
  the status item is updated on the main queue.
- The bundle is ad-hoc signed (`codesign --sign -`), which is sufficient for a
  locally built app.

## Notes

- The app relies on private, long-standing IOKit entry points rather than public
  APIs. A future macOS release could change or remove them.
- No network access, analytics, or telemetry.
- If the menu bar shows `--°`, run the `--dump` command above to check whether
  the sensors are exposed on your Mac.
