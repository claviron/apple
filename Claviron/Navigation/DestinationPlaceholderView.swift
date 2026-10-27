import SwiftUI

struct DestinationPlaceholderView: View {
    let destination: AppDestination

    private let productURL = URL(string: "https://claviron.app")!

    var body: some View {
        ContentUnavailableView {
            Label(destination.title, systemImage: destination.systemImage)
        } description: {
            switch destination.group {
            case .users:
                Text("No user data has been loaded.")
            case .authorization:
                Text("No authorization data has been loaded.")
            case .overview, .runtime, .edge, .settings:
                Text("Connect to Claviron to load this view.")
            }
        } actions: {
            Link("claviron.app", destination: productURL)
        }
        .accessibilityIdentifier("detail.\(destination.rawValue)")
        .workspaceNavigationTitle(destination.title)
    }
}

#Preview {
    DestinationPlaceholderView(destination: .workers)
}
