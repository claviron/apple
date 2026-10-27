import Foundation

public struct ProcessMemoryObservation: Equatable, Sendable, Identifiable {
    public let role: String
    public let nodeID: UInt64
    public let workerID: UInt32
    public let pid: UInt32
    public let rssBytes: UInt64
    public var id: String { "\(nodeID):\(pid)" }
}

/// RSS sums describe reported process samples; shared pages may be counted again.
public struct RuntimeMemorySnapshot: Equatable, Sendable {
    public let processes: [ProcessMemoryObservation]
    public let observedAt: Date
    public let totalRSSBytes: UInt64?
    public let masterRSSBytes: UInt64?
    public let workerRSSBytes: UInt64?

    public var workers: [ProcessMemoryObservation] { processes.filter { $0.role == "worker" } }

    public init(prometheus: String, observedAt: Date = Date()) throws {
        let metric = "claviron_supervisor_process_rss_bytes{"
        let labelPattern = try NSRegularExpression(pattern: #"([a-zA-Z_][a-zA-Z0-9_]*)="([^"\\]*)""#)
        var samples: [String: ProcessMemoryObservation] = [:]
        for line in prometheus.split(whereSeparator: \.isNewline) where line.hasPrefix(metric) {
            guard let end = line.firstIndex(of: "}") else { throw Self.invalid() }
            let rawLabels = String(line[line.index(line.startIndex, offsetBy: metric.count)..<end])
            var labels: [String: String] = [:]
            for match in labelPattern.matches(in: rawLabels, range: NSRange(rawLabels.startIndex..., in: rawLabels)) {
                guard let keyRange = Range(match.range(at: 1), in: rawLabels),
                      let valueRange = Range(match.range(at: 2), in: rawLabels) else { throw Self.invalid() }
                let key = String(rawLabels[keyRange])
                guard labels.updateValue(String(rawLabels[valueRange]), forKey: key) == nil else { throw Self.invalid() }
            }
            guard let role = labels["role"], !role.isEmpty,
                  let node = labels["node_id"].flatMap(UInt64.init),
                  let worker = labels["worker_id"].flatMap(UInt32.init),
                  let pid = labels["pid"].flatMap(UInt32.init),
                  let rawValue = line[line.index(after: end)...].split(whereSeparator: \.isWhitespace).first,
                  let number = Double(rawValue), let bytes = UInt64(exactly: number) else { throw Self.invalid() }
            let sample = ProcessMemoryObservation(role: role, nodeID: node, workerID: worker, pid: pid, rssBytes: bytes)
            if let previous = samples[sample.id], previous != sample { throw Self.invalid() }
            samples[sample.id] = sample
        }
        self.processes = samples.values.sorted {
            if $0.nodeID != $1.nodeID { return $0.nodeID < $1.nodeID }
            if $0.workerID != $1.workerID { return $0.workerID < $1.workerID }
            return $0.pid < $1.pid
        }
        self.observedAt = observedAt
        self.totalRSSBytes = try Self.sum(processes)
        self.masterRSSBytes = try Self.sum(processes.filter { $0.role == "master" })
        self.workerRSSBytes = try Self.sum(processes.filter { $0.role == "worker" })
    }

    private static func sum(_ processes: [ProcessMemoryObservation]) throws -> UInt64? {
        guard !processes.isEmpty else { return nil }
        return try processes.reduce(UInt64(0)) { total, process in
            let (sum, overflow) = total.addingReportingOverflow(process.rssBytes)
            guard !overflow else { throw invalid() }
            return sum
        }
    }

    private static func invalid() -> ClavironClientFailure {
        ClavironClientFailure(kind: .protocolMismatch, diagnosticDetail: "The metrics response contains invalid process RSS samples.")
    }
}
