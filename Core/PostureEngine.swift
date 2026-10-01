import Foundation

/// A seated framing can exclude the lower body required by a body-pose model.
/// Track chin height normalized by face height so lowering the head or moving
/// toward the camera reduces the score. Camera/seating changes need recalibration.
public enum SeatedPostureMetric {
    public static func ratio(faceMinY: Double, faceHeight: Double) -> Double? {
        guard faceMinY.isFinite, faceHeight.isFinite,
              faceHeight >= 0.08, faceHeight <= 0.85,
              faceMinY > 0.01, faceMinY + faceHeight <= 1.01 else { return nil }
        let value = 0.2 * faceMinY / faceHeight
        return value > 0.02 && value < 3 ? value : nil
    }
}

public struct PostureSettings: Codable, Equatable, Sendable {
    public var sampleInterval: Double = 0.5
    public var consecutiveBadSamplesThreshold: Int = 2
    public var slouchTolerance: Double = 0.18
    public var nudgeCooldown: Double = 90
    public var notificationsEnabled = true
    public var notchAlertsEnabled = true
    public var systemNotificationsEnabled = false
    public var soundEnabled = false
    public var idlePauseEnabled = true
    public var notchAlertAppearance: NotchAlertAppearance = .system
    public init() {}

    public var detectionVersion = 2

    private enum CodingKeys: String, CodingKey {
        case detectionVersion, sampleInterval, consecutiveBadSamplesThreshold, slouchTolerance, nudgeCooldown
        case notificationsEnabled, notchAlertsEnabled, systemNotificationsEnabled, soundEnabled, idlePauseEnabled, notchAlertAppearance
    }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        sampleInterval = try values.decodeIfPresent(Double.self, forKey: .sampleInterval) ?? 0.5
        consecutiveBadSamplesThreshold = try values.decodeIfPresent(Int.self, forKey: .consecutiveBadSamplesThreshold) ?? 2
        // Upgrade only the old default response; preserve deliberate tuning.
        if !values.contains(.detectionVersion), sampleInterval == 2.5, consecutiveBadSamplesThreshold == 4 {
            sampleInterval = 0.5
            consecutiveBadSamplesThreshold = 2
        }
        detectionVersion = 2
        slouchTolerance = try values.decodeIfPresent(Double.self, forKey: .slouchTolerance) ?? 0.18
        nudgeCooldown = try values.decodeIfPresent(Double.self, forKey: .nudgeCooldown) ?? 90
        notificationsEnabled = try values.decodeIfPresent(Bool.self, forKey: .notificationsEnabled) ?? true
        notchAlertsEnabled = try values.decodeIfPresent(Bool.self, forKey: .notchAlertsEnabled) ?? true
        systemNotificationsEnabled = try values.decodeIfPresent(Bool.self, forKey: .systemNotificationsEnabled) ?? false
        soundEnabled = try values.decodeIfPresent(Bool.self, forKey: .soundEnabled) ?? false
        idlePauseEnabled = try values.decodeIfPresent(Bool.self, forKey: .idlePauseEnabled) ?? true
        let savedAppearance = try values.decodeIfPresent(String.self, forKey: .notchAlertAppearance)
        switch savedAppearance {
        case "liquidGlass": notchAlertAppearance = .liquidGlass
        case "black", "dark": notchAlertAppearance = .black
        case "white", "light": notchAlertAppearance = .white
        default: notchAlertAppearance = .system
        }
    }

    public func validated() -> Self {
        var copy = self
        copy.sampleInterval = sampleInterval.isFinite ? min(10, max(0.5, sampleInterval)) : 0.5
        copy.consecutiveBadSamplesThreshold = min(10, max(2, consecutiveBadSamplesThreshold))
        copy.slouchTolerance = slouchTolerance.isFinite ? min(0.30, max(0.10, slouchTolerance)) : 0.18
        copy.nudgeCooldown = nudgeCooldown.isFinite ? min(1800, max(5, nudgeCooldown)) : 90
        return copy
    }
}

public enum DetectionState: Equatable, Sendable {
    case needsCalibration, calibrating, good, slouching, noPerson, calibrationFailed
}

public enum NotchAlertAppearance: String, Codable, CaseIterable, Sendable {
    case liquidGlass, black, white, system

    public var title: String {
        switch self {
        case .liquidGlass: "Liquid Glass"
        case .black: "Black"
        case .white: "White"
        case .system: "System"
        }
    }
}

public struct Evaluation: Sendable {
    public var state: DetectionState
    public var shouldNudge: Bool = false
    public var calibratedBaseline: Double?
}

/// Deterministic detector. Call only from the main actor; frames never enter this type.
public struct PostureEngine: Sendable {
    public private(set) var baseline: Double?
    public private(set) var state: DetectionState = .needsCalibration
    public private(set) var calibrationSamples: [Double] = []
    public let calibrationTarget = 20
    private var calibrationStarted: Date?
    private var badSamples = 0
    private var goodSamples = 0
    private var lastNudge: Date?

    public init(baseline: Double? = nil) {
        if let baseline, baseline.isFinite, baseline > 0.02 {
            self.baseline = baseline
        }
    }

    public mutating func beginCalibration(now: Date) {
        calibrationSamples = []
        calibrationStarted = now
        badSamples = 0
        goodSamples = 0
        state = .calibrating
    }

    public mutating func cancelCalibration() {
        calibrationStarted = nil
        calibrationSamples = []
        resetContinuity()
    }

    public mutating func resetContinuity() {
        badSamples = 0
        goodSamples = 0
        state = baseline == nil ? .needsCalibration : .noPerson
    }

    public mutating func expireCalibration(now: Date) -> Bool {
        guard let started = calibrationStarted, now.timeIntervalSince(started) >= 45 else { return false }
        calibrationStarted = nil
        calibrationSamples = []
        state = .calibrationFailed
        return true
    }

    public mutating func sample(_ ratio: Double?, now: Date, settings: PostureSettings) -> Evaluation {
        if expireCalibration(now: now) { return Evaluation(state: state) }
        if state == .calibrationFailed { return Evaluation(state: state) }
        guard let ratio, ratio.isFinite, ratio > 0.02, ratio < 3 else {
            badSamples = 0
            goodSamples = 0
            state = calibrationStarted == nil ? .noPerson : .calibrating
            return Evaluation(state: state)
        }
        if calibrationStarted != nil {
            calibrationSamples.append(ratio)
            state = .calibrating
            if calibrationSamples.count >= calibrationTarget {
                let sorted = calibrationSamples.sorted()
                let median = (sorted[9] + sorted[10]) / 2
                // A moving subject is not a reliable reference posture.
                if (sorted[15] - sorted[4]) / median > 0.25 {
                    calibrationStarted = nil
                    calibrationSamples = []
                    state = .calibrationFailed
                } else {
                    baseline = median
                    calibrationStarted = nil
                    badSamples = 0
                    state = .good
                    return Evaluation(state: state, calibratedBaseline: median)
                }
            }
            return Evaluation(state: state)
        }
        guard let baseline else {
            state = .needsCalibration
            return Evaluation(state: state)
        }
        let settings = settings.validated()
        let deviation = (baseline - ratio) / baseline
        if deviation > settings.slouchTolerance {
            badSamples += 1
            goodSamples = 0
            if badSamples >= settings.consecutiveBadSamplesThreshold { state = .slouching }
            else if state != .slouching { state = .good }
        } else if state == .slouching {
            // Require two clearly upright readings before celebrating recovery.
            badSamples = 0
            goodSamples = deviation <= settings.slouchTolerance * 0.75 ? goodSamples + 1 : 0
            if goodSamples >= 2 { state = .good; goodSamples = 0 }
        } else {
            badSamples = 0
            goodSamples = 0
            state = .good
        }
        let nudge = state == .slouching && goodSamples == 0 && settings.notificationsEnabled && (settings.notchAlertsEnabled || settings.systemNotificationsEnabled) &&
            (lastNudge.map { now.timeIntervalSince($0) >= settings.nudgeCooldown } ?? true)
        if nudge { lastNudge = now }
        return Evaluation(state: state, shouldNudge: nudge)
    }
}
