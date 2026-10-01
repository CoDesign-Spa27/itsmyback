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
                    ProgressView(value: monitor.calibrationProgress).accessibilityLabel("Calibration progress")
                    Text("\(Int((monitor.calibrationProgress * 20).rounded())) of 20 usable readings").font(.caption).foregroundStyle(.secondary)
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
        .onAppear { monitor.recordInteraction() }
    }
    private func feature(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol).font(.title3).foregroundStyle(Color.accentColor).frame(width: 24).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(detail).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

#Preview {
    OnboardingView(
        monitor: PostureMonitor(),
        finish: {}
    )
}
