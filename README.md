# ItsMyBack

A native macOS menu-bar app that estimates changes in seated posture with Apple Vision. Camera frames are processed on your Mac and discarded. No accounts, recording, network access, or cloud services.

Requires macOS 14 or later. Build with Xcode 16 or later (verified with Xcode 26.2 / Swift 6.2.3). The app builds for Apple Silicon and Intel.

## Run

Open `PostureBuddy.xcodeproj`, select the **PostureBuddy** scheme, and run. For a local release build:

```sh
./scripts/build.sh
open build/Build/Products/Release/ItsMyBack.app
```

The local build is ad-hoc signed. For normal distribution, use a Developer ID identity and notarize it (see below). Keep the app in a stable location such as Applications when using launch at login. Ad-hoc identity changes during development can affect macOS permission persistence.

On first launch:

1. Read the privacy explanation and choose **Enable camera**. Camera access is requested only after this action. **Set up later** leaves monitoring off, including on subsequent launches.
2. Use the live camera preview to fit your head and both shoulders in view. The setup screen explains if your face or shoulders are hard to detect. Sit comfortably upright, click **Calibrate**, and stay steady until 20 usable readings are collected (roughly 10 seconds in good conditions).
3. Choose **Finish setup**, then use the menu-bar icon for status, pause/resume, recalibration, settings, and history.
4. Animated notch alerts are enabled by default and do not need macOS notification permission. Use **Preview notch alert** in the menu or Settings to test them. Turn on **Also send macOS notifications** and grant permission only if you also want system banners.

Monitoring resumes on later launches only if you previously enabled it. **Pause** releases the camera while keeping the session enabled; **Stop monitoring** also disables automatic session restoration. Idle pauses use the time since any keyboard or mouse input, with a grace period after app interaction. Setup and calibration are never paused for idleness. Choose **I’m back** to resume an idle pause. Idle, sleep, screen-lock, and camera-contention pauses are independent and cannot cancel a manual pause. Launch at login is opt-in.

## Features

- Native onboarding, menu-bar popover, and Settings window with keyboard and accessibility support.
- Explicit calibration with 20 usable head-position readings at 0.5-second intervals, median baseline, instability rejection, and a 45-second timeout. Failed or cancelled recalibration keeps the previous valid baseline.
- Configurable sensitivity, sample interval, consecutive-reading threshold, reminder cooldown (including 5, 10, and 30 seconds), and optional sound. Default detection uses two consecutive readings at 0.5-second intervals, typically confirming within about one second. Recovery requires two clearly upright readings to avoid flicker. Old default detection settings migrate to the faster defaults; custom tuning is preserved. Reminder cooldown is independent of initial detection. Preview cycles through warning, repeat reminder, lost tracking, calibration, ready, and recovery states.
- Small notch alerts with spring expansion, one glow sweep, four-second dismissal, and feedback for repeat reminders, confirmed recovery, lost tracking, calibration, readiness, calibration failure, and pausing. Non-notched displays use a top-center island. Alerts do not activate the app or take keyboard focus; Reduce Motion is respected.
- Serial camera capture/analysis and main-actor UI/state. Generation IDs reject results from stopped or superseded sessions.
- Camera permission recovery, missing-camera errors, interruption handling, disconnected-camera retry, and frame-delivery watchdog.
- Local daily upright/slouching time and reminder counts, a seven-day chart, and at most 90 daily records. Missing detections and calibration time are excluded.
- Atomic JSON persistence. Unreadable data is backed up before replacement; a failed backup disables saving to preserve the original.
- App Sandbox with camera entitlement and no network entitlement. Developer ID distribution enables hardened runtime.

## Detection limits

The detector tracks your head position relative to a baseline captured while you sit comfortably upright. It uses Apple's face detector and measures chin height normalized by face size. Lowering your head or leaning toward the camera reduces the score. Face rotation, an obscured face, very small faces, and multiple visible faces are excluded. This works with seated, upper-body camera framing; it does not require a full-body pose. Older body-pose calibrations are invalidated and must be repeated.

This is a camera-dependent head-position heuristic, not a medical assessment or a validated clinical measure. It cannot directly measure spine shape or distinguish every ordinary head movement from slouching. Camera placement, head rotation, lighting, and body proportions can affect it. Recalibrate when your camera or seating changes.

Camera frames still arrive continuously while monitoring; only selected frames run Vision. The camera indicator remains on until capture stops. Power consumption and false-positive rates require measurements on real hardware; no negligible-CPU claim is made.

History percentages describe tracked, usable samples, not your entire workday. Reminder counts represent requested reminders; macOS may suppress delivery through permission, Focus, or notification preferences. System banners honor macOS notification delivery behavior. Direct notch alerts are controlled by the app’s reminder preferences and can appear while Focus is on. The app does not read private Focus APIs.

## Development and tests

```sh
./scripts/test.sh
./scripts/build.sh
```

`Package.swift` builds the pure Swift detection and persistence layer for XCTest without requiring camera permission. Tests cover explicit/unstable/timed-out/cancelled calibration, invalid ratios, consecutive samples, loss of detection, reminder cooldowns, disabled reminders, settings bounds, history accounting/retention, atomic round trips, corrupt data, and safe migration of older data, the correct any-input event query, and idle-pause recovery, alert-channel routing, and preference migration.

Source layout:

- `PostureBuddyApp.swift`: app lifecycle, status item, popover, onboarding window.
- `PostureMonitor.swift`: camera worker, main-actor coordinator, permissions, pausing, notifications, login service.
- `Core/`: platform-independent detection and local persistence.
- `MenuBarView.swift`, `OnboardingView.swift`, `SettingsView.swift`: native interface.
- `NotchAlert.swift`: nonactivating island window, display placement, interruptible animation, and alert lifecycle.
- `Resources/`: camera usage description, sandbox entitlements, app icon.
- `scripts/`: local build, tests, vector icon generation, Developer ID notarization.

Data lives at `Application Support/PostureBuddy/data.json` inside the app’s sandbox container. It contains settings, baseline ratio, camera identifier, calibration date, and daily totals. Clearing history keeps preferences and calibration.

## Distribution

Create a Developer ID Application signing identity and an existing `notarytool` keychain profile. Then:

```sh
SIGNING_IDENTITY='Developer ID Application: Your Name (TEAMID)' \
NOTARY_PROFILE='your-notary-profile' ./scripts/notarize.sh
```

The script signs with hardened runtime, uploads an archive to Apple for notarization, staples and validates the ticket, checks Gatekeeper, and creates `build/distribution/ItsMyBack.zip`. This upload is performed only when you run the script. Signing credentials are not stored in the repo. Automatic updates are not integrated; distribute new notarized builds manually.

## Verification status

All 24 core tests and universal compilation are verified. Onboarding and Settings were inspected in a running app. Camera enable advances to live preview and calibration controls; successful calibration, saved baseline, completed onboarding, and local posture totals were verified with a person in frame. The following must still be checked with camera permission on real hardware before public release:

- Camera allow/deny/revoke and permission recovery.
- Calibration in varied lighting, camera heights, and seating positions; false-positive/negative rates.
- Sustained slouching, recovery, reminder cooldown, sound, notification denial, and Focus suppression.
- Manual pause combined with idle/sleep/lock; camera sharing with a call app; unplug/replug.
- History rollover, relaunch, launch-at-login registration, CPU/battery impact, and Intel runtime behavior.
- Developer ID signing, notarization, and installation on a clean Mac.

## Notch motion references

The alert is an independent implementation informed by the spring-opening motion in [boring.notch/drop.swift](https://github.com/TheBoredTeam/boring.notch/blob/main/boringNotch/animations/drop.swift) and the staged illuminated reveal in [HelloAnimation.swift](https://github.com/TheBoredTeam/boring.notch/blob/main/boringNotch/animations/HelloAnimation.swift). No boring.notch code, artwork, or path geometry is included.
