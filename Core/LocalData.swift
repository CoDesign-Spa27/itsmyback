import Foundation

public struct Calibration: Codable, Sendable {
    public var baseline: Double
    public var cameraID: String
    public var date: Date
    public var metricVersion = 2
    public init(baseline: Double, cameraID: String, date: Date) {
        self.baseline = baseline; self.cameraID = cameraID; self.date = date
    }
    private enum CodingKeys: String, CodingKey { case baseline, cameraID, date, metricVersion }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        baseline = try values.decode(Double.self, forKey: .baseline)
        cameraID = try values.decode(String.self, forKey: .cameraID)
        date = try values.decode(Date.self, forKey: .date)
        metricVersion = try values.decodeIfPresent(Int.self, forKey: .metricVersion) ?? 1
    }
}

public struct DailySummary: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var goodSeconds: Double = 0
    public var slouchSeconds: Double = 0
    public var nudges: Int = 0
    public var trackedSeconds: Double { goodSeconds + slouchSeconds }
    public var uprightPercent: Int? {
        trackedSeconds > 0 ? Int((goodSeconds / trackedSeconds * 100).rounded()) : nil
    }
    public init(id: String) { self.id = id }
    public static func dayKey(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year!, parts.month!, parts.day!)
    }
}

public struct LocalData: Codable, Sendable {
    public var settings = PostureSettings()
    public var calibration: Calibration?
    public var onboardingComplete = false
    public var monitoringEnabled = false
    public var days: [DailySummary] = []
    public init() {}
    private enum CodingKeys: String, CodingKey { case settings, calibration, onboardingComplete, monitoringEnabled, days }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        settings = try values.decodeIfPresent(PostureSettings.self, forKey: .settings) ?? PostureSettings()
        calibration = try values.decodeIfPresent(Calibration.self, forKey: .calibration)
        onboardingComplete = try values.decodeIfPresent(Bool.self, forKey: .onboardingComplete) ?? false
        monitoringEnabled = try values.decodeIfPresent(Bool.self, forKey: .monitoringEnabled) ?? false
        days = try values.decodeIfPresent([DailySummary].self, forKey: .days) ?? []
    }
    public mutating func record(state: DetectionState, seconds: Double, nudge: Bool, date: Date) {
        guard state == .good || state == .slouching else { return }
        let key = DailySummary.dayKey(date)
        if !days.contains(where: { $0.id == key }) { days.append(DailySummary(id: key)) }
        let index = days.firstIndex(where: { $0.id == key })!
        let duration = seconds.isFinite ? min(10, max(0, seconds)) : 0
        if state == .good { days[index].goodSeconds += duration }
        else { days[index].slouchSeconds += duration }
        if nudge { days[index].nudges += 1 }
        days = Array(days.sorted { $0.id < $1.id }.suffix(90))
    }
}

public struct LocalStore: Sendable {
    public let url: URL
    public init(url: URL) { self.url = url }
    public func load() throws -> LocalData {
        guard FileManager.default.fileExists(atPath: url.path) else { return LocalData() }
        return try JSONDecoder().decode(LocalData.self, from: Data(contentsOf: url))
    }
    public func save(_ data: LocalData) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(data).write(to: url, options: .atomic)
    }
}
