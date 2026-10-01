import XCTest
import CoreGraphics
@testable import PostureCore

final class PostureCoreTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let settings: PostureSettings = { var value = PostureSettings(); value.consecutiveBadSamplesThreshold = 4; return value }()

    func testExplicitCalibrationAndMedian() {
        var engine = PostureEngine()
        XCTAssertEqual(engine.sample(0.5, now: now, settings: settings).state, .needsCalibration)
        XCTAssertNil(engine.baseline)
        engine.beginCalibration(now: now)
        for i in 0..<19 { _ = engine.sample(i == 0 ? 1.5 : 0.5, now: now.addingTimeInterval(Double(i) / 2), settings: settings) }
        let result = engine.sample(0.5, now: now.addingTimeInterval(10), settings: settings)
        XCTAssertEqual(result.calibratedBaseline, 0.5)
        XCTAssertEqual(result.state, .good)
    }

    func testCalibrationTimeoutPreservesBaseline() {
        var engine = PostureEngine(baseline: 0.6)
        engine.beginCalibration(now: now)
        _ = engine.sample(0.5, now: now, settings: settings)
        XCTAssertTrue(engine.expireCalibration(now: now.addingTimeInterval(46)))
        XCTAssertEqual(engine.state, .calibrationFailed)
        XCTAssertEqual(engine.baseline, 0.6)
        XCTAssertEqual(engine.sample(nil, now: now.addingTimeInterval(47), settings: settings).state, .calibrationFailed)
    }

    func testUnstableCalibrationRejected() {
        var engine = PostureEngine(baseline: 0.5)
        engine.beginCalibration(now: now)
        for i in 0..<20 { _ = engine.sample(i % 2 == 0 ? 0.3 : 0.8, now: now.addingTimeInterval(Double(i) / 2), settings: settings) }
        XCTAssertEqual(engine.state, .calibrationFailed)
        XCTAssertEqual(engine.baseline, 0.5)
    }

    func testSlouchThresholdAndSustainedCooldown() {
        var engine = PostureEngine(baseline: 0.5)
        for i in 0..<3 {
            let result = engine.sample(0.3, now: now.addingTimeInterval(Double(i)), settings: settings)
            XCTAssertEqual(result.state, .good)
            XCTAssertFalse(result.shouldNudge)
        }
        XCTAssertTrue(engine.sample(0.3, now: now.addingTimeInterval(3), settings: settings).shouldNudge)
        XCTAssertFalse(engine.sample(0.3, now: now.addingTimeInterval(92), settings: settings).shouldNudge)
        XCTAssertTrue(engine.sample(0.3, now: now.addingTimeInterval(93), settings: settings).shouldNudge)
        XCTAssertEqual(engine.sample(0.5, now: now.addingTimeInterval(94), settings: settings).state, .slouching)
        XCTAssertEqual(engine.sample(0.5, now: now.addingTimeInterval(95), settings: settings).state, .good)
    }

    func testMissingPersonAndPauseResetConsecutiveReadings() {
        var engine = PostureEngine(baseline: 0.5)
        for _ in 0..<3 { _ = engine.sample(0.3, now: now, settings: settings) }
        XCTAssertEqual(engine.sample(nil, now: now, settings: settings).state, .noPerson)
        XCTAssertEqual(engine.sample(0.3, now: now, settings: settings).state, .good)
        engine.resetContinuity()
        XCTAssertEqual(engine.sample(0.3, now: now, settings: settings).state, .good)
    }

    func testInvalidRatiosCannotCalibrate() {
        var engine = PostureEngine()
        engine.beginCalibration(now: now)
        for value in [Double.nan, .infinity, 0, -1, 4] { _ = engine.sample(value, now: now, settings: settings) }
        XCTAssertTrue(engine.calibrationSamples.isEmpty)
        XCTAssertNil(engine.baseline)
    }

    func testCancelledRecalibrationKeepsBaseline() {
        var engine = PostureEngine(baseline: 0.5)
        engine.beginCalibration(now: now)
        engine.cancelCalibration()
        XCTAssertEqual(engine.baseline, 0.5)
        XCTAssertEqual(engine.sample(0.5, now: now, settings: settings).state, .good)
    }

    func testDisabledNudgesDoNotConsumeCooldown() {
        var engine = PostureEngine(baseline: 0.5)
        var muted = settings
        muted.notificationsEnabled = false
        for _ in 0..<4 { XCTAssertFalse(engine.sample(0.3, now: now, settings: muted).shouldNudge) }
        XCTAssertTrue(engine.sample(0.3, now: now, settings: settings).shouldNudge)
    }

    func testSettingsValidation() {
        var value = settings
        value.sampleInterval = .nan
        value.slouchTolerance = -10
        value.nudgeCooldown = .infinity
        value.consecutiveBadSamplesThreshold = 100
        let validated = value.validated()
        XCTAssertEqual(validated.sampleInterval, 0.5)
        XCTAssertEqual(validated.slouchTolerance, 0.1)
        XCTAssertEqual(validated.nudgeCooldown, 90)
        XCTAssertEqual(validated.consecutiveBadSamplesThreshold, 10)
    }

    func testHistoryExcludesUntrackedStatesAndBoundsDurations() {
        var data = LocalData()
        data.record(state: .noPerson, seconds: 1000, nudge: false, date: now)
        XCTAssertTrue(data.days.isEmpty)
        data.record(state: .good, seconds: 1000, nudge: false, date: now)
        data.record(state: .slouching, seconds: 10, nudge: true, date: now)
        XCTAssertEqual(data.days[0].trackedSeconds, 20)
        XCTAssertEqual(data.days[0].uprightPercent, 50)
        XCTAssertEqual(data.days[0].nudges, 1)
    }

    func testRetentionAndDayRollover() {
        var data = LocalData()
        for i in 0..<100 { data.record(state: .good, seconds: 2, nudge: false, date: now.addingTimeInterval(Double(i) * 86400)) }
        XCTAssertEqual(data.days.count, 90)
        XCTAssertEqual(Set(data.days.map(\.id)).count, 90)
    }

    func testAtomicPersistenceAndCorruptData() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = LocalStore(url: directory.appendingPathComponent("data.json"))
        XCTAssertFalse(try store.load().onboardingComplete)
        var data = LocalData()
        data.onboardingComplete = true
        data.calibration = Calibration(baseline: 0.5, cameraID: "camera", date: now)
        data.record(state: .good, seconds: 5, nudge: false, date: now)
        try store.save(data)
        let loaded = try store.load()
        XCTAssertTrue(loaded.onboardingComplete)
        XCTAssertEqual(loaded.calibration?.cameraID, "camera")
        XCTAssertEqual(loaded.days, data.days)
        try Data("corrupt".utf8).write(to: store.url)
        XCTAssertThrowsError(try store.load())
    }

    func testOlderDataDoesNotEnableCameraAutomatically() throws {
        let json = Data("{\"onboardingComplete\":true,\"days\":[]}".utf8)
        let data = try JSONDecoder().decode(LocalData.self, from: json)
        XCTAssertTrue(data.onboardingComplete)
        XCTAssertFalse(data.monitoringEnabled)
    }

    func testIdleQueryUsesAnyInputInsteadOfNullEvents() {
        XCTAssertEqual(InputActivity.anyInputEventType.rawValue, UInt32.max)
        XCTAssertNotEqual(InputActivity.anyInputEventType, .null)
    }

    func testIdlePauseRespectsRecentAppInteractionAndSystemInput() {
        var activity = InputActivity(now: 1000)
        XCTAssertFalse(activity.shouldPause(systemIdle: 100000, now: 1001, enabled: true))
        XCTAssertFalse(activity.shouldPause(systemIdle: 1, now: 1400, enabled: true))
        XCTAssertTrue(activity.shouldPause(systemIdle: 400, now: 1400, enabled: true))
        activity.recordInteraction(now: 1400)
        XCTAssertFalse(activity.shouldPause(systemIdle: 400, now: 1401, enabled: true))
        XCTAssertFalse(activity.shouldPause(systemIdle: .infinity, now: 1800, enabled: true))
        XCTAssertFalse(activity.shouldPause(systemIdle: 400, now: 1800, enabled: false))
    }

    func testSeatedMetricRespondsToHeadDescentAndForwardMovement() throws {
        let upright = try XCTUnwrap(SeatedPostureMetric.ratio(faceMinY: 0.5, faceHeight: 0.25))
        let lowered = try XCTUnwrap(SeatedPostureMetric.ratio(faceMinY: 0.4, faceHeight: 0.25))
        let forward = try XCTUnwrap(SeatedPostureMetric.ratio(faceMinY: 0.5, faceHeight: 0.35))
        XCTAssertLessThan(lowered, upright)
        XCTAssertLessThan(forward, upright)
        XCTAssertNil(SeatedPostureMetric.ratio(faceMinY: .nan, faceHeight: 0.25))
        XCTAssertNil(SeatedPostureMetric.ratio(faceMinY: 0.5, faceHeight: 0.02))
        XCTAssertNil(SeatedPostureMetric.ratio(faceMinY: 0.8, faceHeight: 0.3))
    }

    func testOldBodyCalibrationIsMarkedForRecalibration() throws {
        let json = Data("{\"baseline\":0.5,\"cameraID\":\"camera\",\"date\":0}".utf8)
        let old = try JSONDecoder().decode(Calibration.self, from: json)
        XCTAssertEqual(old.metricVersion, 1)
        XCTAssertEqual(Calibration(baseline: 0.5, cameraID: "camera", date: now).metricVersion, 2)
    }

    func testNotchReminderWorksWithoutSystemNotifications() {
        var engine = PostureEngine(baseline: 0.5)
        var settings = PostureSettings()
        settings.systemNotificationsEnabled = false
        settings.notchAlertsEnabled = true
        for _ in 0..<1 { XCTAssertFalse(engine.sample(0.3, now: now, settings: settings).shouldNudge) }
        XCTAssertTrue(engine.sample(0.3, now: now, settings: settings).shouldNudge)
    }

    func testNoReminderOrCooldownWhenAllChannelsAreDisabled() {
        var engine = PostureEngine(baseline: 0.5)
        var settings = PostureSettings()
        settings.notchAlertsEnabled = false
        settings.systemNotificationsEnabled = false
        for _ in 0..<5 { XCTAssertFalse(engine.sample(0.3, now: now, settings: settings).shouldNudge) }
        settings.notchAlertsEnabled = true
        XCTAssertTrue(engine.sample(0.3, now: now, settings: settings).shouldNudge)
    }

    func testOldPreferencesPreserveDetectionAndEnableNotchChannel() throws {
        var settings = PostureSettings()
        settings.slouchTolerance = 0.27
        settings.notificationsEnabled = false
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(settings)) as? [String: Any])
        json.removeValue(forKey: "notchAlertsEnabled")
        json.removeValue(forKey: "systemNotificationsEnabled")
        let migrated = try JSONDecoder().decode(PostureSettings.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(migrated.slouchTolerance, 0.27)
        XCTAssertFalse(migrated.notificationsEnabled)
        XCTAssertTrue(migrated.notchAlertsEnabled)
        XCTAssertFalse(migrated.systemNotificationsEnabled)
    }
    func testQuickConfirmationIgnoresSingleBadReading() {
        var engine = PostureEngine(baseline: 0.5)
        let quick = PostureSettings()
        XCTAssertEqual(quick.sampleInterval, 0.5)
        XCTAssertFalse(engine.sample(0.3, now: now, settings: quick).shouldNudge)
        XCTAssertFalse(engine.sample(0.5, now: now.addingTimeInterval(0.5), settings: quick).shouldNudge)
        XCTAssertFalse(engine.sample(0.3, now: now.addingTimeInterval(1), settings: quick).shouldNudge)
        XCTAssertTrue(engine.sample(0.3, now: now.addingTimeInterval(1.5), settings: quick).shouldNudge)
    }

    func testShortReminderIntervalsHaveExactBoundaries() {
        for interval in [5.0, 10.0, 30.0] {
            var engine = PostureEngine(baseline: 0.5)
            var quick = PostureSettings()
            quick.nudgeCooldown = interval
            XCTAssertEqual(quick.validated().nudgeCooldown, interval)
            _ = engine.sample(0.3, now: now.addingTimeInterval(-0.5), settings: quick)
            XCTAssertTrue(engine.sample(0.3, now: now, settings: quick).shouldNudge)
            XCTAssertFalse(engine.sample(0.3, now: now.addingTimeInterval(interval - 0.01), settings: quick).shouldNudge)
            XCTAssertTrue(engine.sample(0.3, now: now.addingTimeInterval(interval), settings: quick).shouldNudge)
        }
    }

    func testRecoveryRequiresConsistentClearlyUprightReadings() {
        var engine = PostureEngine(baseline: 0.5)
        let quick = PostureSettings()
        _ = engine.sample(0.3, now: now, settings: quick)
        _ = engine.sample(0.3, now: now, settings: quick)
        XCTAssertEqual(engine.sample(0.5, now: now, settings: quick).state, .slouching)
        XCTAssertEqual(engine.sample(0.42, now: now, settings: quick).state, .slouching)
        XCTAssertEqual(engine.sample(0.5, now: now, settings: quick).state, .slouching)
        XCTAssertEqual(engine.sample(0.5, now: now, settings: quick).state, .good)
    }

    func testLegacyResponseDefaultsUpgradeButCustomTuningSurvives() throws {
        let defaults = try JSONDecoder().decode(PostureSettings.self, from: Data("{\"sampleInterval\":2.5,\"consecutiveBadSamplesThreshold\":4,\"nudgeCooldown\":30}".utf8))
        XCTAssertEqual(defaults.sampleInterval, 0.5)
        XCTAssertEqual(defaults.consecutiveBadSamplesThreshold, 2)
        XCTAssertEqual(defaults.nudgeCooldown, 30)
        let custom = try JSONDecoder().decode(PostureSettings.self, from: Data("{\"sampleInterval\":5,\"consecutiveBadSamplesThreshold\":3}".utf8))
        XCTAssertEqual(custom.sampleInterval, 5)
        XCTAssertEqual(custom.consecutiveBadSamplesThreshold, 3)
        let roundTrip = try JSONDecoder().decode(PostureSettings.self, from: JSONEncoder().encode(custom))
        XCTAssertEqual(roundTrip, custom)
    }

}
