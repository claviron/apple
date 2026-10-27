import Foundation
import Testing
@testable import Claviron

struct AppDestinationTests {
    @Test
    func workspaceCollapseKeepsPermanentRail() {
        #expect(SidebarDensity.railWidth == 52)
        #expect(SidebarDensity.expanded.workspaceWidth == 220)
        #expect(SidebarDensity.compact.workspaceWidth == 0)
        #expect(SidebarDensity.expanded.toggled == .compact)
        #expect(SidebarDensity.compact.toggled == .expanded)
        #expect(SidebarDensity.resolve("obsolete") == .expanded)
    }

    @Test
    func railContainsMainGroupsWithProfileAndSettingsInItsFooterMenu() {
        #expect(NavigationGroup.primaryGroups == [.overview, .runtime, .edge, .users, .authorization])
        #expect(NavigationGroup.allCases.last == .settings)
        #expect(!NavigationGroup.primaryGroups.contains(.settings))
        #expect(NavigationGroup.primaryGroups.map(\.title) == [
            "Overview", "Runtime", "Edge", "Users", "Authorization",
        ])
    }

    @Test
    func sectionsPartitionEveryDestinationExactlyOnce() {
        let grouped = NavigationGroup.allCases.flatMap(\.destinations)

        #expect(grouped == AppDestination.allCases)
        #expect(Set(grouped).count == AppDestination.allCases.count)
    }

    @Test
    func mainGroupsOpenTheirOwnOverview() {
        for group in NavigationGroup.primaryGroups {
            #expect(group.landing.group == group)
            #expect(group.landing.title == "Overview")
            #expect(group.destinations.first == group.landing)
        }
        #expect(NavigationGroup.overview.landing != NavigationGroup.runtime.landing)
    }

    @Test
    func childNavigationKeepsItsMainGroupSelected() {
        #expect(NavigationGroup.runtime.destinations == [.runtimeOverview, .workers, .services, .applications, .tasks])
        #expect(NavigationGroup.edge.destinations == [.edgeOverview, .hosting, .dns, .domains, .certificates])
        #expect(AppDestination.workers.group == AppDestination.tasks.group)
        #expect(AppDestination.hosting.group == AppDestination.certificates.group)
        #expect(AppDestination.permissions.group == .authorization)
        #expect(AppDestination.settings.group == .settings)
        #expect(AppDestination.profile.group == .settings)
    }

    @Test
    func settingsUsesProfileOnlyWhenUserManagementIsAvailable() {
        #expect(NavigationGroup.settings.destinations(userManagementAvailable: true) == [.profile, .settings])
        #expect(NavigationGroup.settings.landing(userManagementAvailable: true) == .profile)
        #expect(NavigationGroup.settings.destinations(userManagementAvailable: false) == [.settings])
        #expect(NavigationGroup.settings.landing(userManagementAvailable: false) == .settings)
    }

    @Test
    func destinationsExposeStableIdentifiersAndSymbols() {
        let destinations = AppDestination.allCases

        #expect(Set(destinations.map(\.id)).count == destinations.count)
        #expect(destinations.allSatisfy { !$0.systemImage.isEmpty })
    }
}
