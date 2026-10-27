//
//  ClavironApp.swift
//  Claviron
//
//  Created by Developer on 12.09.2026.
//

import SwiftUI

@main
struct ClavironApp: App {
    @State private var applicationModel = ApplicationModel.live()
#if os(macOS)
    @NSApplicationDelegateAdaptor(MacApplicationDelegate.self) private var applicationDelegate
    @State private var applicationPresentation = MacApplicationPresentation()
#endif

    var body: some Scene {
#if os(macOS)
        MenuBarExtra(
            "Claviron",
            image: "MenuBarIcon",
            isInserted: applicationPresentation.menuBarExtraBinding
        ) {
            ClavironMenuBarView(presentation: applicationPresentation)
        }
        .menuBarExtraStyle(.menu)

        Window("Claviron", id: ClavironWindow.mainID) {
            applicationRoot
                .background {
                    MacWindowPresentationObserver(
                        presentation: applicationPresentation
                    )
                }
        }
        .defaultLaunchBehavior(.presented)
        .windowToolbarStyle(.unifiedCompact)
        .commands {
            ClavironServerCommands()
        }
#else
        WindowGroup {
            applicationRoot
        }
#endif
    }

    private var applicationRoot: some View {
        AppRootView(applicationModel: applicationModel)
    }
}
