/// Device-local visibility preferences for the main macOS navigation rail.
struct NavigationPins {
    static let storageKey = "navigation.pinnedGroups"
    static var defaultValue: String {
        NavigationGroup.primaryGroups.map(\.rawValue).joined(separator: ",")
    }

    private(set) var groups: [NavigationGroup]

    init(storedValue: String) {
        let names = storedValue.split(separator: ",").map(String.init)
        groups = NavigationGroup.primaryGroups.filter { $0 == .overview || names.contains($0.rawValue) }
    }

    var storedValue: String { groups.map(\.rawValue).joined(separator: ",") }

    func contains(_ group: NavigationGroup) -> Bool { groups.contains(group) }

    mutating func toggle(_ group: NavigationGroup) {
        guard group != .overview, NavigationGroup.primaryGroups.contains(group) else { return }
        if contains(group) {
            groups.removeAll { $0 == group }
        } else {
            groups = NavigationGroup.primaryGroups.filter { groups.contains($0) || $0 == group }
        }
    }
}
