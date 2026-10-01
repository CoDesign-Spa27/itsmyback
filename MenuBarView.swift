import SwiftUI
import AppKit

struct MenuBarView: View {
    @ObservedObject var monitor: PostureMonitor
    var showWelcome: () -> Void

    private var brandImage: Image {
        guard
            let url = Bundle.main.url(forResource: "BrandIcon", withExtension: "png"),
            let image = NSImage(contentsOf: url)
        else {
            return Image(systemName: "figure.stand")
        }
        return Image(nsImage: image)
    }

    private var statusColor: Color {
        if !monitor.pauseReasons.isEmpty || !monitor.isRunning { return .secondary }
        if monitor.cameraError != nil || monitor.cameraDenied { return .orange }
        switch monitor.state {
        case .good: return .green
        case .slouching, .calibrationFailed: return .orange
        case .calibrating: return .accentColor
        default: return .secondary
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                brandImage
                    .resizable()
                    .scaledToFit()
                    .frame(width: 30, height: 30)
                    .accessibilityHidden(true)
                Text("ItsMyBack").font(.system(size: 14, weight: .semibold))
                Spacer()
                HStack(spacing: 5) {
                    Circle().fill(monitor.cameraReady ? Color.green : Color.secondary)
                        .frame(width: 5, height: 5)
                    Text(monitor.cameraReady ? "Camera on" : monitor.isRunning ? "Starting…" : "Camera off")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Menu {
                    Button("Preview notch alert", systemImage: "rectangle.topthird.inset.filled") { monitor.previewNotchAlert() }
                    Button(monitor.isCalibrated ? "Recalibrate…" : "Calibrate…", systemImage: "viewfinder") { monitor.beginCalibration() }
                        .disabled(!monitor.canCalibrate || monitor.state == .calibrating)
                    if monitor.isRunning || !monitor.pauseReasons.isEmpty {
                        Button("Stop monitoring", systemImage: "stop.circle") { monitor.stop() }
                    }
                    Divider()
                    Button("Quit ItsMyBack") { NSApp.terminate(nil) }.keyboardShortcut("q")
                } label: {
                    Image(systemName: "ellipsis.circle").font(.system(size: 15)).foregroundStyle(.secondary)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("More options")
                .accessibilityLabel("More options")
            }
            .padding(.horizontal, 18).padding(.vertical, 14)

            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: monitor.statusSymbol)
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(statusColor)
                        .frame(width: 44, height: 44)
                        .background(statusColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 13))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(monitor.statusTitle)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(monitor.statusDetail)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .lineSpacing(2)
                    }
                }
                if monitor.state == .calibrating && monitor.isRunning {
                    VStack(alignment: .leading, spacing: 8) {
                        ProgressView(value: monitor.calibrationProgress).accessibilityLabel("Calibration progress")
                        Text(monitor.detectionHint).font(.caption).foregroundStyle(.secondary)
                        Button("Cancel calibration") { monitor.cancelCalibration() }.controlSize(.small)
                    }
                }
                if let error = monitor.storageError { Text(error).font(.caption).foregroundStyle(.orange) }
                primaryControl
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            .overlay { RoundedRectangle(cornerRadius: 16).strokeBorder(.primary.opacity(0.06), lineWidth: 0.5) }
            .padding(.horizontal, 12)

            VStack(alignment: .leading, spacing: 10) {
                Text("Today").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                HStack(spacing: 0) {
                    metric(monitor.today.uprightPercent.map { "\($0)%" } ?? "—", label: "Upright")
                    Divider().frame(height: 30).padding(.horizontal, 18)
                    metric("\(Int(monitor.today.trackedSeconds / 60)) min", label: "Tracked")
                    Spacer(minLength: 0)
                }
                if let percent = monitor.today.uprightPercent {
                    ProgressView(value: Double(percent), total: 100)
                        .tint(.green)
                        .accessibilityLabel("Today’s upright posture")
                        .accessibilityValue("\(percent) percent")
                } else {
                    Text("Your progress appears as you sit.").font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(18)

            Divider().padding(.horizontal, 12)
            SettingsLink {
                HStack {
                    Label("Settings & history", systemImage: "slider.horizontal.3")
                    Spacer()
                    Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold)).foregroundStyle(.tertiary)
                }
                .font(.system(size: 12))
                .foregroundStyle(.primary)
                .padding(.horizontal, 18).padding(.vertical, 13)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .simultaneousGesture(TapGesture().onEnded { NSApp.activate(ignoringOtherApps: true); monitor.refreshNotificationStatus() })
        }
        .frame(width: 320)
        .background(.thinMaterial)
        .onAppear { monitor.recordInteraction() }
    }

    private func metric(_ value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value).font(.system(size: 19, weight: .semibold, design: .rounded)).monospacedDigit()
            Text(label).font(.system(size: 11)).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var primaryControl: some View {
        if !monitor.onboardingComplete {
            Button("Set up ItsMyBack", action: showWelcome).buttonStyle(.borderedProminent)
        } else if monitor.permissionPending {
            ProgressView("Waiting for camera permission…").controlSize(.small).font(.caption)
        } else if monitor.cameraDenied {
            HStack {
                Button("Camera settings") { monitor.openCameraSettings() }
                Button("Try again") { monitor.start() }
            }
        } else if monitor.cameraError != nil || (!monitor.isRunning && monitor.pauseReasons.isEmpty) {
            Button("Start monitoring", systemImage: "play.fill") { monitor.start() }.buttonStyle(.borderedProminent)
        } else {
            HStack {
                if monitor.pauseReasons.contains("You paused") {
                    Button("Resume monitoring", systemImage: "play.fill") { monitor.resumeFromPause() }
                } else if monitor.pauseReasons.contains("Away from keyboard") {
                    Button("I’m back", systemImage: "play.fill") { monitor.resumeFromPause() }
                } else {
                    Button("Pause", systemImage: "pause.fill") { monitor.toggleManualPause() }
                }
                Spacer()
                if !monitor.isCalibrated && monitor.state != .calibrating {
                    Button("Calibrate") { monitor.beginCalibration() }.disabled(!monitor.canCalibrate)
                }
            }.controlSize(.small)
        }
    }
}

#Preview {
    MenuBarView(
        monitor: PostureMonitor(),
        showWelcome: {}
    )
}
