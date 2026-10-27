import Testing
@testable import Claviron

@MainActor
struct NavigationHistoryTests {
    @Test
    func arrowsFollowSectionAndDetailHistory() {
        let history = NavigationHistory()
        #expect(!history.canGoBack)
        #expect(!history.canGoForward)
        history.back()
        history.forward()
        #expect(history.current.destination == .overview)

        let sites = NavigationLocation(destination: .hosting)
        let detail = NavigationLocation(destination: .hosting, details: [3])
        history.visit(sites)
        history.visit(detail)
        #expect(history.canGoBack)
        #expect(!history.canGoForward)

        history.back()
        #expect(history.current == sites)
        #expect(history.canGoForward)
        history.back()
        #expect(history.current.destination == .overview)
        #expect(!history.canGoBack)
        history.forward()
        history.forward()
        #expect(history.current == detail)
        #expect(!history.canGoForward)
    }

    @Test
    func sectionChangesRestoreThePreviousDetailStack() {
        let history = NavigationHistory()
        let worker = NavigationLocation(destination: .workers, details: [AnyHashable(UInt32(4))])
        history.visit(worker)
        history.visit(NavigationLocation(destination: .tasks, details: ["example-task"]))
        history.back()
        #expect(history.current == worker)
        #expect(history.current.details.first?.base as? UInt32 == 4)
    }

    @Test
    func newNavigationDiscardsForwardHistoryButDuplicateDoesNot() {
        let history = NavigationHistory()
        let sites = NavigationLocation(destination: .hosting)
        history.visit(sites)
        history.visit(NavigationLocation(destination: .domains))
        history.back()
        history.visit(sites)
        #expect(history.canGoForward)
        history.visit(NavigationLocation(destination: .dns))
        #expect(!history.canGoForward)
        history.back()
        #expect(history.current == sites)
        history.back()
        #expect(!history.canGoBack)
    }

    @Test
    func serverChangeDropsResourcePathsAndHistory() {
        let history = NavigationHistory()
        history.visit(NavigationLocation(destination: .certificates, details: [2]))
        history.reset()
        #expect(history.current == NavigationLocation(destination: .certificates))
        #expect(!history.canGoBack)
        #expect(!history.canGoForward)
    }

    @Test
    func firstGroupVisitsOpenTheirOwnOverview() {
        let history = NavigationHistory()
        for group in NavigationGroup.primaryGroups {
            history.activate(group)
            #expect(history.current == NavigationLocation(destination: group.landing))
        }
    }

    @Test
    func groupSwitchesResumeTheLastPageAndTypedDetailStack() {
        let history = NavigationHistory()
        let worker = NavigationLocation(destination: .workers, details: [AnyHashable(UInt32(4))])
        let site = NavigationLocation(destination: .hosting, details: [AnyHashable(Int64(3))])
        history.activate(.runtime)
        history.visit(worker)
        history.activate(.edge)
        history.visit(site)

        for _ in 0..<2 {
            history.activate(.runtime)
            #expect(history.current == worker)
            #expect(history.current.details.first?.base as? UInt32 == 4)
            history.activate(.edge)
            #expect(history.current == site)
            #expect(history.current.details.first?.base as? Int64 == 3)
        }
    }

    @Test
    func selectingTheActiveGroupKeepsItsDetailAndForwardHistory() {
        let history = NavigationHistory()
        let task = NavigationLocation(destination: .tasks, details: ["example-task"])
        history.activate(.runtime)
        history.visit(task)
        history.activate(.edge)
        history.back()
        history.activate(.runtime)
        #expect(history.current == task)
        #expect(history.canGoForward)
        history.back()
        #expect(history.current == NavigationLocation(destination: .runtimeOverview))
    }

    @Test
    func historyTraversalUpdatesTheGroupLocationAndGroupSwitchBranchesHistory() {
        let history = NavigationHistory()
        let task = NavigationLocation(destination: .tasks, details: ["example-task"])
        history.activate(.runtime)
        history.visit(task)
        history.activate(.edge)
        history.back()
        history.back()
        history.forward()
        #expect(history.current == task)
        history.back()
        history.activate(.users)
        #expect(!history.canGoForward)
        history.activate(.runtime)
        #expect(history.current == NavigationLocation(destination: .runtimeOverview))
        history.back()
        #expect(history.current == NavigationLocation(destination: .usersOverview))
    }

    @Test
    func explicitSubmenuSelectionReplacesTheRememberedPage() {
        let history = NavigationHistory()
        history.visit(NavigationLocation(destination: .tasks, details: ["example-task"]))
        history.visit(NavigationLocation(destination: .services))
        history.activate(.edge)
        history.activate(.runtime)
        #expect(history.current == NavigationLocation(destination: .services))
        history.visit(NavigationLocation(destination: .runtimeOverview))
        history.activate(.edge)
        history.activate(.runtime)
        #expect(history.current == NavigationLocation(destination: .runtimeOverview))
    }

    @Test
    func serverChangeClearsDormantGroupDetailsAndRetainsTheirPageChoices() {
        let history = NavigationHistory()
        history.visit(NavigationLocation(destination: .tasks, details: ["example-task"]))
        history.visit(NavigationLocation(destination: .certificates, details: [2]))
        history.reset()
        #expect(history.current == NavigationLocation(destination: .certificates))
        #expect(!history.canGoBack)
        #expect(!history.canGoForward)
        history.activate(.runtime)
        #expect(history.current == NavigationLocation(destination: .tasks))
        history.activate(.edge)
        #expect(history.current == NavigationLocation(destination: .certificates))
        history.back()
        #expect(history.current == NavigationLocation(destination: .tasks))
    }

    @Test
    func groupRestoreRespectsTheCurrentServersProfileCapability() {
        let history = NavigationHistory()
        history.visit(NavigationLocation(destination: .profile))
        history.activate(.runtime)
        history.activate(.settings, userManagementAvailable: false)
        #expect(history.current == NavigationLocation(destination: .settings))
    }

    @Test
    func dormantPagesKeepTheirOwnPathsEvenWithinTheSameGroup() {
        let history = NavigationHistory()
        let task = NavigationLocation(destination: .tasks, details: ["example-task"])
        let worker = NavigationLocation(destination: .workers, details: [AnyHashable(UInt32(4))])
        history.visit(task)
        history.visit(worker)
        history.activate(.edge)
        #expect(history.location(for: .tasks) == task)
        #expect(history.location(for: .workers) == worker)
        history.activate(.runtime)
        #expect(history.current == worker)
        #expect(history.location(for: .tasks) == task)
        history.reset()
        #expect(history.location(for: .tasks).details.isEmpty)
        #expect(history.location(for: .workers).details.isEmpty)
    }

    @Test
    func retainedPagesAreCreatedOnceOnFirstVisitAndDiscardedOnServerChange() {
        let history = NavigationHistory()
        #expect(history.visitedDestinations == [.overview])
        history.visit(NavigationLocation(destination: .tasks))
        history.visit(NavigationLocation(destination: .tasks, details: ["example-task"]))
        history.activate(.edge)
        history.activate(.runtime)
        #expect(history.visitedDestinations == [.overview, .tasks, .edgeOverview])
        history.reset()
        #expect(history.visitedDestinations == [.tasks])
    }
}
