import Foundation

enum TrimUnit: String, CaseIterable, Codable {
    case days = "Days"
    case weeks = "Weeks"
    case months = "Months"

    var maxValue: Int {
        switch self {
        case .days: 90
        case .weeks: 52
        case .months: 24
        }
    }

    func displayName(count: Int) -> String {
        let base: String
        switch self {
        case .days: base = "day"
        case .weeks: base = "week"
        case .months: base = "month"
        }
        return count == 1 ? base : "\(base)s"
    }

    func cutoffDate(byAdding value: Int, to date: Date = Date()) -> Date {
        let calendar = Calendar.current
        switch self {
        case .days:
            return calendar.date(byAdding: .day, value: -value, to: date) ?? date
        case .weeks:
            return calendar.date(byAdding: .day, value: -value * 7, to: date) ?? date
        case .months:
            return calendar.date(byAdding: .month, value: -value, to: date) ?? date
        }
    }
}

@MainActor
@Observable
final class SettingsStore {
    static let shared = SettingsStore()

    var showWindowOnLaunch: Bool = false {
        didSet { UserDefaults.standard.set(showWindowOnLaunch, forKey: "showWindowOnLaunch") }
    }
    var trimThresholdValue: Int = 30 {
        didSet { UserDefaults.standard.set(trimThresholdValue, forKey: "trimThresholdValue") }
    }
    var trimThresholdUnit: TrimUnit = .days {
        didSet { UserDefaults.standard.set(trimThresholdUnit.rawValue, forKey: "trimThresholdUnit") }
    }
    var lastTrimDate: Date? {
        didSet {
            if let date = lastTrimDate {
                UserDefaults.standard.set(date, forKey: "lastTrimDate")
            } else {
                UserDefaults.standard.removeObject(forKey: "lastTrimDate")
            }
        }
    }
    var lastTrimSummary: String = "" {
        didSet { UserDefaults.standard.set(lastTrimSummary, forKey: "lastTrimSummary") }
    }
    var trimNotifyOnComplete: Bool = false {
        didSet { UserDefaults.standard.set(trimNotifyOnComplete, forKey: "trimNotifyOnComplete") }
    }
    var autoTrimEnabled: Bool = false {
        didSet { UserDefaults.standard.set(autoTrimEnabled, forKey: "autoTrimEnabled") }
    }
    var autoTrimThresholdValue: Int = 90 {
        didSet { UserDefaults.standard.set(autoTrimThresholdValue, forKey: "autoTrimThresholdValue") }
    }
    var autoTrimThresholdUnit: TrimUnit = .days {
        didSet { UserDefaults.standard.set(autoTrimThresholdUnit.rawValue, forKey: "autoTrimThresholdUnit") }
    }
    var autoTrimLastRun: Date? {
        didSet {
            if let date = autoTrimLastRun {
                UserDefaults.standard.set(date, forKey: "autoTrimLastRun")
            } else {
                UserDefaults.standard.removeObject(forKey: "autoTrimLastRun")
            }
        }
    }
    var autoTrimResult: String = "" {
        didSet { UserDefaults.standard.set(autoTrimResult, forKey: "autoTrimResult") }
    }

    private init() {
        let defaults = UserDefaults.standard
        showWindowOnLaunch = defaults.bool(forKey: "showWindowOnLaunch")

        if let raw = defaults.string(forKey: "trimThresholdUnit"), let unit = TrimUnit(rawValue: raw) {
            trimThresholdUnit = unit
        } else {
            trimThresholdUnit = .days
        }
        trimThresholdValue = defaults.object(forKey: "trimThresholdValue") as? Int ?? 30

        lastTrimDate = defaults.object(forKey: "lastTrimDate") as? Date
        lastTrimSummary = defaults.string(forKey: "lastTrimSummary") ?? ""
        trimNotifyOnComplete = defaults.bool(forKey: "trimNotifyOnComplete")
        autoTrimEnabled = defaults.bool(forKey: "autoTrimEnabled")

        if let raw = defaults.string(forKey: "autoTrimThresholdUnit"), let unit = TrimUnit(rawValue: raw) {
            autoTrimThresholdUnit = unit
        } else {
            autoTrimThresholdUnit = .days
        }
        autoTrimThresholdValue = defaults.object(forKey: "autoTrimThresholdValue") as? Int ?? 90

        autoTrimLastRun = defaults.object(forKey: "autoTrimLastRun") as? Date
        autoTrimResult = defaults.string(forKey: "autoTrimResult") ?? ""

        defaults.removeObject(forKey: "ageThresholdMonths")
        defaults.removeObject(forKey: "autoTrimAgeMonths")
    }

    func recordTrim(date: Date, count: Int, space: String) {
        lastTrimDate = date
        lastTrimSummary = "\(count) snapshots, \(space)"
    }

    func clearTrimHistory() {
        lastTrimDate = nil
        lastTrimSummary = ""
    }
}
