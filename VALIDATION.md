# Validation status

Implementation started November 18, 2026. This file distinguishes verified behavior from checks that still require a working simulator session or the physical iPhone.

## Verified

- The app and Live Activity widget compile for the iOS Simulator with signing disabled.
- The current app and widget compile for a physical iPhone destination, both unsigned and signed with the selected Personal Team. The signed app passed bundle validation and installed successfully on the paired iPhone 16. Signature verification outside the sandbox reports valid on disk and satisfies its designated requirement.
- Nine Swift Testing tests pass on macOS using real SwiftData containers, including:
  - 4 a.m. boundaries, after-midnight labeling, and 23/25-hour daylight-saving days.
  - Independent categories, the zero floor, and immutable cutoff behavior.
  - Repeated Pause/Resume entries and rejection of an old active-period control.
  - Known 27/38/48-hour travel transitions and the reverse date-line guard.
  - Unknown-zone fallback and gaps without placeholder days.
  - Thirty concurrent adjustments with no lost counts or per-counter event log.
  - Disk reopening with saved values/identity intact and backup-exclusion metadata verified.
  - A deliberately read-only store: failed Pause saves roll back state and event together.
  - No record created by history reads, and idempotent lifecycle retries even after a later state transition.

- After the developer profile was trusted, CoreDevice successfully launched the app on the physical iPhone.
- The user confirmed that tapping water + on the Lock Screen increases the card count while staying on the Lock Screen. This establishes the primary real-device interaction, not every authentication scenario.
- The user also confirmed that Pause/Resume preserve the water count, remove/restore the card, and show the action timestamps in History.

The read-only test intentionally produces a SwiftData permission error in the test log. That is an injected failure case, not a failure to save the normal store.

## Not yet passed

- **Simulator UI execution:** the UI test target compiles. Two native-arm64 attempts were blocked by simulator first-boot/service failures before test actions completed; the retry exited without a UI test pass. No UI pass is claimed. `DrinkTrackerUITests.testTrackingHistoryAndResume` exercises Start, independent water adjustments, Pause, History/details, and Resume using an isolated in-memory store once the simulator is working.
- **Additional Lock Screen cases:** all six buttons, cold intent execution, first-unlock/storage behavior, stale/expired state, dismissal/restoration, and full app/card consistency remain to be exercised. Staying on the Lock Screen does not establish whether Face ID silently authenticated during the interaction.
- **Release checks:** no TestFlight upload, real eight-hour expiry run, overnight cutoff device run, accessibility device review, or migration to a future schema version has been completed.

## Phone check after installation

1. Open Tracking and tap Start Tracking. Confirm zero totals and the Lock Screen card.
2. Add a water glass on the Lock Screen, then reopen the app: only water should increase.
3. Test all three categories and minus at zero, noting whether Face ID/device authentication is requested and whether the visible app opens.
4. Pause in the app: retain totals and remove the card. Resume: retain totals and restore the card. History should retain Started/Paused/Resumed timestamps on one day.
5. Dismiss the card yourself: in-app counting continues. Show on Lock Screen restores it without another Started/Resumed event.
6. Reopen the app after the cutoff: totals are final, the effective end time is the stored cutoff, and no new day starts automatically.

A development test creates a real day in the normal app. The product intentionally has no deletion command. Simulator UI tests use a separate in-memory store instead.
