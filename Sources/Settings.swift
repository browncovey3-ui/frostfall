import Foundation

/// User preferences, cached in memory and persisted to UserDefaults.
final class Settings {
    static let shared = Settings()
    static let changed = Notification.Name("FrostfallSettingsChanged")

    enum Key: String {
        case intensity, opacity
        case settleOnGround, settleOnWindows, melt
        case behindWindows, overFullScreen, showInScreenshots, paused
    }

    private let defaults = UserDefaults.standard
    private var doubles: [Key: Double] = [:]
    private var bools: [Key: Bool] = [:]

    private init() {
        defaults.register(defaults: [
            Key.intensity.rawValue: 0.4,
            Key.opacity.rawValue: 0.9,
            Key.settleOnGround.rawValue: true,
            Key.settleOnWindows.rawValue: true,
            Key.melt.rawValue: false,
            Key.behindWindows.rawValue: false,
            Key.overFullScreen.rawValue: true,
            Key.showInScreenshots.rawValue: false,
            Key.paused.rawValue: false,
        ])
        for k in [Key.intensity, .opacity] {
            doubles[k] = defaults.double(forKey: k.rawValue)
        }
        for k in [Key.settleOnGround, .settleOnWindows, .melt, .behindWindows,
                  .overFullScreen, .showInScreenshots, .paused] {
            bools[k] = defaults.bool(forKey: k.rawValue)
        }
    }

    func double(_ key: Key) -> Double { doubles[key] ?? 0 }
    func bool(_ key: Key) -> Bool { bools[key] ?? false }

    func set(_ value: Double, for key: Key) {
        doubles[key] = value
        defaults.set(value, forKey: key.rawValue)
        NotificationCenter.default.post(name: Settings.changed, object: nil)
    }

    func set(_ value: Bool, for key: Key) {
        bools[key] = value
        defaults.set(value, forKey: key.rawValue)
        NotificationCenter.default.post(name: Settings.changed, object: nil)
    }

    var intensity: CGFloat { CGFloat(double(.intensity)) }
    var opacity: CGFloat { CGFloat(double(.opacity)) }
    var settleOnGround: Bool { bool(.settleOnGround) }
    var settleOnWindows: Bool { bool(.settleOnWindows) }
    var melt: Bool { bool(.melt) }
    var behindWindows: Bool { bool(.behindWindows) }
    var overFullScreen: Bool { bool(.overFullScreen) }
    var showInScreenshots: Bool { bool(.showInScreenshots) }
    var paused: Bool { bool(.paused) }
}
