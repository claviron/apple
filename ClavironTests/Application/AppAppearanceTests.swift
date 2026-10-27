import SwiftUI
import Testing
@testable import Claviron

struct AppAppearanceTests {
    @Test
    func storedValuesResolveToSupportedAppearances() {
        #expect(AppAppearance.resolve("system") == .system)
        #expect(AppAppearance.resolve("light") == .light)
        #expect(AppAppearance.resolve("dark") == .dark)
        #expect(AppAppearance.resolve("unsupported") == .system)
        #expect(AppAppearance.allCases.map(\.title) == ["Auto", "Light", "Dark"])
    }

    @Test @MainActor
    func appearancesMapToTheExpectedColorScheme() {
        #expect(AppAppearance.system.colorScheme == nil)
        #expect(AppAppearance.light.colorScheme == .light)
        #expect(AppAppearance.dark.colorScheme == .dark)
    }
}
