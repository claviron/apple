import Observation
import SwiftUI

/// One window's location, including the selected section's detail stack.
struct NavigationLocation: Equatable {
    var destination: AppDestination
    var details: [AnyHashable] = []
}

@MainActor
@Observable
final class NavigationHistory {
    private(set) var current = NavigationLocation(destination: .overview)
    private var previous: [NavigationLocation] = []
    private var following: [NavigationLocation] = []
    private var groupLocations: [NavigationGroup: NavigationLocation] = [:]
    private var pageLocations: [AppDestination: NavigationLocation] = [:]
    private(set) var visitedDestinations: [AppDestination] = [.overview]

    var canGoBack: Bool { !previous.isEmpty }
    var canGoForward: Bool { !following.isEmpty }

    /// Dormant stacks keep their own path while another page is active.
    func location(for destination: AppDestination) -> NavigationLocation {
        destination == current.destination
            ? current
            : pageLocations[destination] ?? NavigationLocation(destination: destination)
    }

    /// A group's rail entry resumes its last page and detail stack. Explicit
    /// submenu selections still visit the selected page directly.
    func activate(_ group: NavigationGroup, userManagementAvailable: Bool = false) {
        let location = groupLocations[group]
        if let location,
           group.destinations(userManagementAvailable: userManagementAvailable).contains(location.destination) {
            visit(location)
        } else {
            visit(NavigationLocation(destination: group.landing(userManagementAvailable: userManagementAvailable)))
        }
    }

    func visit(_ location: NavigationLocation) {
        guard location != current else { return }
        previous.append(current)
        move(to: location)
        following.removeAll()
    }

    func back() {
        guard let location = previous.popLast() else { return }
        following.append(current)
        move(to: location)
    }

    func forward() {
        guard let location = following.popLast() else { return }
        previous.append(current)
        move(to: location)
    }

    private func move(to location: NavigationLocation) {
        groupLocations[current.destination.group] = current
        pageLocations[current.destination] = current
        current = location
        groupLocations[location.destination.group] = location
        pageLocations[location.destination] = location
        if !visitedDestinations.contains(location.destination) {
            visitedDestinations.append(location.destination)
        }
    }

    /// Retain selected pages, but never replay resource identities from any
    /// remembered group against a different server.
    func reset() {
        current = NavigationLocation(destination: current.destination)
        groupLocations = groupLocations.mapValues { NavigationLocation(destination: $0.destination) }
        groupLocations[current.destination.group] = current
        pageLocations.removeAll()
        pageLocations[current.destination] = current
        visitedDestinations = [current.destination]
        previous.removeAll()
        following.removeAll()
    }
}

extension EnvironmentValues {
    @Entry var navigationHistory: NavigationHistory? = nil
}

/// macOS detail stacks participate in the window's history. Standalone views
/// and iOS retain their ordinary, locally owned NavigationStack path.
@propertyWrapper
struct NavigationDetailPath<Element: Hashable>: DynamicProperty {
    @Environment(\.navigationHistory) private var history
    @State private var local: [Element]
    private let destination: AppDestination

    init(wrappedValue: [Element] = [], _ destination: AppDestination) {
        self.destination = destination
        _local = State(initialValue: wrappedValue)
    }

    var wrappedValue: [Element] {
        get {
            if let history {
                return history.location(for: destination).details.compactMap { $0.base as? Element }
            }
            return local
        }
        nonmutating set {
            if let history {
                // Ignore a departing stack's callbacks after a section change.
                guard history.current.destination == destination else { return }
                history.visit(NavigationLocation(destination: destination, details: newValue.map(AnyHashable.init)))
            } else {
                local = newValue
            }
        }
    }

    var projectedValue: Binding<[Element]> {
        Binding(get: { wrappedValue }, set: { wrappedValue = $0 })
    }
}

extension View {
    func managementDestination<Value: Hashable, Detail: View>(
        for type: Value.Type,
        @ViewBuilder destination: @escaping (Value) -> Detail
    ) -> some View {
        modifier(ManagementDestination(type: type, destination: destination))
    }
}

private struct ManagementDestination<Value: Hashable, Detail: View>: ViewModifier {
    let type: Value.Type
    @ViewBuilder let destination: (Value) -> Detail
    @Environment(\.workspaceNavigationDepth) private var depth

    func body(content: Content) -> some View {
        content.navigationDestination(for: type) { value in
            destination(value)
                .modifier(ManagementBackButton())
                .environment(\.workspaceNavigationDepth, depth + 1)
        }
    }
}

private struct ManagementBackButton: ViewModifier {
    @Environment(\.navigationHistory) private var history

    func body(content: Content) -> some View {
        content.navigationBarBackButtonHidden(history != nil)
    }
}
