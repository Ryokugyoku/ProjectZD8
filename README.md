# RevTorque Insight

RevTorque Insight is a SwiftUI application for iOS and macOS that connects to an
OBD adapter, records vehicle telemetry, and helps you review and analyse it
without presenting unverified vehicle state as fact.

The customer-facing product name is **RevTorque Insight**. The Xcode project,
targets, bundle identifiers, persistence paths, and other technical identifiers
continue to use `ProjectZD8` until they are renamed in a separately agreed change.

## What it does

- **Connect and record**: discovers an OBD adapter, identifies (or registers) the
  vehicle, and records a session. Every PID request is stored as one row,
  including requests that received no answer, together with the PID definitions
  that were in force when the session was recorded.
- **Live telemetry**: shows the latest values and recent history of the session
  being recorded.
- **Garage and maintenance**: per-vehicle profile, photos, PID collection
  settings, and maintenance records.
- **Log history**: browse recorded sessions, delete them, or release the Raw data
  stored on the device.
- **Analysis**: a bundled HTML/JavaScript workbench shown in a web view. It uses
  no external libraries and no network; Swift supplies the decoded dataset and
  JavaScript does the interactive aggregation and visualisation.
- **Demo mode**: a simulated adapter that you must enable in Settings. Demo
  sessions are marked `isDemo` and are never synchronised.

There is no app-specific login. The data belongs to the iCloud account signed in
on the device. Vehicles, maintenance records, photos, and sessions are
synchronised through the CloudKit private database; each session's Raw data is
uploaded once, as a compressed archive, after the session ends. Without an iCloud
sign-in, every feature still works on the device and only synchronisation is
reported as unavailable.

Data lives in a single SQLite file, `Application Support/ProjectZD8/insight-v1.sqlite`.
The first public release has no backward compatibility with earlier builds: the
old `projectzd8.sqlite` and its CloudKit records are not read.

## Product concept

- Content and measured vehicle evidence take priority over decoration.
- Luminous cyan, inherited from the app icon's tachometer and signal trace,
  identifies primary actions, focus, selection, and analytical depth.
- Orange is reserved for a signal peak, caution, or another small high-energy
  emphasis; it never substitutes for real connection or health state.
- iOS and macOS share one identity while keeping each platform's own layout:
  macOS uses a sidebar with a settings scene and menu commands, iOS uses tabs.

## Requirements

- Xcode 26.4 or later
- iOS 26.4 or later, or macOS 26.4 or later
- GRDB.swift 7.x (Swift Package Manager dependency)

## Build and test

Open `ProjectZD8.xcodeproj` in Xcode (scheme `ProjectZD8`) to build and run the app.
From the command line:

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
# macOS build and a single unit-test class
xcodebuild -project ProjectZD8.xcodeproj -scheme ProjectZD8 -destination 'platform=macOS' \
  -derivedDataPath .build/dd CODE_SIGNING_ALLOWED=NO build
xcodebuild -project ProjectZD8.xcodeproj -scheme ProjectZD8 -destination 'platform=macOS' \
  -derivedDataPath .build/dd CODE_SIGNING_ALLOWED=NO test -only-testing:ProjectZD8Tests/<TestClass>
# iOS build
xcodebuild -project ProjectZD8.xcodeproj -scheme ProjectZD8 -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath .build/dd CODE_SIGNING_ALLOWED=NO build
# Offline data-quality tool (Python standard library only)
PYTHONPATH=Tools/VehicleChangeDataQuality python3 -m unittest discover -s Tools/VehicleChangeDataQuality/Tests -v
# CI helper script test
ruby .github/testflight_build_publisher_test.rb
```

Unsigned builds carry no CloudKit entitlement, so use a configuration that does
not touch CloudKit when running tests. Passing local builds and tests is not
evidence of appearance, real-device behaviour, a real adapter, production
CloudKit, or CI.

## Development rules

Architecture, conventions, and the documentation map are summarized in
[CLAUDE.md](CLAUDE.md). Documents about vehicle-specific change detection
(requirements, data inventory and audit, feature specification, and the
acquisition and collection plan) are in [Documentation](Documentation), and the
offline data-quality tool is in [Tools/VehicleChangeDataQuality](Tools/VehicleChangeDataQuality).

## License

Copyright 2026 Ryokugyoku.

This project is source-available under the [PolyForm Noncommercial License 1.0.0](LICENSE).
Third parties may use, modify, and redistribute it only for noncommercial purposes. Commercial use by anyone other than the copyright holder is not permitted.

本プロジェクトは、[PolyForm Noncommercial License 1.0.0](LICENSE) に基づきソースを公開しています。著作権者本人を除き、商用目的での利用・改変・再配布は許可されません。
