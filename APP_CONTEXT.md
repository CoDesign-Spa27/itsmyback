# ItsMyBack — Product Context for AI-Assisted Writing and Development

> This document is a handoff brief for other AIs. Use it as the source of truth for product understanding, scripts, landing pages, onboarding copy, feature explanations, support content, and UX writing.

## 1. Product identity

### Public product name

- **ItsMyBack**
- Current release label: **ItsMyBack 1.0**
- Platform: native macOS menu-bar app
- Minimum OS: macOS 14 or later
- Distribution target: Apple Silicon and Intel Macs

### Internal/project names

- Xcode project and scheme: `PostureBuddy`
- Swift package/library: `PostureBuddy` / `PostureCore`
- Main app type: `PostureBuddyApp`
- Data folder: `Application Support/PostureBuddy`
- Bundle display name and executable output: `ItsMyBack`

When writing user-facing content, always call the product **ItsMyBack**. Treat PostureBuddy as an implementation name only.

### One-sentence description

ItsMyBack is a private Mac menu-bar companion that watches for changes in seated head position, then gives gentle, timely reminders to reset or stretch.

### Short pitch

Sit comfortably. ItsMyBack quietly checks for changes in your seated posture using your Mac camera, processes everything on-device, and nudges you when it notices you have drifted from your calibrated upright position.

### Core promise

Help people notice posture drift during computer work without making them think about posture all day—and without sending camera footage anywhere.

### Product category

Privacy-first desktop wellness utility / posture awareness companion / passive ergonomic reminder.

It is not a medical device, clinical assessment, physical therapist, diagnostic tool, or guarantee of improved posture.

## 2. Problem and user context

### Problem

People who work at a Mac for long periods often gradually lower their head, lean toward the screen, or collapse into an uncomfortable position. The change is usually subtle and easy to miss. Generic timers are disconnected from what the person is actually doing; a camera-based tool can be more context-aware, but camera privacy is a major concern.

### Primary audience

- Desk workers and remote workers
- Developers, designers, writers, researchers, students, and other long-session computer users
- Mac users who want a low-friction posture cue rather than a rigid productivity system
- Privacy-conscious users who do not want video uploaded, recorded, or tied to an account

### Likely audience mindset

- “I start upright but slowly fold toward the screen.”
- “I need a cue at the moment I drift, not another timer.”
- “I want something quiet and respectful, not a nagging coach.”
- “I do not want a webcam recording me or sending images to a server.”

### Jobs to be done

1. Notice when seated posture has drifted from a comfortable baseline.
2. Receive a small reminder that does not interrupt typing or steal focus.
3. Take a quick reset, stretch, or change position.
4. See a simple local summary of upright versus slouching tracked time.
5. Keep control over sensitivity, reminder channels, pauses, and stored history.

## 3. How it works

1. The user explicitly enables camera access.
2. The app shows a live setup preview. The user positions their face and both shoulders in view.
3. The user sits comfortably upright and starts calibration.
4. The app collects 20 usable readings at roughly 0.5-second intervals, typically around 10 seconds.
5. It stores a median baseline for the user’s upright head position.
6. During monitoring, Apple Vision detects the face. The app derives a normalized head-position ratio from chin height and face size.
7. A sustained deviation from the baseline becomes a slouching state after the configured number of consecutive readings.
8. The app shows a gentle alert through the selected channel(s).
9. Two clearly upright readings are required before marking recovery, reducing flicker.
10. Only usable, calibrated good/slouching samples contribute to local history.

### Detection model in plain language

This is a seated framing heuristic. It tracks head position relative to the user’s own baseline; it does not reconstruct the spine or perform full-body pose analysis. Lowering the head or moving toward the camera generally lowers the calculated score.

### Default behavior

- Check interval: 0.5 seconds
- Confirm slouching after: 2 consecutive bad readings
- Sensitivity/tolerance: 18%
- Reminder cooldown: 90 seconds
- Animated notch alert: on
- macOS system notifications: off until enabled by the user
- Sound: off
- Pause after 5 minutes away: on

## 4. User experience and flows

### First launch / onboarding

Tone: calm, transparent, non-alarming.

Key messages:

- “A gentle reminder to sit comfortably.”
- “ItsMyBack lives in your menu bar and checks for changes in your seated posture.”
- Camera frames stay on the Mac.
- No recordings, uploads, or accounts.
- A clear view helps: whole face and both shoulders visible.
- Monitoring can pause when the user is idle, the Mac sleeps, or another app uses the camera.
- The user can choose **Enable camera** or **Set up later**.

Setup sequence:

1. Privacy explanation.
2. Explicit camera permission request.
3. Live camera preview and framing guidance.
4. “I’m sitting upright · Calibrate.”
5. Calibration progress: 20 usable readings.
6. “Finish setup.”

The user can cancel calibration. A failed or cancelled recalibration preserves the previous valid baseline.

### Menu-bar popover

The app is primarily accessed from the menu bar. The popover shows:

- Brand and camera status
- Current state and plain-language explanation
- Pause/resume or start controls
- Calibration control
- Today’s upright percentage
- Today’s tracked minutes
- Settings & history
- Preview notch alert
- Stop monitoring / quit

Primary status language:

- Ready: “Ready when you are”
- Needs setup: “Find your upright position”
- Calibrating: “Learning your posture”
- Good: “Sitting comfortably”
- Slouching: “Time for a posture check”
- Tracking lost: “Looking for you”
- Calibration failed: “Let’s try calibration again”

### Monitoring controls

- **Pause**: stops camera monitoring temporarily while the session remains enabled.
- **Resume monitoring**: resumes a manual pause.
- **I’m back**: resumes an idle pause.
- **Stop monitoring**: turns off the session and disables automatic restoration on later launches.
- **Launch at login**: optional and controlled through macOS login-item support.

Pause reasons are independent: manual pause, away from keyboard, Mac asleep, screen locked, and camera used by another app. Setup and calibration are not interrupted by idle pausing.

### Alerts

The preferred alert is a small non-activating top-of-screen “notch” or island alert. It does not take keyboard focus or bring the app forward.

Alert states include:

- “A little posture reset” — “Sit upright or take a stretch.”
- “Time to reset again” — “Relax your shoulders. Sit upright.”
- “Nice reset” — “Keep sitting comfortably.”
- “Face out of view” — “Move back into the camera’s view.”
- “Learning your posture” — “Sit comfortably upright and still.”
- “You’re ready” — “Your upright position is saved.”
- “Let’s try calibration again” — “Keep your face visible and stay still.”
- “Monitoring paused” — “Reminders resume with monitoring.”

Alert behavior:

- Spring expansion, content reveal, brief display, then dismissal
- One glow/reveal treatment
- Dismissible manually
- Supports Reduce Motion
- Supports Liquid Glass, black, white, and system appearance options
- Preview cycles through representative states

Additional channels:

- Optional macOS notifications, which require system permission
- Optional sound

Do not describe the app as interruptive, punitive, or judgmental. The product is a gentle cue, not a coach shouting at the user.

### Settings

Settings tabs:

1. **Settings**
   - Sensitivity: more sensitive ↔ more forgiving
   - Consecutive readings before confirmation
   - Check interval
   - Pause after 5 minutes away
   - Enable/disable posture reminders
   - Animated notch alerts
   - Notch appearance
   - macOS notifications
   - Sound
   - Time between reminders
   - Launch at login
   - Recalibrate upright position

2. **History**
   - Seven-day stacked bar chart
   - Upright and slouching minutes
   - Upright percentage by day
   - Reminder count
   - Empty state before data exists
   - Clear history action

3. **Privacy**
   - On-device Vision processing explanation
   - Frames discarded after processing
   - No video, photos, uploads, or network data
   - Stored data list
   - Detection limitations
   - macOS compatibility/version

## 5. Privacy and trust model

This is one of the product’s strongest differentiators and must be stated precisely.

### True claims supported by the implementation

- Camera frames are processed on the Mac with Apple’s Vision framework.
- Frames are not recorded, saved as photos, uploaded, or sent to a cloud service.
- There is no account requirement.
- The app has camera access but no network entitlement in its sandbox entitlements.
- Stored local data includes settings, calibration ratio, camera identifier, onboarding/session state, and daily totals.
- Monitoring can be paused to turn the camera off.
- The macOS camera indicator remains on while camera capture is active.
- History can be cleared without deleting settings or calibration.
- Unreadable local data is backed up before replacement where possible.

### Avoid these claims

- “100% accurate”
- “Clinically validated”
- “Prevents back pain”
- “Fixes your posture”
- “Understands your spine”
- “Detects every slouch”
- “Uses zero CPU/battery”
- “Never accesses the camera”
- “No data is stored” (settings, calibration, camera identifier, and daily totals are stored locally)

### Required limitation language

Use language such as:

> ItsMyBack provides a camera-based posture estimate, not a medical assessment. Results can be affected by camera placement, lighting, head rotation, face visibility, seating position, and body proportions. Recalibrate when your camera or seating changes.

History percentages describe tracked, usable samples—not the user’s entire workday. Missing detections, paused time, and calibration time are excluded.

## 6. Voice and messaging guidance

### Voice attributes

- Gentle
- Respectful
- Clear
- Reassuring
- Privacy-forward
- Practical
- Slightly warm, never cute for its own sake
- Encouraging without moralizing

### Preferred vocabulary

- sit comfortably
- posture check
- reset
- stretch
- upright position
- your baseline
- gentle reminder
- stays on your Mac
- processed on-device
- when you’re ready
- small adjustment
- looking for you

### Avoid

- lazy, bad, failing, unhealthy, shame, fix yourself
- “perfect posture”
- “slouch police”
- “we’re watching you”
- “AI-powered” as empty hype
- “surveillance,” even when discussing the product’s opposite intent
- medical or therapeutic promises

### Copy principles

1. Explain what the app knows and does not know.
2. Give the user control over camera, reminders, pause, sensitivity, and data.
3. Describe posture as a moment-to-moment comfort cue, not a moral score.
4. Put privacy claims next to camera-related actions.
5. Use direct, human actions: “Sit comfortably upright,” “Take a stretch,” “I’m back.”
6. Keep errors actionable: improve lighting, keep your face in view, close another camera app, or recalibrate.

## 7. Landing page brief

### Recommended page hierarchy

1. Hero: private posture reminders for your Mac
2. Explain the problem: posture drift happens quietly during long screen sessions
3. Show the experience: calibrate once → work normally → get a gentle cue → reset
4. Privacy section: on-device processing, no recordings, no uploads, no account
5. Feature cards: notch alerts, calibration, history, pause controls, sensitivity
6. How it works: face and shoulders in view; baseline; local estimate
7. Limitations/disclaimer
8. Compatibility and call to action

### Strong hero directions

Option A:

> A gentle reminder to sit comfortably.

Supporting copy: ItsMyBack notices changes in your seated posture and gives you a small cue to reset—privately, right from your Mac.

Option B:

> Your posture drifts. Your Mac can gently notice.

Supporting copy: Calibrate your comfortable upright position once, then let ItsMyBack quietly watch for changes without recording or uploading your camera feed.

Option C:

> Posture awareness, without the surveillance feeling.

Supporting copy: A private menu-bar companion for long desk sessions. On-device processing, gentle reminders, and local history.

### Suggested feature messaging

- **Private by design** — Camera frames stay on your Mac. No recordings, uploads, or accounts.
- **Calibrate to you** — Use your own comfortable upright position as the baseline.
- **A cue, not an interruption** — Small top-of-screen alerts help you reset without stealing focus.
- **Pause whenever you want** — Manual, idle, sleep, lock, and camera-sharing pauses keep you in control.
- **See the pattern** — Review seven days of local upright and slouching estimates.

### CTA directions

- Download for Mac
- Try ItsMyBack
- Start with a private posture check
- Set up your upright position

Do not imply a web account, cloud dashboard, subscription, or cross-device syncing unless those features are actually added.

## 8. Script and content generation guidance

When generating scripts, ads, videos, demos, or social posts, preserve this narrative:

1. Person begins a focused desk session.
2. Their posture gradually drifts; no exaggerated cartoon slouching is needed.
3. A subtle ItsMyBack alert appears at the top of the screen.
4. The person relaxes, sits comfortably, or stretches.
5. The script reinforces privacy: camera processing stays on-device; frames are discarded.
6. End with a low-pressure CTA.

### Good 30-second demo structure

“Long desk sessions have a way of changing your posture before you notice. ItsMyBack learns your comfortable upright position, then quietly checks for changes from the Mac menu bar. When you drift, a small reminder appears—no interruption, no account, and no video uploaded. Reset, stretch, and get back to your work. ItsMyBack: a gentle reminder to sit comfortably.”

### Visual direction

- Native macOS setting
- Clean desk, realistic posture drift
- Calm blue accent, neutral macOS materials
- Small top-center alert, never a giant warning banner
- Avoid medical imagery, red danger UI, shame-based before/after shots, or surveillance-camera motifs

## 9. Technical architecture for coding AIs

### Major files

- `PostureBuddyApp.swift`: app lifecycle, menu-bar status item, popover, onboarding window, icon updates, alert wiring
- `PostureMonitor.swift`: camera worker, Vision face detection, permissions, session state, pause/reconcile logic, notifications, history updates, login item
- `Core/PostureEngine.swift`: platform-independent posture metric, settings validation, calibration, detection state machine, nudge cooldown
- `Core/LocalData.swift`: Codable local model, daily summaries, retention, atomic local store
- `Core/InputActivity.swift`: keyboard/mouse idle detection
- `MenuBarView.swift`: menu-bar popover
- `OnboardingView.swift`: first-run privacy, camera setup, live preview, calibration
- `SettingsView.swift`: settings, history chart, privacy tab
- `NotchAlert.swift`: non-activating top-screen alert window and animation lifecycle
- `Resources/Info.plist`: bundle identity, camera usage description, macOS minimum
- `Resources/PostureBuddy.entitlements`: sandbox and camera entitlement

### State machine

Detection states:

- `needsCalibration`
- `calibrating`
- `good`
- `slouching`
- `noPerson`
- `calibrationFailed`

Session/pause state is separate from detection state. Do not conflate “slouching,” “camera unavailable,” “paused,” and “face not visible.”

### Important implementation constraints

- Camera capture and Vision run through a serial camera pipeline.
- Only numeric posture results and hints leave the camera worker.
- Main UI/state is main-actor controlled.
- Generation IDs reject stale results after stop, pause, restart, or superseded sessions.
- Camera frames still arrive while monitoring; only selected frames are analyzed.
- Data is local JSON with atomic writes.
- The app is sandboxed and intentionally has no network entitlement.
- Keep accessibility support: labels, announcements, keyboard support, Reduce Motion.

### Local data shape

`LocalData` contains:

- `settings`
- optional `calibration` with baseline, camera ID, date, and metric version
- onboarding completion
- monitoring-enabled preference
- daily summaries

Daily summaries retain at most 90 days and contain:

- good/upright seconds
- slouching seconds
- reminder count

## 10. Verification and product caveats

The core tests and universal compilation are verified. The following require real-hardware validation before making strong public claims:

- Camera permission allow/deny/revoke recovery
- Different lighting, camera heights, and seating positions
- Sustained slouching and recovery accuracy
- Reminder cooldown behavior, sound, notification denial, and Focus behavior
- Manual pause combined with idle, sleep, and lock
- Camera contention with video-call apps
- Camera disconnect/reconnect
- History rollover and relaunch behavior
- Launch at login
- CPU/battery impact
- Intel runtime behavior
- Developer ID signing, notarization, and clean installation

## 11. Reusable AI prompt

Use this when asking another AI to create product content:

> You are writing for ItsMyBack, a native macOS menu-bar posture-awareness app. It learns a user’s comfortable upright head position through a short calibration, then uses Apple Vision on the Mac to detect sustained changes in seated head position. It gives gentle, non-focus-stealing reminders through a small top-of-screen notch alert, with optional macOS notifications and sound. Camera frames are processed locally and discarded; there are no accounts, recordings, uploads, or cloud services. The product is a posture estimate, not a medical assessment, and it can be affected by camera angle, lighting, head rotation, face visibility, and seating changes. Use a calm, respectful, privacy-forward tone. Never shame the user or claim clinical accuracy, pain prevention, perfect posture, or full-body/spine understanding. Prefer language like “sit comfortably,” “reset,” “take a stretch,” “your baseline,” and “when you’re ready.” The public product name is ItsMyBack; PostureBuddy is an internal project name.

## 12. Source of truth and maintenance

If code behavior changes, update this document alongside the implementation. In particular, revisit:

- public name and version
- default settings
- privacy/storage behavior
- supported macOS versions
- alert copy and channels
- detection limitations
- landing-page claims
- verification status

