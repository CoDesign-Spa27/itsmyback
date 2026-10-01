import AppKit
import AVFoundation
import Combine
import Vision
import UserNotifications
import ServiceManagement
import SwiftUI

struct PoseMeasurement: Sendable {
    var ratio: Double?
    var hint: String
}

/// Owns AVFoundation exclusively on a serial queue. Only numeric results leave it.
final class CameraPipeline: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.posturebuddy.camera", qos: .utility)
    private let session = AVCaptureSession()
    private var input: AVCaptureDeviceInput?
    private var output: AVCaptureVideoDataOutput?
    private var observers: [NSObjectProtocol] = []
    private var generation = 0
    private var interval = 2.5
    private var lastSample = -Double.infinity
    private var active = false
    var onSample: (@Sendable (PoseMeasurement, Int) -> Void)?
    var onStatus: (@Sendable (String?, String?, Int) -> Void)?

    func start(generation: Int, interval: Double) {
        queue.async { [self] in
            self.generation = generation
            self.interval = interval
            lastSample = -Double.infinity
            do {
                if let input, !input.device.isConnected || input.device.uniqueID != AVCaptureDevice.default(for: .video)?.uniqueID {
                    if session.isRunning { session.stopRunning() }
                    session.beginConfiguration()
                    session.removeInput(input)
                    if let output { session.removeOutput(output) }
                    session.commitConfiguration()
                    self.input = nil
                    self.output = nil
                    observers.forEach { NotificationCenter.default.removeObserver($0) }
                    observers = []
                }
                if input == nil { try configure() }
                active = true
                if !session.isRunning { session.startRunning() }
                if session.isRunning { onStatus?(nil, input?.device.uniqueID, generation) }
                else { active = false; onStatus?("The camera could not start. Close other camera apps and try again.", nil, generation) }
            } catch {
                active = false
                onStatus?(error.localizedDescription, nil, generation)
            }
        }
    }

    func stop(generation: Int) {
        queue.async { [self] in
            self.generation = generation
            active = false
            if session.isRunning { session.stopRunning() }
        }
    }

    func setInterval(_ value: Double) { queue.async { self.interval = value } }

    @MainActor func makePreviewLayer() -> AVCaptureVideoPreviewLayer {
        AVCaptureVideoPreviewLayer(session: session)
    }

    private func configure() throws {
        guard let device = AVCaptureDevice.default(for: .video), device.isConnected else {
            throw NSError(domain: "backbone", code: 1, userInfo: [NSLocalizedDescriptionKey: "No camera found. Connect a camera and try again."])
        }
        let cameraInput = try AVCaptureDeviceInput(device: device)
        let videoOutput = AVCaptureVideoDataOutput()
        videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        videoOutput.alwaysDiscardsLateVideoFrames = true
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.sessionPreset = .vga640x480
        guard session.canAddInput(cameraInput), session.canAddOutput(videoOutput) else {
            throw NSError(domain: "backbone", code: 2, userInfo: [NSLocalizedDescriptionKey: "This camera does not support posture monitoring."])
        }
        session.addInput(cameraInput)
        session.addOutput(videoOutput)
        videoOutput.setSampleBufferDelegate(self, queue: queue)
        input = cameraInput
        output = videoOutput
        let center = NotificationCenter.default
        for name in [AVCaptureSession.runtimeErrorNotification, AVCaptureSession.wasInterruptedNotification] {
            observers.append(center.addObserver(forName: name, object: session, queue: nil) { [weak self] _ in
                self?.queue.async { [weak self] in
                    guard let self, self.active else { return }
                    self.active = false
                    self.onStatus?("Camera access was interrupted. Close other camera apps, then try again.", nil, self.generation)
                }
            })
        }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard active else { return }
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastSample >= interval else { return }
        lastSample = now
        guard let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let request = VNDetectFaceRectanglesRequest()
        do {
            try VNImageRequestHandler(cvPixelBuffer: buffer, orientation: .up).perform([request])
            let faces = (request.results ?? []).filter { $0.confidence > 0.5 && $0.boundingBox.height >= 0.08 }
            // Multiple people are ambiguous; don't silently calibrate against a bystander.
            let measurement: PoseMeasurement
            if faces.isEmpty { measurement = PoseMeasurement(hint: "Your face is not visible yet. Face the camera and use the preview to check your position and lighting.") }
            else if faces.count > 1 { measurement = PoseMeasurement(hint: "More than one face is visible. Calibrate with just you in the camera view.") }
            else { measurement = Self.measure(faces[0]) }
            onSample?(measurement, generation)
        } catch { onSample?(PoseMeasurement(hint: "The posture detector could not read this frame. Try better lighting or restart the camera."), generation) }
    }

    private static func measure(_ face: VNFaceObservation) -> PoseMeasurement {
        if let yaw = face.yaw, abs(yaw.doubleValue) > 0.6 {
            return PoseMeasurement(hint: "Face the camera so we can get a steady head-position reading.")
        }
        guard let ratio = SeatedPostureMetric.ratio(faceMinY: Double(face.boundingBox.minY), faceHeight: Double(face.boundingBox.height)) else {
            return PoseMeasurement(hint: "Adjust your distance so your whole face fits clearly in the preview.")
        }
        return PoseMeasurement(ratio: ratio, hint: "Your face is visible. Stay comfortably upright while we learn your head position.")
    }

    deinit { observers.forEach { NotificationCenter.default.removeObserver($0) } }
}

@MainActor
final class PostureMonitor: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    var onNudge: (() -> Void)?
    var onPreviewNudge: (() -> Void)?
    @Published private(set) var state: DetectionState = .needsCalibration
    @Published private(set) var pauseReasons: Set<String> = []
    @Published private(set) var isRunning = false
    @Published private(set) var cameraReady = false
    @Published private(set) var permissionPending = false
    @Published private(set) var poseVisible = false
    @Published private(set) var detectionHint = "Keep your head and both shoulders in view."
    @Published private(set) var cameraDenied = false
    @Published private(set) var cameraError: String?
    @Published private(set) var notificationStatus = "Not requested"
    @Published private(set) var calibrationProgress = 0.0
    @Published private(set) var days: [DailySummary] = []
    @Published private(set) var storageError: String?
    @Published private(set) var onboardingComplete = false
    @Published private(set) var isCalibrated = false
    @Published private(set) var loginEnabled = false
    @Published private(set) var loginError: String?
    @Published var settings = PostureSettings() {
        didSet {
            data.settings = settings.validated()
            camera.setInterval(state == .calibrating ? 0.5 : data.settings.sampleInterval)
            save()
        }
    }
    private let camera = CameraPipeline()
    private var engine = PostureEngine()
    private var data = LocalData()
    private let store: LocalStore
    private var generation = 0
    private var cameraID: String?
    private var wanted = false
    private var activity = InputActivity(now: ProcessInfo.processInfo.systemUptime)
    private var lastHistorySample: Date?
    private var lastFrame: Date?
    private var startedAt: Date?
    private var timer: Timer?
    private var systemObservers: [NSObjectProtocol] = []
    private var lastSaved = Date.distantPast

    static func makePreview(
        permissionPending: Bool = false,
        cameraDenied: Bool = false,
        cameraError: String? = nil,
        isRunning: Bool = false,
        cameraReady: Bool = false,
        pauseReason: String? = nil,
        state: DetectionState = .needsCalibration,
        isCalibrated: Bool = false,
        calibrationProgress: Double = 0,
        poseVisible: Bool = false
    ) -> PostureMonitor {
        let monitor = PostureMonitor()
        monitor.permissionPending = permissionPending
        monitor.cameraDenied = cameraDenied
        monitor.cameraError = cameraError
        monitor.isRunning = isRunning
        monitor.cameraReady = cameraReady
        monitor.pauseReasons = pauseReason.map { [$0] } ?? []
        monitor.state = state
        monitor.isCalibrated = isCalibrated
        monitor.calibrationProgress = calibrationProgress
        monitor.poseVisible = poseVisible
        monitor.detectionHint = poseVisible
            ? "Your face is visible. Stay comfortably upright while we learn your baseline."
            : "Keep your head and both shoulders in view."
        return monitor
    }

    override init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        store = LocalStore(url: support.appendingPathComponent("PostureBuddy/data.json"))
        super.init()
        do { data = try store.load() }
        catch {
            storageError = "Saved data could not be read. A backup is kept beside data.json."
            // Preserve the original before any later writes.
            let backup = store.url.deletingLastPathComponent().appendingPathComponent("data-unreadable-\(Int(Date().timeIntervalSince1970)).json")
            do { try FileManager.default.copyItem(at: store.url, to: backup) }
            catch { storageError = "Saved data could not be read or backed up. History saving is disabled."; writesDisabled = true }
        }
        settings = data.settings.validated()
        days = data.days
        onboardingComplete = data.onboardingComplete
        if let calibration = data.calibration, calibration.metricVersion == 2, calibration.cameraID == AVCaptureDevice.default(for: .video)?.uniqueID {
            engine = PostureEngine(baseline: calibration.baseline)
            isCalibrated = engine.baseline != nil
        } else {
            data.calibration = nil
        }
        loginEnabled = SMAppService.mainApp.status == .enabled
        camera.onSample = { [weak self] measurement, generation in
            Task { @MainActor in self?.receive(measurement, generation: generation) }
        }
        camera.onStatus = { [weak self] error, id, generation in
            Task { @MainActor in self?.cameraStatus(error: error, id: id, generation: generation) }
        }
        UNUserNotificationCenter.current().delegate = self
        refreshNotificationStatus()
        timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(timer!, forMode: .common)
        let center = NSWorkspace.shared.notificationCenter
        systemObservers.append(center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.setPaused("Mac asleep", enabled: true) }
        })
        systemObservers.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.setPaused("Mac asleep", enabled: false) }
        })
        systemObservers.append(center.addObserver(forName: NSWorkspace.sessionDidResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.setPaused("Screen locked", enabled: true) }
        })
        systemObservers.append(center.addObserver(forName: NSWorkspace.sessionDidBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.setPaused("Screen locked", enabled: false) }
        })
    }
    private var writesDisabled = false

    var today: DailySummary { days.first { $0.id == DailySummary.dayKey(Date()) } ?? DailySummary(id: DailySummary.dayKey(Date())) }
    var canCalibrate: Bool { isRunning && cameraReady && pauseReasons.isEmpty && cameraError == nil }
    var cameraPreview: some View { CameraPreview(pipeline: camera) }
    func restoreSession() {
        guard data.monitoringEnabled else { return }
        // Restoring a session never opens a new permission prompt.
        if AVCaptureDevice.authorizationStatus(for: .video) == .authorized { start() }
        else { cameraDenied = true }
    }
    var statusTitle: String {
        if permissionPending { return "Waiting for camera permission" }
        if cameraDenied { return "Camera permission needed" }
        if cameraError != nil { return "Camera unavailable" }
        if let reason = pauseReasons.sorted().first { return "Paused · \(reason)" }
        if !isRunning { return "Ready when you are" }
        if !cameraReady { return "Starting your camera" }
        switch state {
        case .needsCalibration: return "Find your upright position"
        case .calibrating: return "Learning your posture"
        case .good: return "Sitting comfortably"
        case .slouching: return "Time for a posture check"
        case .noPerson: return "Looking for you"
        case .calibrationFailed: return "Let's try calibration again"
        }
    }
    var statusDetail: String {
        if permissionPending { return "Choose Allow in the macOS camera permission dialog to continue. If it is behind another window, bring ItsMyBack to the front." }
        if cameraDenied { return "Allow ItsMyBack in System Settings → Privacy & Security → Camera, then try again." }
        if let cameraError { return cameraError }
        if pauseReasons.contains("You paused") { return "Your camera is off. Choose Resume when you’re ready." }
        if pauseReasons.contains("Away from keyboard") { return "Your camera is off after 5 minutes without input. Move your mouse, press a key, or choose I’m back." }
        if pauseReasons.contains("Camera used by another app") { return "Close the other app’s camera session. ItsMyBack will resume automatically." }
        if !pauseReasons.isEmpty { return "Your camera is off. Monitoring resumes when your Mac is active again." }
        if !isRunning { return "Start a session to check your posture on this Mac." }
        if !cameraReady { return "Opening the camera. This usually takes a few seconds." }
        switch state {
        case .needsCalibration: return "Sit comfortably upright, face the camera, then calibrate your head position."
        case .calibrating: return "Stay comfortably upright for about 10 seconds. Keep your face in view."
        case .good: return "Small, comfortable adjustments make a difference."
        case .slouching: return "Reset your position or take a short stretch."
        case .noPerson: return detectionHint
        case .calibrationFailed: return "We couldn't get a steady reading. Improve the lighting and keep still, then retry. Your previous calibration is preserved."
        }
    }
    var statusSymbol: String {
        if cameraDenied || cameraError != nil { return "camera.badge.ellipsis" }
        if !pauseReasons.isEmpty || !isRunning { return "pause.circle" }
        switch state {
        case .good: return "checkmark.circle"
        case .slouching: return "figure.seated.side"
        case .calibrating: return "scope"
        case .needsCalibration, .calibrationFailed: return "viewfinder"
        case .noPerson: return "person.crop.rectangle"
        }
    }

    func start() {
        recordInteraction()
        wanted = true
        cameraError = nil
        guard !permissionPending else { return }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            cameraDenied = false
            data.monitoringEnabled = true
            save()
            reconcile()
        case .notDetermined:
            permissionPending = true
            AVCaptureDevice.requestAccess(for: .video) { [weak self] allowed in
                Task { @MainActor in
                    guard let self else { return }
                    self.permissionPending = false
                    self.cameraDenied = !allowed
                    if allowed {
                        guard self.wanted else { return }
                        self.data.monitoringEnabled = true
                        self.save()
                        self.reconcile()
                    }
                }
            }
        default: cameraDenied = true
        }
    }

    func finishOnboarding() {
        data.onboardingComplete = true
        onboardingComplete = true
        save()
    }

    func toggleManualPause() { setPaused("You paused", enabled: !pauseReasons.contains("You paused")) }

    func recordInteraction() {
        activity.recordInteraction(now: ProcessInfo.processInfo.systemUptime)
        setPaused("Away from keyboard", enabled: false)
    }

    func resumeFromPause() {
        recordInteraction()
        setPaused("You paused", enabled: false)
    }

    func stop() {
        wanted = false
        data.monitoringEnabled = false
        pauseReasons = []
        generation += 1
        camera.stop(generation: generation)
        isRunning = false
        cameraReady = false
        poseVisible = false
        engine.cancelCalibration()
        state = engine.state
        calibrationProgress = 0
        lastHistorySample = nil
        save()
    }

    private func setPaused(_ reason: String, enabled: Bool) {
        let previous = pauseReasons
        if enabled { pauseReasons.insert(reason) } else { pauseReasons.remove(reason) }
        if previous != pauseReasons { reconcile() }
    }

    private func reconcile() {
        guard wanted, !cameraDenied, AVCaptureDevice.authorizationStatus(for: .video) == .authorized else { return }
        generation += 1
        cameraReady = false
        poseVisible = false
        engine.cancelCalibration()
        state = engine.state
        calibrationProgress = 0
        lastHistorySample = nil
        if !pauseReasons.isEmpty {
            camera.stop(generation: generation)
            isRunning = false
        } else {
            lastFrame = nil
            startedAt = Date()
            isRunning = true
            camera.start(generation: generation, interval: settings.validated().sampleInterval)
        }
    }

    func beginCalibration() {
        recordInteraction()
        guard canCalibrate else { return }
        engine.beginCalibration(now: Date())
        state = .calibrating
        calibrationProgress = 0
        lastHistorySample = nil
        camera.setInterval(0.5)
    }

    func cancelCalibration() {
        engine.cancelCalibration()
        state = engine.state
        calibrationProgress = 0
        camera.setInterval(settings.validated().sampleInterval)
    }

    private func cameraStatus(error: String?, id: String?, generation: Int) {
        guard self.generation == generation, wanted, pauseReasons.isEmpty else { return }
        if let error {
            cameraError = error
            self.generation += 1
            camera.stop(generation: self.generation)
            isRunning = false
            cameraReady = false
            engine.cancelCalibration()
            state = engine.state
            lastHistorySample = nil
            return
        }
        cameraID = id
        cameraError = nil
        cameraReady = true
        if let saved = data.calibration, saved.cameraID != id {
            data.calibration = nil
            engine = PostureEngine()
            isCalibrated = false
            state = .needsCalibration
            save()
        }
    }

    private func receive(_ measurement: PoseMeasurement, generation: Int) {
        guard generation == self.generation, isRunning, pauseReasons.isEmpty else { return }
        let now = Date()
        lastFrame = now
        poseVisible = measurement.ratio != nil
        detectionHint = measurement.hint
        let wasCalibrating = state == .calibrating
        let result = engine.sample(measurement.ratio, now: now, settings: settings)
        state = result.state
        calibrationProgress = Double(engine.calibrationSamples.count) / Double(engine.calibrationTarget)
        if let baseline = result.calibratedBaseline, let cameraID {
            data.calibration = Calibration(baseline: baseline, cameraID: cameraID, date: now)
            isCalibrated = true
            save()
        }
        if wasCalibrating && state != .calibrating { camera.setInterval(settings.validated().sampleInterval) }
        if state == .good || state == .slouching, !wasCalibrating {
            let duration = lastHistorySample.map { min(settings.validated().sampleInterval * 1.5, now.timeIntervalSince($0)) } ?? 0
            data.record(state: state, seconds: duration, nudge: result.shouldNudge, date: now)
            days = data.days
            lastHistorySample = now
        } else { lastHistorySample = nil }
        if result.shouldNudge { sendNudge() }
        if now.timeIntervalSince(lastSaved) >= 15 { save() }
    }

    private func tick() {
        guard wanted else { return }
        // Setup, permission prompts and calibration must never be interrupted by idle pausing.
        let allowIdlePause = settings.idlePauseEnabled && onboardingComplete && isCalibrated && state != .calibrating && !permissionPending
        setPaused("Away from keyboard", enabled: activity.shouldPause(systemIdle: InputActivity.systemIdleSeconds(), now: ProcessInfo.processInfo.systemUptime, enabled: allowIdlePause))
        setPaused("Camera used by another app", enabled: AVCaptureDevice.default(for: .video)?.isInUseByAnotherApplication == true)
        if isRunning && engine.expireCalibration(now: Date()) {
            state = .calibrationFailed
            calibrationProgress = 0
            camera.setInterval(settings.validated().sampleInterval)
        }
        if isRunning, let reference = lastFrame ?? startedAt,
           Date().timeIntervalSince(reference) > max(15, settings.validated().sampleInterval * 3) {
            cameraStatus(error: "The camera stopped sending frames. Reconnect it and try again.", id: nil, generation: generation)
        }
    }

    func requestNotifications() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { [weak self] _, _ in
            Task { @MainActor in self?.refreshNotificationStatus() }
        }
    }
    func refreshNotificationStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { [weak self] value in
            let status: String
            switch value.authorizationStatus {
            case .authorized, .provisional, .ephemeral: status = "Allowed"
            case .denied: status = "Disabled in System Settings"
            default: status = "Not requested"
            }
            Task { @MainActor in self?.notificationStatus = status }
        }
    }
    private func sendNudge() {
        if settings.notchAlertsEnabled { onNudge?() }
        if settings.soundEnabled { NSSound(named: "Pop")?.play() }
        guard settings.systemNotificationsEnabled else { return }
        let content = UNMutableNotificationContent()
        content.title = "A little posture reset"
        content.body = "Sit comfortably upright or take a moment to stretch."
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "posture-reminder", content: content, trigger: nil))
    }
    func previewNotchAlert() { onPreviewNudge?() }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
    func setLoginEnabled(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginEnabled = SMAppService.mainApp.status == .enabled
            loginError = SMAppService.mainApp.status == .requiresApproval ? "Allow ItsMyBack under System Settings → General → Login Items." : nil
        } catch { loginError = error.localizedDescription }
    }
    func clearHistory() { data.days = []; days = []; lastHistorySample = nil; save() }
    func openCameraSettings() { openSettings("Privacy_Camera") }
    func openNotificationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") { NSWorkspace.shared.open(url) }
    }
    private func openSettings(_ pane: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") { NSWorkspace.shared.open(url) }
    }
    private func save() {
        guard !writesDisabled else { return }
        do { try store.save(data); lastSaved = Date() }
        catch { storageError = "Could not save settings or history: \(error.localizedDescription)" }
    }
    func shutdown() {
        timer?.invalidate()
        systemObservers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        systemObservers = []
        generation += 1
        camera.stop(generation: generation)
        save()
    }
}

/// Preview is shown only during setup/calibration, never saved or uploaded.
private struct CameraPreview: NSViewRepresentable {
    let pipeline: CameraPipeline
    func makeNSView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.wantsLayer = true
        view.preview = pipeline.makePreviewLayer()
        view.preview?.videoGravity = .resizeAspectFill
        view.layer = view.preview
        return view
    }
    func updateNSView(_ view: PreviewView, context: Context) {}
    static func dismantleNSView(_ view: PreviewView, coordinator: ()) { view.preview?.session = nil }
    final class PreviewView: NSView {
        var preview: AVCaptureVideoPreviewLayer?
        override func layout() { super.layout(); preview?.frame = bounds }
    }
}
