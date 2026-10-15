import SwiftUI
import AppKit
import Combine

enum AppTheme {
    static let accent = Color(red: 58 / 255, green: 97 / 255, blue: 223 / 255)
}

@main
struct PostureBuddyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    var body: some Scene {
        Settings { SettingsView(monitor: appDelegate.monitor).tint(AppTheme.accent) }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let monitor = PostureMonitor()
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private var welcomeWindow: NSWindow?
    private var observation: AnyCancellable?
    private let notchAlerts = NotchAlertController()
    private var alertStateObservation: AnyCancellable?
    private var alertAvailabilityObservation: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem?.button?.target = self
        statusItem?.button?.action = #selector(togglePopover)
        statusItem?.button?.setAccessibilityLabel("ItsMyBack")
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: MenuBarView(monitor: monitor, showWelcome: { [weak self] in self?.showWelcome() }))
        observation = monitor.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.updateIcon() }
        }
        updateIcon()
        monitor.onNudge = { [weak self] in
            guard let self else { return }
            self.notchAlerts.show(appearance: self.monitor.settings.notchAlertAppearance)
        }
        monitor.onPreviewNudge = { [weak self] in
            guard let self else { return }
            self.notchAlerts.show(preview: true, appearance: self.monitor.settings.notchAlertAppearance)
        }
        // Observe the published state itself so the alert receives the exact
        // transition that the menu bar is rendering. `objectWillChange` fires
        // before a @Published value changes and is too broad for state routing.
        alertStateObservation = monitor.$state.removeDuplicates().sink { [weak self] state in
            DispatchQueue.main.async {
                guard let self, self.alertsAreAvailable else { return }
                self.notchAlerts.update(posture: state, appearance: self.monitor.settings.notchAlertAppearance)
            }
        }
        alertAvailabilityObservation = monitor.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async {
                guard let self else { return }
                if !self.alertsAreAvailable {
                    self.notchAlerts.dismissDetectionAlert()
                } else {
                    // Becoming active can happen without a posture transition
                    // (for example, resuming while tracking is already lost).
                    self.notchAlerts.update(posture: self.monitor.state, appearance: self.monitor.settings.notchAlertAppearance)
                }
            }
        }
        if monitor.onboardingComplete { monitor.restoreSession() } else { showWelcome() }
    }

    private var alertsAreAvailable: Bool {
        monitor.isRunning && monitor.pauseReasons.isEmpty && monitor.settings.notificationsEnabled && monitor.settings.notchAlertsEnabled
    }

    private func updateIcon() {
        let symbol = monitor.isRunning && monitor.state == .slouching ? "figure.seated.side" : monitor.isRunning ? "figure.stand" : "pause.circle"
        statusItem?.button?.image = NSImage(systemSymbolName: symbol, accessibilityDescription: monitor.statusTitle)
        statusItem?.button?.toolTip = "ItsMyBack · \(monitor.statusTitle)"
    }

    @objc private func togglePopover() {
        monitor.recordInteraction()
        guard let button = statusItem?.button else { return }
        if popover.isShown { popover.performClose(nil) }
        else { popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY) }
    }

    func showWelcome() {
        popover.performClose(nil)
        if welcomeWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 560), styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.title = "Welcome to ItsMyBack"
            window.isReleasedWhenClosed = false
            window.contentViewController = NSHostingController(rootView: OnboardingView(monitor: monitor, finish: { [weak self] in
                self?.monitor.finishOnboarding()
                self?.welcomeWindow?.close()
            }))
            window.center()
            welcomeWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        welcomeWindow?.makeKeyAndOrderFront(nil)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !monitor.onboardingComplete { showWelcome() }
        else if let button = statusItem?.button { popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY) }
        return false
    }
    func applicationWillTerminate(_ notification: Notification) { notchAlerts.shutdown(); monitor.shutdown() }
}
