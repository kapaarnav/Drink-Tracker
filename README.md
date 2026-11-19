# Drink Tracker

A native iOS 26+ app with three local counters, a Lock Screen Live Activity, and read-only daily history. Product decisions and edge cases are specified in [DESIGN.md](DESIGN.md).

## Open and run

1. Open `DrinkTracker.xcodeproj` in Xcode 27.2 or a compatible newer release.
2. Select the **DrinkTracker** scheme.
3. For a simulator, choose an available iPhone simulator and Run.
4. For your iPhone, select your **Personal Team** under **Signing & Capabilities** for both **DrinkTracker** and **DrinkTrackerWidget**. Leave automatic signing enabled. The initial identifiers are `com.aarnavkapoor.DrinkTracker` and `.Widget`; change both together if your team requires different identifiers.
5. Choose the paired iPhone, enable Developer Mode if requested, and Run.

No package installation or backend configuration is needed. `DrinkTrackerCore` is a local Swift package. The app initializes the same coordinator for UI actions and LiveActivityIntent execution; the widget never opens a separate database.

## Behavior

Start Tracking explicitly creates a zero-count day. Pause immediately saves a timestamp and removes the card. Resume retains that day's identity, counts, and cutoff. At 4 a.m. in the assigned time zone, the day becomes permanently read-only. Travel windows and unknown-zone fallback follow the design document.

A dismissed, expired, disabled, or failed card never stops in-app tracking. Use **Show on Lock Screen** to restore the card without creating a new event. iOS controls authentication and the card's active lifetime; physical-device checks remain necessary.

History is on a separate top tab. The current entry has an Active/Paused label; tapping any entry opens totals, its tracking window, and Start/Pause/Resume timestamps. There are no edit/delete controls or per-drink event logs.

The SwiftData store is under the app container's Application Support/DrinkTrackerStore directory, with managed CloudKit sync disabled and the folder marked excluded from backup. Never reset a failed store to recover from an error. Updates should preserve its schema and data.

## Validate

Core domain/persistence tests (macOS 26+):

```sh
swift test
```

Build without device signing:

```sh
xcodebuild -project DrinkTracker.xcodeproj -scheme DrinkTracker \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

Run `DrinkTrackerUITests` from Xcode's Test action or use an available simulator identifier with `xcodebuild test`. UI tests launch with `--ui-testing`, selecting an isolated in-memory store; they do not clear or modify normal on-device history.

`Scripts/generate_project.py` regenerates target membership and the shared scheme without third-party tools. Prefer editing target membership in the script; regeneration resets manual project settings such as a selected development team, so preserve signing changes before regenerating.

See [VALIDATION.md](VALIDATION.md) for observed results and remaining device checks. A passing simulator build is not evidence that an unauthenticated locked-device action works.
