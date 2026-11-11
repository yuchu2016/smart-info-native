# SMART Info Native

[简体中文](README.md) | **English**

A native macOS (SwiftUI) viewer for disk S.M.A.R.T. data. It enumerates physical disks with `diskutil` and calls `smartctl -x --json=ov` from [smartmontools](https://www.smartmontools.org/) 7.5, then renders the complete NVMe / ATA SMART output as readable tables with Chinese annotations.

**Read-only by design**: no self-tests, no writes to disks, no kernel extensions. Missing values are shown as *unavailable* — never guessed or replaced with zero.

Current release: **1.1.3 (build 5)** · macOS 13+ · Apple Silicon (arm64) · GPL v2

> The in-app field descriptions are in Chinese. The documentation in this file is in English.

---

## Features

- Sidebar lists every physical disk with capacity, interface, internal/external location and health status; the entire row is clickable
- Fully expanded NVMe health information log and ATA attribute table, with Chinese descriptions, units, thresholds, per-bit critical warnings and all eight optional temperature sensors
- Preserves `smartctl`'s exact numeric strings and full text output; thermal management counters missing from the upstream 7.5 JSON are recovered from the original text
- Every group is expanded by default; table content can be copied in full, with horizontal scrolling for long fields
- Identifiers such as serial numbers are masked in the UI by default and only appear in exported JSON
- Per-disk presentations and row heights are prepared on a background worker and rendered with reusable native table rows, so switching between disks with hundreds of fields stays responsive
- Parser unit tests (`Tests/SMARTTests.swift`) run automatically as part of the build

## Download & install

Download `SMART-Info-Native-1.1.3-Mac.zip` from [Releases](https://github.com/yuchu2016/smart-info-native/releases), unzip it and drag `SMART Info Native.app` into Applications.

> **First launch**: this build is ad-hoc signed and **has not been signed with an Apple Developer ID or notarized**. macOS may say the developer cannot be verified. Right-click the app → **Open** → confirm, or allow it in *System Settings → Privacy & Security*. Alternatively:
>
> ```sh
> xattr -d com.apple.quarantine "/Applications/SMART Info Native.app"
> ```

Reading SMART data from some disks may require administrator privileges. If a disk reports "no SMART data obtained", try launching with `sudo`, or check whether the device / USB bridge is supported by smartmontools.

## Requirements

| Item | Requirement |
|---|---|
| OS | macOS 13.0 (Ventura) or later |
| Architecture | Apple Silicon / arm64 (no x86_64 slice in this build) |
| Build tools | Xcode or Command Line Tools (`xcrun swiftc`, `iconutil`, `codesign`) |
| Engine | Bundled `smartctl`, or smartmontools installed system-wide (`brew install smartmontools`) |

## Build from source

```sh
git clone https://github.com/yuchu2016/smart-info-native.git
cd smart-info-native

./build-engine.sh   # optional: download and build smartmontools 7.5 smartctl into Engine/
./build.sh          # compile the app, generate the icon and run unit tests

open "Build/SMART Info Native.app"
```

Notes:

- `build-engine.sh` downloads the official `smartmontools-7.5.tar.gz` (GPL v2) from SourceForge, builds an arm64 `smartctl` in `EngineWork/`, and ad-hoc signs it. The resulting `Engine/smartctl` and `Engine/COPYING` are not tracked in git.
- Building the engine is optional. The app looks for `Contents/Resources/smartctl`, then the `SMARTINFO_ENGINE` environment variable, then Homebrew paths such as `/opt/homebrew/sbin/smartctl`.
- `build.sh` compiles the three Swift files in `Sources/` with `xcrun swiftc -O`, generates `AppIcon.icns`, copies `Info.plist`, runs `codesign --verify --deep --strict`, then compiles and runs `Tests/SMARTTests.swift`.
- Override the output directory with `SMARTINFO_BUILD_DIR=/some/path ./build.sh`; the default is `Build/`.

## How it works

```
diskutil list -plist physical        ->  physical disk identifiers
diskutil info  -plist /dev/diskN     ->  capacity, interface, location, device node
smartctl -x --json=ov <node>         ->  raw NVMe / ATA SMART JSON + text output
SMARTParser / SMARTPresentation      ->  annotated tables, units, thresholds, health, masked identifiers
```

Field definitions follow smartmontools 7.5 (`nvmeprint.cpp`, `smartctl.8.in`) and the NVMe specification. ATA descriptions match attribute names rather than numeric IDs alone; unknown vendor-specific fields are preserved verbatim and labelled as vendor-specific, without invented interpretations. Health status is a threshold-based heuristic — **not a guarantee against drive failure. Keep independent backups.**

## License & credits

- The SwiftUI application UI and SMART data normalization code were implemented independently for this project and are released under **GNU GPL v2** — see [LICENSE](LICENSE) / [COPYING](COPYING). Version history and compliance notes are in [NOTICE.txt](NOTICE.txt).
- The bundled `smartctl` comes from the official **smartmontools 7.5** release (2025-04-30, r5714), © 2002–2025 Bruce Allen, Christian Franke and smartmontools contributors, also GPL v2. Upstream source: <https://downloads.sourceforge.net/project/smartmontools/smartmontools/7.5/smartmontools-7.5.tar.gz>. The `*-Source.zip` asset in Releases includes the unmodified upstream archive to satisfy the corresponding-source requirement.
- This project does **not** use any code or binary assets from the original Flutter-based SMART Info app.

## Known limitations

- arm64 only. Intel Macs need to adjust `-target` in `build.sh` and the architecture flags in `build-engine.sh`.
- Ad-hoc signed and not notarized; distribution is limited to local builds and this repository's Releases.
- USB/SATA bridge compatibility depends on macOS, firmware, drivers and the smartmontools backend. The parser has test coverage, but this build was not validated against live USB/SATA hardware.
- Health status is heuristic; missing data is always reported as unavailable.
