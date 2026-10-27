import CoreGraphics

/// Visibility of the workspace navigation beside the permanent macOS icon rail.
nonisolated enum SidebarDensity: String, CaseIterable, Sendable {
    case expanded
    case compact

    static let storageKey = "sidebarDensity"

    static let railWidth: CGFloat = 52
    /// Operator-selected drawer transition: 150 milliseconds.
    static let drawerDuration: Double = 0.15

    var workspaceWidth: CGFloat {
        switch self {
        case .expanded: 220
        case .compact: 0
        }
    }

    var toggled: Self {
        switch self {
        case .expanded: .compact
        case .compact: .expanded
        }
    }

    /// What the toggle does from this density.
    var toggleTitle: String {
        switch self {
        case .expanded: "Hide Sidebar"
        case .compact: "Show Sidebar"
        }
    }

    static func resolve(_ storedValue: String) -> Self {
        Self(rawValue: storedValue) ?? .expanded
    }
}
