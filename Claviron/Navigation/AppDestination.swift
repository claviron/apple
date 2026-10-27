import Foundation

/// Leaf views are independent of the main groups shown in the icon rail.
enum AppDestination: String, CaseIterable, Hashable, Identifiable, Sendable {
    case overview
    case runtimeOverview
    case workers
    case services
    case applications
    case tasks
    case edgeOverview
    case hosting
    case dns
    case domains
    case certificates
    case usersOverview
    case users
    case authorizationOverview
    case roles
    case permissions
    case profile
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview, .runtimeOverview, .edgeOverview, .usersOverview, .authorizationOverview: "Overview"
        case .workers: "Workers"
        case .services: "Services"
        case .applications: "Applications"
        case .tasks: "Tasks"
        case .hosting: "Sites"
        case .dns: "DNS"
        case .domains: "Domains"
        case .certificates: "Certificates"
        case .users: "Users"
        case .roles: "Roles"
        case .permissions: "Permissions"
        case .profile: "Profile"
        case .settings: "Settings"
        }
    }

    // Leaf symbols remain available for content and a future pinned-view rail.
    var systemImage: String {
        switch self {
        case .overview: "house"
        case .runtimeOverview: NavigationGroup.runtime.systemImage
        case .workers: "cpu"
        case .services: "server.rack"
        case .applications: "app"
        case .tasks: "checklist"
        case .edgeOverview: "network"
        case .hosting: "network"
        case .dns: "point.3.connected.trianglepath.dotted"
        case .domains: "globe"
        case .certificates: "checkmark.shield"
        case .usersOverview, .users: "person.2"
        case .authorizationOverview: NavigationGroup.authorization.systemImage
        case .roles: "person.badge.key"
        case .permissions: "key"
        case .profile: "person.crop.circle"
        case .settings: "gearshape"
        }
    }

    var group: NavigationGroup {
        switch self {
        case .overview: .overview
        case .runtimeOverview, .workers, .services, .applications, .tasks: .runtime
        case .edgeOverview, .hosting, .dns, .domains, .certificates: .edge
        case .usersOverview, .users: .users
        case .authorizationOverview, .roles, .permissions: .authorization
        case .profile, .settings: .settings
        }
    }
}

/// Main navigation only. Selecting a child never changes its group's icon.
enum NavigationGroup: String, CaseIterable, Identifiable, Sendable {
    case overview
    case runtime
    case edge
    case users
    case authorization
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: "Overview"
        case .runtime: "Runtime"
        case .edge: "Edge"
        case .users: "Users"
        case .authorization: "Authorization"
        case .settings: "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .overview: "house"
        case .runtime: "server.rack"
        case .edge: "globe"
        case .users: "person.2"
        case .authorization: "key.horizontal"
        case .settings: "gearshape"
        }
    }

    var landing: AppDestination {
        switch self {
        case .overview: .overview
        case .runtime: .runtimeOverview
        case .edge: .edgeOverview
        case .users: .usersOverview
        case .authorization: .authorizationOverview
        case .settings: .profile
        }
    }

    var destinations: [AppDestination] {
        AppDestination.allCases.filter { $0.group == self }
    }

    func destinations(userManagementAvailable: Bool) -> [AppDestination] {
        destinations.filter { $0 != .profile || userManagementAvailable }
    }

    func landing(userManagementAvailable: Bool) -> AppDestination {
        self == .settings && !userManagementAvailable ? .settings : landing
    }

    /// Settings and Profile are reached from the fixed profile menu.
    static var primaryGroups: [Self] { allCases.filter { $0 != .settings } }
}
