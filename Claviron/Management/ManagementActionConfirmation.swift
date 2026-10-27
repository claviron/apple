import SwiftUI

nonisolated enum ManagementActionImpact: Equatable, Sendable {
    case routine
    case disruptive
    case serviceWide
    case destructive

    var requiresConfirmation: Bool {
        switch self {
        case .routine:
            false
        case .disruptive, .serviceWide, .destructive:
            true
        }
    }

    var confirmationRole: ButtonRole? {
        switch self {
        case .routine, .disruptive, .serviceWide:
            nil
        case .destructive:
            .destructive
        }
    }
}

nonisolated struct ManagementActionIntent: Equatable, Sendable {
    let actionTitle: String
    let confirmationTitle: String
    let confirmationMessage: String
    let impact: ManagementActionImpact

    init(
        actionTitle: String,
        confirmationTitle: String,
        confirmationMessage: String,
        impact: ManagementActionImpact
    ) {
        self.actionTitle = actionTitle
        self.confirmationTitle = confirmationTitle
        self.confirmationMessage = confirmationMessage
        self.impact = impact
    }
}

struct ConfirmedManagementActionButton<Label: View>: View {
    let intent: ManagementActionIntent
    let action: () -> Void
    @ViewBuilder let label: () -> Label

    @State private var isConfirmationPresented = false

    var body: some View {
        Button {
            if intent.impact.requiresConfirmation {
                isConfirmationPresented = true
            } else {
                action()
            }
        } label: {
            label()
        }
        .confirmationDialog(
            intent.confirmationTitle,
            isPresented: $isConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button(
                intent.actionTitle,
                role: intent.impact.confirmationRole,
                action: action
            )
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(intent.confirmationMessage)
        }
    }
}

extension ConfirmedManagementActionButton where Label == Text {
    init(intent: ManagementActionIntent, action: @escaping () -> Void) {
        self.init(intent: intent, action: action) {
            Text(intent.actionTitle)
        }
    }
}
