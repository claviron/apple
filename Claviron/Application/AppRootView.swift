import SwiftUI

struct AppRootView: View {
    @Bindable var applicationModel: ApplicationModel
    @AppStorage(AppAppearance.storageKey) private var storedAppearance = AppAppearance.system.rawValue

    var body: some View {
        Group {
            switch applicationModel.loadState {
            case .idle, .loading:
                ProgressView("Loading configuration…")
            case .ready where applicationModel.needsInitialConfiguration:
                InitialConfigurationView(applicationModel: applicationModel)
            case .ready:
                ContentView(applicationModel: applicationModel)
            case let .failed(message):
                ContentUnavailableView {
                    Label("Configuration Unavailable", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(message)
                } actions: {
                    Button("Try Again") {
                        Task {
                            await applicationModel.reload()
                        }
                    }
                }
            }
        }
        .preferredColorScheme(AppAppearance.resolve(storedAppearance).colorScheme)
        .task {
            await applicationModel.loadIfNeeded()
        }
    }
}

#Preview("First Launch") {
    AppRootView(applicationModel: .preview())
}

#Preview("Configured") {
    AppRootView(applicationModel: .preview(configuration: .preview))
}
