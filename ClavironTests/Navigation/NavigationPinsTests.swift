import Testing
@testable import Claviron

@MainActor
struct NavigationPinsTests {
    @Test
    func existingSectionsAreVisibleByDefault() {
        let pins = NavigationPins(storedValue: NavigationPins.defaultValue)
        #expect(pins.groups == NavigationGroup.primaryGroups)
    }

    @Test
    func unpinnedSectionRemainsInTheMenuAndCanBeRestored() {
        var pins = NavigationPins(storedValue: NavigationPins.defaultValue)
        pins.toggle(.users)
        let restored = NavigationPins(storedValue: pins.storedValue)
        #expect(!restored.contains(.users))
        #expect(NavigationGroup.primaryGroups.contains(.users))
        pins.toggle(.users)
        #expect(pins.groups == NavigationGroup.primaryGroups)
    }

    @Test
    func homeCannotBeHiddenAndSettingsCannotBePinned() {
        var pins = NavigationPins(storedValue: "")
        pins.toggle(.overview)
        pins.toggle(.settings)
        #expect(pins.groups == [.overview])
    }

    @Test
    func storedPinsDiscardUnknownEntriesAndDuplicates() {
        let pins = NavigationPins(storedValue: "users,obsolete,settings,users,runtime")
        #expect(pins.groups == [.overview, .runtime, .users])
        #expect(pins.storedValue == "overview,runtime,users")
    }
}
