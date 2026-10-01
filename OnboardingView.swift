import SwiftUI
import AppKit

struct OnboardingView: View {
    @ObservedObject var monitor: PostureMonitor
    var finish: () -> Void

    private var brandImage: Image {
        guard
            let url = Bundle.main.url(forResource: "BrandIcon", withExtension: "png"),
            let image = NSImage(contentsOf: url)
        else {
            return Image(systemName: "figure.seated.side")
        }
        return Image(nsImage: image)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            brandImage
                .resizable()
                .scaledToFit()
                .frame(width: 72, height: 72)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 8) {
                Text("A gentle reminder\nto sit comfortably.").font(.system(size: 30, weight: .semibold))
                Text("ItsMyBack lives in your menu bar and checks for changes in your seated posture.").foregroundStyle(.secondary)
            }
            if !monitor.cameraReady {
              VStack(alignment: .leading, spacing: 16) {
                feature("lock.shield", "Private by design", "Camera frames stay on your Mac. No recordings, uploads, or accounts.")
                feature("camera", "A clear view helps", "Face the camera with your whole face visible. Sit comfortably upright to set your baseline.")
                feature("pause.circle", "Room to step away", "Monitoring pauses when you’re idle, your Mac sleeps, or another app uses your camera.")
              }
            } else {
                Label("Live preview · stays on your Mac", systemImage: "lock.shield").font(.caption).foregroundStyle(.secondary)
            }
            Divider()
            if monitor.isCalibrated {
                Label("Your upright position is saved", systemImage: "checkmark.circle").foregroundStyle(.green)
                Button("Finish setup", action: finish).buttonStyle(.borderedProminent).controlSize(.large)
            } else if monitor.permissionPending {
                ProgressView("Waiting for camera permission…")
                Text(monitor.statusDetail).font(.callout).foregroundStyle(.secondary)
            } else if !monitor.pauseReasons.isEmpty && !monitor.cameraDenied {
                Text(monitor.statusDetail).font(.callout).foregroundStyle(.secondary)
                Button("Resume camera setup") { monitor.resumeFromPause(); monitor.start() }.buttonStyle(.borderedProminent)
            } else if monitor.isRunning {
                if monitor.cameraReady {
                    monitor.cameraPreview
                        .frame(height: 170)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .accessibilityLabel("Live camera view for positioning your head")
                    Text(monitor.detectionHint).font(.callout).foregroundStyle(monitor.poseVisible ? Color.green : Color.secondary)
                }
                Text(monitor.statusDetail).font(.callout).foregroundStyle(.secondary)
                if monitor.state == .calibrating {
                    HStack(spacing: 16) {
                        CalibrationLoader(progress: monitor.calibrationProgress)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Finding your steady position…")
                                .font(.headline)
                            Text("\(Int((monitor.calibrationProgress * 20).rounded())) of 20 usable readings")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Calibration progress")
                    .accessibilityValue("\(Int((monitor.calibrationProgress * 100).rounded())) percent")
                    Button("Cancel calibration") { monitor.cancelCalibration() }
                } else {
                    if !monitor.cameraReady { ProgressView("Starting camera…").controlSize(.small) }
                    Button("I'm sitting upright · Calibrate") { monitor.beginCalibration() }
                        .buttonStyle(.borderedProminent).disabled(!monitor.canCalibrate)
                }
            } else {
                if monitor.cameraDenied || monitor.cameraError != nil {
                    Text(monitor.statusDetail).font(.callout).foregroundStyle(.secondary)
                }
                HStack {
                    Button(monitor.cameraDenied || monitor.cameraError != nil ? "Try camera again" : "Enable camera") { monitor.start() }
                        .buttonStyle(.borderedProminent).controlSize(.large)
                    if monitor.cameraDenied { Button("Open camera settings") { monitor.openCameraSettings() } }
                }
            }
            HStack {
                Text("A posture estimate, not a medical assessment.").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Set up later") { monitor.stop(); finish() }.font(.caption)
            }
        }
        .padding(32)
        .frame(width: 520)
        .fixedSize(horizontal: false, vertical: true)
        .tint(AppTheme.accent)
        .onAppear { monitor.recordInteraction() }
    }
    private func feature(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol).font(.title3).foregroundStyle(AppTheme.accent).frame(width: 24).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(detail).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct CalibrationLoader: View {
    let progress: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isAnimating = false
    private let accent = AppTheme.accent

    private var clampedProgress: Double { min(1, max(0, progress)) }

    var body: some View {
        ZStack {
            Circle()
                .stroke(.quaternary, lineWidth: 6)
            Circle()
                .trim(from: 0, to: max(0.02, clampedProgress))
                .stroke(accent, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Circle()
                .trim(from: 0.08, to: 0.72)
                .stroke(accent.opacity(0.42), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .rotationEffect(.degrees(isAnimating && !reduceMotion ? 360 : 0))
                .scaleEffect(isAnimating && !reduceMotion ? 1 : 0.94)
                .opacity(isAnimating && !reduceMotion ? 1 : 0.72)
        }
        .frame(width: 68, height: 68)
        .animation(
            reduceMotion ? nil : .linear(duration: 1.1).repeatForever(autoreverses: false),
            value: isAnimating
        )
        .onAppear { isAnimating = true }
        .accessibilityHidden(true)
    }
}

#Preview("Welcome") {
    OnboardingView(monitor: .makePreview(), finish: {})
}

#Preview("Permission waiting") {
    OnboardingView(monitor: .makePreview(permissionPending: true), finish: {})
}

#Preview("Camera denied") {
    OnboardingView(monitor: .makePreview(cameraDenied: true), finish: {})
}

#Preview("Camera unavailable") {
    OnboardingView(
        monitor: .makePreview(cameraError: "The camera is being used by another app."),
        finish: {}
    )
}

#Preview("Paused") {
    OnboardingView(monitor: .makePreview(pauseReason: "Mac asleep"), finish: {})
}

#Preview("Camera ready") {
    OnboardingView(
        monitor: .makePreview(isRunning: true, cameraReady: true, poseVisible: true),
        finish: {}
    )
}

#Preview("Calibrating") {
    OnboardingView(
        monitor: .makePreview(
            isRunning: true,
            cameraReady: true,
            state: .calibrating,
            calibrationProgress: 0.55,
            poseVisible: true
        ),
        finish: {}
    )
}

#Preview("Finish setup") {
    OnboardingView(
        monitor: .makePreview(isCalibrated: true),
        finish: {}
    )
}
