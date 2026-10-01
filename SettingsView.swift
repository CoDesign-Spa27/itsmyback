import SwiftUI
import Charts

struct SettingsView: View {
    @ObservedObject var monitor: PostureMonitor
    @State private var confirmClear = false

    var body: some View {
        TabView {
            Form {
                Section("Detection") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Sensitivity")
                        Slider(value: $monitor.settings.slouchTolerance, in: 0.10...0.30, step: 0.01) {
                            Text("Slouch tolerance")
                        }
                        HStack { Text("More sensitive"); Spacer(); Text("More forgiving") }.font(.caption).foregroundStyle(.secondary)
                    }
                    HStack(spacing: 8) {
                        Text("Confirm after")
                        Text("\(monitor.settings.consecutiveBadSamplesThreshold)")
                            .fontWeight(.bold)
                            .monospacedDigit()
                            .foregroundStyle(AppTheme.accent)
                        Text("consecutive readings")
                        Spacer()
                        Stepper("", value: $monitor.settings.consecutiveBadSamplesThreshold, in: 2...10)
                            .labelsHidden()
                            .accessibilityLabel("Consecutive readings before confirmation")
                    }
                    Picker("Check posture every", selection: $monitor.settings.sampleInterval) {
                        Text("0.5 seconds (quick)").tag(0.5)
                        Text("1 second").tag(1.0)
                        Text("2.5 seconds").tag(2.5)
                        Text("5 seconds").tag(5.0)
                        Text("10 seconds").tag(10.0)
                    }
                    Text("The first alert appears after confirmation. Reminder spacing applies while poor posture continues.").font(.caption).foregroundStyle(.secondary)
                    Toggle("Pause after 5 minutes away", isOn: $monitor.settings.idlePauseEnabled)
                }
                Section("Reminders") {
                    Toggle("Gentle posture reminders", isOn: $monitor.settings.notificationsEnabled)
                    Toggle("Animated notch alerts", isOn: $monitor.settings.notchAlertsEnabled).disabled(!monitor.settings.notificationsEnabled)
                    Picker("Notch alert appearance", selection: $monitor.settings.notchAlertAppearance) {
                        ForEach(NotchAlertAppearance.allCases, id: \.self) { appearance in
                            Text(appearance.title).tag(appearance)
                        }
                    }
                    Text("System uses black or white based on macOS. Liquid Glass follows the current system appearance.").font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Text("A small alert at the top of your screen. No notification permission needed.").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button("Preview notch alert") { monitor.previewNotchAlert() }
                    }
                    Toggle("Also send macOS notifications", isOn: $monitor.settings.systemNotificationsEnabled).disabled(!monitor.settings.notificationsEnabled)
                    Toggle("Play a sound", isOn: $monitor.settings.soundEnabled).disabled(!monitor.settings.notificationsEnabled)
                    Picker("Time between reminders", selection: $monitor.settings.nudgeCooldown) {
                        Text("5 seconds").tag(5.0)
                        Text("10 seconds").tag(10.0)
                        Text("30 seconds").tag(30.0)
                        Text("1 minute").tag(60.0)
                        Text("90 seconds").tag(90.0)
                        Text("3 minutes").tag(180.0)
                        Text("5 minutes").tag(300.0)
                        Text("10 minutes").tag(600.0)
                        Text("30 minutes").tag(1800.0)
                    }.disabled(!monitor.settings.notificationsEnabled)
                    if monitor.settings.systemNotificationsEnabled { HStack {
                        Text("Notifications: \(monitor.notificationStatus)").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button(monitor.notificationStatus == "Not requested" ? "Allow notifications" : "System settings") {
                            if monitor.notificationStatus == "Not requested" { monitor.requestNotifications() }
                            else { monitor.openNotificationSettings() }
                        }
                    }
                    Text("macOS Focus controls system banners. Notch alerts use your reminder preferences above.").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Section("General") {
                    Toggle("Launch at login", isOn: Binding(get: { monitor.loginEnabled }, set: { monitor.setLoginEnabled($0) }))
                    if let error = monitor.loginError { Text(error).font(.caption).foregroundStyle(.orange) }
                    if monitor.state == .calibrating && monitor.isRunning {
                        ProgressView("Learning your upright position…", value: monitor.calibrationProgress)
                        Button("Cancel calibration") { monitor.cancelCalibration() }
                    } else {
                        Button("Recalibrate upright position") { monitor.beginCalibration() }.disabled(!monitor.canCalibrate)
                    }
                    Text("Recalibrate after moving your camera, changing your chair, or adjusting your screen.").font(.caption).foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .tabItem { Label("Settings", systemImage: "slider.horizontal.3") }

            VStack(alignment: .leading, spacing: 20) {
                Text("Your last 7 days").font(.title2.weight(.semibold))
                Text("An estimate based on clear, calibrated readings. Paused time and missing detections are excluded.")
                    .font(.callout).foregroundStyle(.secondary)
                if monitor.days.allSatisfy({ $0.trackedSeconds == 0 }) {
                    ContentUnavailableView("Your history starts here", systemImage: "chart.bar", description: Text("Calibrate and start monitoring to see your daily upright time."))
                } else {
                    Chart(week) { day in
                        BarMark(x: .value("Day", day.id), y: .value("Upright", day.goodSeconds / 60)).foregroundStyle(by: .value("Posture", "Upright"))
                        BarMark(x: .value("Day", day.id), y: .value("Slouching", day.slouchSeconds / 60)).foregroundStyle(by: .value("Posture", "Slouching"))
                    }
                    .chartForegroundStyleScale(["Upright": Color.teal, "Slouching": Color.orange])
                    .chartYAxisLabel("Minutes")
                    .chartXAxis { AxisMarks { value in AxisValueLabel { if let key = value.as(String.self) { Text(String(key.suffix(5))) } } } }
                    .frame(height: 210)
                    List(week.reversed()) { day in
                        HStack {
                            Text(day.id)
                            Spacer()
                            Text(day.uprightPercent.map { "\($0)% upright" } ?? "No readings").foregroundStyle(.secondary)
                            Text("\(day.nudges) reminders").foregroundStyle(.secondary)
                        }.monospacedDigit()
                    }
                }
                HStack {
                    Text("Stored on this Mac for up to 90 days.").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Clear history…", role: .destructive) { confirmClear = true }.disabled(monitor.days.isEmpty)
                }
            }
            .padding(24)
            .tabItem { Label("History", systemImage: "chart.bar") }

            VStack(alignment: .leading, spacing: 20) {
                Label("Your camera stays local", systemImage: "lock.shield").font(.title2.weight(.semibold))
                Text("ItsMyBack analyzes camera frames with Apple’s Vision framework on your Mac. Frames are discarded after processing. The app does not record video, save photos, or send data over a network.")
                Text("Only your settings, calibration ratio, camera identifier, and daily totals are saved in Application Support/PostureBuddy. Clearing history removes the daily totals.")
                Text("Your camera indicator stays on while monitoring. Pause monitoring to turn the camera off.")
                Divider()
                Text("The posture estimate depends on camera angle, lighting, and visible landmarks. It can miss slouching or flag ordinary movement. Adjust sensitivity and recalibrate if readings seem wrong.").foregroundStyle(.secondary)
                Spacer()
                Text("ItsMyBack 1.0 · macOS 14 or later").font(.caption).foregroundStyle(.secondary)
            }
            .padding(28)
            .tabItem { Label("Privacy", systemImage: "lock.shield") }
        }
        .frame(width: 620, height: 630)
        .tint(AppTheme.accent)
        .alert("Clear all posture history?", isPresented: $confirmClear) {
            Button("Cancel", role: .cancel) {}
            Button("Clear history", role: .destructive) { monitor.clearHistory() }
        } message: { Text("This removes daily totals from this Mac. Settings and calibration are kept.") }
        .onAppear { monitor.recordInteraction(); monitor.refreshNotificationStatus() }
    }

    private var week: [DailySummary] {
        (0..<7).reversed().compactMap { offset in
            guard let date = Calendar.current.date(byAdding: .day, value: -offset, to: Date()) else { return nil }
            let key = DailySummary.dayKey(date)
            return monitor.days.first { $0.id == key } ?? DailySummary(id: key)
        }
    }
}

#Preview {
    SettingsView(
        monitor: PostureMonitor()
    )
}
