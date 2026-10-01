import Foundation
import CoreGraphics

public struct InputActivity: Sendable {
    // CGEventSource.h explicitly requires kCGAnyInputEventType (UINT32_MAX).
    // .null is a specific null event and does not measure user activity.
    public static let anyInputEventType = CGEventType(rawValue: UInt32.max)!
    private var lastInteraction: Double
    public init(now: Double) { lastInteraction = now }
    public mutating func recordInteraction(now: Double) { lastInteraction = now }
    public func shouldPause(systemIdle: Double, now: Double, enabled: Bool) -> Bool {
        guard enabled, systemIdle.isFinite, systemIdle >= 0, now.isFinite else { return false }
        return min(systemIdle, max(0, now - lastInteraction)) >= 300
    }
    public static func systemIdleSeconds() -> Double {
        CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyInputEventType)
    }
}
