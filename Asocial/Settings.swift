import Foundation

/// Which filters are on. All of them start on; Settings switches them off one by one.
@MainActor
final class FilterSettings: ObservableObject {
    static let shared = FilterSettings()

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func isOn(_ filter: Filter) -> Bool {
        defaults.object(forKey: key(filter)) as? Bool ?? true
    }

    func set(_ filter: Filter, on: Bool) {
        objectWillChange.send()
        defaults.set(on, forKey: key(filter))
        NotificationCenter.default.post(name: .asocialFiltersChanged, object: nil)
    }

    func enabled(for platform: Platform) -> [Filter] {
        platform.filters.filter(isOn)
    }

    private func key(_ filter: Filter) -> String { "filter." + filter.id }
}

/// Counts what Asocial kept out of the way today.
@MainActor
final class Stats: ObservableObject {
    static let shared = Stats()

    @Published private(set) var today: Int

    private let defaults: UserDefaults
    private let calendar = Calendar.current

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        today = 0
        today = currentCount()
    }

    func record(_ count: Int = 1) {
        let day = dayKey()
        let value = (defaults.string(forKey: "stats.day") == day ? defaults.integer(forKey: "stats.count") : 0) + count
        defaults.set(day, forKey: "stats.day")
        defaults.set(value, forKey: "stats.count")
        today = value
    }

    func refresh() { today = currentCount() }

    private func currentCount() -> Int {
        defaults.string(forKey: "stats.day") == dayKey() ? defaults.integer(forKey: "stats.count") : 0
    }

    private func dayKey() -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: Date())
        return "\(parts.year ?? 0)-\(parts.month ?? 0)-\(parts.day ?? 0)"
    }
}

extension Notification.Name {
    static let asocialFiltersChanged = Notification.Name("asocialFiltersChanged")
}
