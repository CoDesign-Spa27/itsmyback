import AppKit
import SwiftUI
import Combine

// Original implementation. Motion reference: boring.notch's drop.swift (spring
// opening).
// No third-party implementation or path geometry is included.

private struct IslandLayout {
    var width: CGFloat
    var collapsedWidth: CGFloat
    var cutoutHeight: CGFloat
    var topMargin: CGFloat
    var attached: Bool
    var expandedHeight: CGFloat { cutoutHeight + 76 }

    init(width: CGFloat, collapsedWidth: CGFloat, cutoutHeight: CGFloat, topMargin: CGFloat, attached: Bool) {
        self.width = width
        self.collapsedWidth = collapsedWidth
        self.cutoutHeight = cutoutHeight
        self.topMargin = topMargin
        self.attached = attached
    }

    static let preview = IslandLayout(
        width: 420,
        collapsedWidth: 180,
        cutoutHeight: 0,
        topMargin: 12,
        attached: false
    )

    init(screen: NSScreen) {
        attached = screen.safeAreaInsets.top > 0
        cutoutHeight = attached ? screen.safeAreaInsets.top : 0
        topMargin = attached ? 0 : 12
        let notchWidth: CGFloat
        if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            notchWidth = screen.frame.width - left.width - right.width
        } else { notchWidth = 180 }
        collapsedWidth = attached ? max(120, notchWidth) : 150
        width = min(screen.frame.width - 32, max(328, collapsedWidth + 100))
    }
}

private enum IslandFeedback {
    case warning, reminder, recovered, trackingLost, calibrating, ready, calibrationFailed, paused
    var title: String {
        switch self {
        case .warning: "A little posture reset"
        case .reminder: "Time to reset again"
        case .recovered: "Nice reset"
        case .trackingLost: "Face out of view"
        case .calibrating: "Learning your posture"
        case .ready: "You're ready"
        case .calibrationFailed: "Let's try calibration again"
        case .paused: "Monitoring paused"
        }
    }
    var detail: String {
        switch self {
        case .warning: "Sit upright or take a stretch."
        case .reminder: "Relax your shoulders. Sit upright."
        case .recovered: "Keep sitting comfortably."
        case .trackingLost: "Move back into the camera's view."
        case .calibrating: "Sit comfortably upright and still."
        case .ready: "Your upright position is saved."
        case .calibrationFailed: "Keep your face visible and stay still."
        case .paused: "Reminders resume with monitoring."
        }
    }
    var symbol: String {
        switch self {
        case .warning: "figure.seated.side"
        case .reminder: "bell.badge.fill"
        case .recovered, .ready: "checkmark"
        case .trackingLost: "person.crop.rectangle.badge.exclamationmark"
        case .calibrating: "viewfinder"
        case .calibrationFailed: "arrow.clockwise"
        case .paused: "pause.fill"
        }
    }
    var color: Color {
        switch self {
        case .warning: .orange
        case .reminder: .yellow
        case .recovered: .green
        case .trackingLost: .gray
        case .calibrating: .cyan
        case .ready: .mint
        case .calibrationFailed: .red
        case .paused: .purple
        }
    }
}

@MainActor
private final class IslandModel: ObservableObject {
    @Published var expanded = false
    @Published var contentVisible = false
    @Published var feedback: IslandFeedback = .warning
    @Published var appearance: NotchAlertAppearance = .system
    var preview = false
}

@MainActor
final class NotchAlertController {
    private let model = IslandModel()
    private var panel: IslandPanel?
    private var lifecycle: Task<Void, Never>?
    private var trackingLostTask: Task<Void, Never>?
    private var lastPosture: DetectionState?
    private var repeatedWarning = false
    private var warningWasShown = false
    private var trackingLostWasShown = false
    private var screenObserver: NSObjectProtocol?

    init() {
        screenObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.dismiss() }
        }
    }

    func show(preview: Bool = false, appearance: NotchAlertAppearance = .system) {
        trackingLostTask?.cancel()
        present(preview: preview, appearance: appearance, feedback: repeatedWarning && !preview ? .reminder : .warning)
        if !preview {
            repeatedWarning = true
            warningWasShown = true
        }
    }

    private func present(preview: Bool = false, appearance: NotchAlertAppearance = .system, feedback: IslandFeedback) {
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main ?? NSScreen.screens.first else { return }
        lifecycle?.cancel()
        let layout = IslandLayout(screen: screen)
        let window = panel ?? IslandPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel = window
        window.isReleasedWhenClosed = false
        window.backgroundColor = .clear
        window.appearance = nil
        window.isOpaque = false
        window.hasShadow = false
        window.hidesOnDeactivate = false
        window.isFloatingPanel = true
        window.becomesKeyOnlyIfNeeded = true
        window.level = .init(rawValue: NSWindow.Level.screenSaver.rawValue - 1)
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        window.isMovable = false
        window.setFrame(NSRect(x: screen.frame.midX - (layout.width + 40) / 2, y: screen.frame.maxY - (layout.expandedHeight + layout.topMargin + 32), width: layout.width + 40, height: layout.expandedHeight + layout.topMargin + 32), display: false)
        model.preview = preview
        model.appearance = appearance
        model.feedback = feedback
        model.expanded = false
        model.contentVisible = false
        window.contentView = FirstClickHostingView(rootView: IslandAlertView(model: model, layout: layout, dismiss: { [weak self] in self?.dismiss() }))
        window.orderFrontRegardless()
        let reduced = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        lifecycle = Task { [weak self] in
            guard let self else { return }
            do {
                // Allow the collapsed cap to render before the spring expands it.
                try await Task.sleep(for: .milliseconds(30))
                withAnimation(reduced ? .easeOut(duration: 0.15) : .spring(duration: 0.28, bounce: 0.12)) { model.expanded = true }
                try await Task.sleep(for: .milliseconds(reduced ? 0 : 60))
                withAnimation(.easeOut(duration: 0.18)) { model.contentVisible = true }
                NSAccessibility.post(element: window, notification: .announcementRequested, userInfo: [.announcement: feedback.title + ". " + feedback.detail, .priority: NSAccessibilityPriorityLevel.high.rawValue])
                if preview {
                    for next in [IslandFeedback.reminder, .trackingLost, .calibrating, .ready, .recovered] {
                        try await Task.sleep(for: .seconds(1.5))
                        withAnimation(.easeOut(duration: 0.18)) { model.feedback = next }
                    }
                } else {
                    try await Task.sleep(for: .seconds(4))
                }
                dismiss()
            } catch { /* A newer alert or dismissal owns the window now. */ }
        }
    }

    func update(posture: DetectionState, appearance: NotchAlertAppearance) {
        guard !model.preview else { return }
        let previous = lastPosture
        lastPosture = posture
        guard previous != posture else { return }

        trackingLostTask?.cancel()
        trackingLostTask = nil
        model.appearance = appearance

        // Face detection can miss a single frame during an ordinary movement.
        // Keep the menu-bar state immediate, but only interrupt with an alert
        // when tracking has remained lost briefly.
        if posture == .noPerson {
            trackingLostTask = Task { [weak self] in
                do {
                    try await Task.sleep(for: .seconds(1))
                    guard let self, self.lastPosture == .noPerson, !self.model.preview else { return }
                    self.trackingLostWasShown = true
                    self.showStateFeedback(.trackingLost, appearance: appearance)
                    self.trackingLostTask = nil
                } catch {}
            }
            return
        }

        if posture == .calibrating {
            trackingLostWasShown = false
            present(appearance: appearance, feedback: .calibrating)
            return
        }
        if previous == .calibrating {
            if posture == .good { present(appearance: appearance, feedback: .ready); return }
            if posture == .calibrationFailed { present(appearance: appearance, feedback: .calibrationFailed); return }
        }

        switch posture {
        case .good:
            repeatedWarning = false
            if warningWasShown || trackingLostWasShown {
                warningWasShown = false
                trackingLostWasShown = false
                showStateFeedback(.recovered, appearance: appearance)
            }
        case .calibrationFailed:
            trackingLostWasShown = false
            showStateFeedback(.calibrationFailed, appearance: appearance)
        case .needsCalibration:
            warningWasShown = false
            trackingLostWasShown = false
            dismiss()
        case .slouching:
            // Warnings are opened only by show(), which is driven by the
            // detector's confirmation threshold and reminder cooldown.
            break
        case .noPerson, .calibrating:
            break
        }
    }

    private func showStateFeedback(_ feedback: IslandFeedback, appearance: NotchAlertAppearance) {
        if panel?.isVisible == true { transition(to: feedback) }
        else { present(appearance: appearance, feedback: feedback) }
    }

    private func transition(to feedback: IslandFeedback, seconds: Double = 2) {
        lifecycle?.cancel()
        withAnimation(.easeOut(duration: 0.18)) { model.feedback = feedback }
        if let panel {
            NSAccessibility.post(element: panel, notification: .announcementRequested, userInfo: [.announcement: feedback.title + ". " + feedback.detail, .priority: NSAccessibilityPriorityLevel.high.rawValue])
        }
        lifecycle = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(seconds)); self?.dismiss() } catch {}
        }
    }

    func dismissDetectionAlert() {
        trackingLostTask?.cancel()
        trackingLostTask = nil
        if !model.preview, panel?.isVisible == true, model.feedback != .paused {
            transition(to: .paused)
        }
    }

    func dismiss() {
        lifecycle?.cancel()
        guard let panel, panel.isVisible else { return }
        let reduced = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        withAnimation(.easeOut(duration: reduced ? 0.12 : 0.24)) {
            model.contentVisible = false
            model.expanded = false
        }
        lifecycle = Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(reduced ? 140 : 280))
                guard !Task.isCancelled else { return }
                panel.orderOut(nil)
                self?.model.preview = false
                self?.lifecycle = nil
            } catch {}
        }
    }

    func shutdown() {
        trackingLostTask?.cancel()
        lifecycle?.cancel()
        panel?.orderOut(nil)
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        screenObserver = nil
    }
}

private final class IslandPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private final class FirstClickHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

private struct IslandAlertView: View {
    @ObservedObject var model: IslandModel
    let layout: IslandLayout
    let dismiss: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var color: Color { model.feedback.color }
    private var systemColorScheme: ColorScheme {
        let appearance = NSApp?.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) ?? .aqua
        return appearance == .darkAqua ? .dark : .light
    }
    private var forcedColorScheme: ColorScheme? {
        switch model.appearance {
        case .black: .dark
        case .white: .light
        case .liquidGlass, .system: nil
        }
    }
    private var colorScheme: ColorScheme { forcedColorScheme ?? systemColorScheme }
    private var primaryForeground: Color { colorScheme == .dark ? .white : .black.opacity(0.82) }
    private var secondaryForeground: Color { colorScheme == .dark ? .white.opacity(0.62) : .black.opacity(0.58) }
    private var borderColor: Color { colorScheme == .dark ? .white.opacity(0.14) : .black.opacity(0.12) }
    private var buttonForeground: Color { colorScheme == .dark ? .white.opacity(0.72) : .black.opacity(0.58) }
    private var buttonBackground: Color { colorScheme == .dark ? .white.opacity(0.1) : .black.opacity(0.07) }
    private var backgroundGradient: LinearGradient {
        let colors: [Color]
        switch model.appearance {
        case .black:
            colors = [.black, .black]
        case .white:
            colors = [.white, .white]
        case .system:
            colors = colorScheme == .dark ? [.black, .black] : [.white, .white]
        case .liquidGlass:
            colors = colorScheme == .dark
                ? [Color.white.opacity(0.12), Color.white.opacity(0.05), Color.black.opacity(0.14)]
                : [Color.white.opacity(0.7), Color.white.opacity(0.5), Color.black.opacity(0.03)]
        }
        return LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom)
    }
    private var silhouette: UnevenRoundedRectangle {
        UnevenRoundedRectangle(topLeadingRadius: layout.attached ? 0 : 26, bottomLeadingRadius: 26, bottomTrailingRadius: 26, topTrailingRadius: layout.attached ? 0 : 26)
    }
    @ViewBuilder
    private var surface: some View {
        if model.appearance == .liquidGlass, #available(macOS 26.0, *) {
            silhouette
                .fill(backgroundGradient)
                .glassEffect(.regular, in: silhouette)
        } else {
            silhouette.fill(backgroundGradient)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                surface
                    .overlay { silhouette.stroke(borderColor, lineWidth: 0.5) }
                HStack(spacing: 12) {
                    Image(systemName: model.feedback.symbol)
                        .font(.system(size: 23, weight: .medium))
                        .foregroundStyle(color)
                        .frame(width: 40, height: 40)
                        .background(color.opacity(0.14), in: RoundedRectangle(cornerRadius: 13))
                        .scaleEffect(model.contentVisible || reduceMotion ? 1 : 0.76)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(model.feedback.title)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(primaryForeground)
                        Text(model.feedback.detail)
                            .font(.system(size: 11))
                            .foregroundStyle(secondaryForeground)
                    }
                    .fixedSize(horizontal: true, vertical: false)
                    Spacer(minLength: 0)
                    Button(action: dismiss) {
                        Image(systemName: "xmark").font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(buttonForeground)
                            .frame(width: 24, height: 24)
                            .background(buttonBackground, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .help("Dismiss posture alert")
                    .accessibilityLabel("Dismiss posture alert")
                }
                .padding(.horizontal, 17)
                .padding(.top, layout.cutoutHeight + 18)
                .opacity(model.contentVisible ? 1 : 0)
                .blur(radius: reduceMotion || model.contentVisible ? 0 : 3)
                .allowsHitTesting(model.contentVisible)
                .accessibilityHidden(!model.contentVisible)
            }
            .frame(width: model.expanded ? layout.width : layout.collapsedWidth, height: model.expanded ? layout.expandedHeight : max(8, layout.cutoutHeight))
            .clipShape(silhouette)
            .shadow(color: .black.opacity(model.expanded ? 0.3 : 0), radius: 10, y: 5)
            .opacity(model.expanded || layout.attached ? 1 : 0)
            Spacer(minLength: 0)
        }
        .padding(.top, layout.topMargin)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .preferredColorScheme(forcedColorScheme)
    }
}


private struct IslandAlertPreview: View {
    let feedback: IslandFeedback

    var body: some View {
        let model = IslandModel()
        model.expanded = true
        model.contentVisible = true
        model.feedback = feedback

        return IslandAlertView(
            model: model,
            layout: .preview,
            dismiss: {}
        )
        .frame(width: 460, height: 150)
    }
}

#Preview("Warning") {
    IslandAlertPreview(feedback: .warning)
}

#Preview("Reminder") {
    IslandAlertPreview(feedback: .reminder)
}

#Preview("Tracking lost") {
    IslandAlertPreview(feedback: .trackingLost)
}

#Preview("Calibrating") {
    IslandAlertPreview(feedback: .calibrating)
}

#Preview("Ready") {
    IslandAlertPreview(feedback: .ready)
}

#Preview("Recovered") {
    IslandAlertPreview(feedback: .recovered)
}
