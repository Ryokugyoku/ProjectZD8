# RevTorque Insight

RevTorque Insight is a SwiftUI automotive insight application for iOS and macOS.
It turns vehicle connection, live telemetry, maintenance, history, and analysis
workflows into a calm, precise cockpit without presenting unverified vehicle state
as fact.

The customer-facing product name is **RevTorque Insight**. The Xcode project,
targets, bundle identifiers, persistence paths, and other compatibility-sensitive
technical identifiers continue to use `ProjectZD8` until they are migrated in a
separately reviewed change.

## Product concept

- Content and measured vehicle evidence take priority over decoration.
- Luminous cyan, inherited from the app icon's tachometer and signal trace,
  identifies primary actions, focus, selection, and analytical depth.
- Orange is reserved for a signal peak, caution, or another small high-energy
  emphasis; it never substitutes for real connection or health state.
- Login and navigation establish one consistent RevTorque Insight identity across
  iOS and macOS while preserving each platform's own layout conventions.

## Requirements

- Xcode 26.4 or later
- iOS 26.4 or later, or macOS 26.4 or later

Open `ProjectZD8.xcodeproj` in Xcode to build and run the app.

## Development rules

Start with the [documentation index](Documentation/INDEX.md), which routes each
task to the smallest relevant section. Codex and human contributors must follow
[AGENTS.md](AGENTS.md), [the coding standards](Documentation/CODING_STANDARDS.md),
and [the folder placement rules](Documentation/PLACEMENT_RULES.md) when applicable.

## License

Copyright 2026 Ryokugyoku.

This project is source-available under the [PolyForm Noncommercial License 1.0.0](LICENSE).
Third parties may use, modify, and redistribute it only for noncommercial purposes. Commercial use by anyone other than the copyright holder is not permitted.

本プロジェクトは、[PolyForm Noncommercial License 1.0.0](LICENSE) に基づきソースを公開しています。著作権者本人を除き、商用目的での利用・改変・再配布は許可されません。
