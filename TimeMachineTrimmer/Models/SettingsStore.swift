import Foundation

@MainActor
@Observable
final class SettingsStore {
    static let shared = SettingsStore()

    var showWindowOnLaunch: Bool {
        get { _showWindowOnLaunch }
        set { _showWindowOnLaunch = newValue; UserDefaults.standard.set(newValue, forKey: "showWindowOnLaunch") }
    }
    var ageThresholdMonths: Int {
        get { _ageThresholdMonths }
        set { _ageThresholdMonths = newValue; UserDefaults.standard.set(newValue, forKey: "ageThresholdMonths") }
    }
    var lastTrimDate: Date? {
        get { _lastTrimDate }
        set {
            _lastTrimDate = newValue
            if let date = newValue {
                UserDefaults.standard.set(date, forKey: "lastTrimDate")
            } else {
                UserDefaults.standard.removeObject(forKey: "lastTrimDate")
            }
        }
    }
    var lastTrimSummary: String {
        get { _lastTrimSummary }
        set { _lastTrimSummary = newValue; UserDefaults.standard.set(newValue, forKey: "lastTrimSummary") }
    }
    var trimNotifyOnComplete: Bool {
        get { _trimNotifyOnComplete }
        set { _trimNotifyOnComplete = newValue; UserDefaults.standard.set(newValue, forKey: "trimNotifyOnComplete") }
    }

    @ObservationIgnored private var _showWindowOnLaunch: Bool
    @ObservationIgnored private var _ageThresholdMonths: Int
    @ObservationIgnored private var _lastTrimDate: Date?
    @ObservationIgnored private var _lastTrimSummary: String
    @ObservationIgnored private var _trimNotifyOnComplete: Bool

    private init() {
        let defaults = UserDefaults.standard
        _showWindowOnLaunch = defaults.bool(forKey: "showWindowOnLaunch")
        _ageThresholdMonths = defaults.object(forKey: "ageThresholdMonths") as? Int ?? 6
        _lastTrimDate = defaults.object(forKey: "lastTrimDate") as? Date
        _lastTrimSummary = defaults.string(forKey: "lastTrimSummary") ?? ""
        _trimNotifyOnComplete = defaults.bool(forKey: "trimNotifyOnComplete")
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
