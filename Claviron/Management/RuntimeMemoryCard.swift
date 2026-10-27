import ClavironControlPlane
import SwiftUI

struct RuntimeMemoryCard: View {
    let state: RuntimeMemoryObservationState
    let supported: Bool

    var body: some View {
        ManagementDetailCard("Resident Memory (RSS)", systemImage: "memorychip", tint: .purple) {
            if !supported {
                Text("This server has not reported metrics support.").foregroundStyle(.secondary)
            } else if let snapshot = state.snapshot {
                if snapshot.processes.isEmpty {
                    Text("Process RSS is not reported in the metrics snapshot.").foregroundStyle(.secondary)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), alignment: .leading)], alignment: .leading, spacing: 12) {
                        value("Total RSS", bytes: snapshot.totalRSSBytes)
                        value("Master RSS", bytes: snapshot.masterRSSBytes)
                        value("Workers RSS", bytes: snapshot.workerRSSBytes)
                    }
                    Divider()
                    ForEach(snapshot.processes) { process in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(title(process)).font(.callout.weight(.medium))
                                Text("Node \(process.nodeID) · PID \(process.pid)").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(formatted(process.rssBytes)).font(.body.monospacedDigit())
                        }
                    }
                    Text("Sum of reported process RSS samples; shared pages may be counted more than once.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Text("Observed \(snapshot.observedAt.formatted(date: .omitted, time: .standard))")
                    .font(.caption).foregroundStyle(.tertiary)
            } else if case .loading = state {
                ProgressView("Reading metrics…")
            } else if case .failed = state {
                EmptyView()
            } else {
                Text("Memory metrics have not been read.").foregroundStyle(.secondary)
            }
            if case let .stale(_, failure) = state {
                Label("Previous snapshot · \(failure.localizedDescription)", systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.orange)
            }
            if case let .failed(failure) = state {
                Text(failure.localizedDescription).foregroundStyle(.orange)
            }
        }
    }

    private func value(_ title: String, bytes: UInt64?) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(bytes.map(formatted) ?? "Not reported")
                .font(.title3.weight(.semibold)).monospacedDigit()
        }
    }

    private func formatted(_ bytes: UInt64) -> String {
        let unit: String
        let divisor: Double
        if bytes >= 1_073_741_824 { unit = "GiB"; divisor = 1_073_741_824 }
        else { unit = "MiB"; divisor = 1_048_576 }
        return "\((Double(bytes) / divisor).formatted(.number.precision(.fractionLength(2)))) \(unit)"
    }

    private func title(_ process: ProcessMemoryObservation) -> String {
        switch process.role {
        case "master": "Master"
        case "worker": "Worker #\(process.workerID)"
        case "standalone": "Standalone"
        default: process.role
        }
    }
}
