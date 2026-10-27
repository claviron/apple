import ClavironControlPlane
import Foundation

/// Editable text for a zone write. The protocol replaces the whole zone, so a
/// draft always carries every field. Timers are never filled in for the
/// operator: SOA durations are an operator decision (TIME_OWNERSHIP), so a
/// new zone starts with them empty and the form will not submit until each
/// is given.
nonisolated struct DnsZoneDraft: Equatable, Sendable {
    var domain = ""
    var mname = ""
    var rname = ""
    var refresh = ""
    var retry = ""
    var expire = ""
    var minimum = ""
    var enabled = true

    init() {}

    init(_ configuration: DnsZoneConfiguration) {
        domain = configuration.domain
        enabled = configuration.enabled
        if let soa = configuration.soa {
            mname = soa.mname
            rname = soa.rname
            refresh = String(soa.refresh)
            retry = String(soa.retry)
            expire = String(soa.expire)
            minimum = String(soa.minimum)
        }
    }

    /// The first thing that keeps this draft from being a valid write.
    var issue: String? {
        switch result {
        case .success: nil
        case let .failure(issue): issue.message
        }
    }

    var configuration: DnsZoneConfiguration? {
        try? result.get()
    }

    private var result: Result<DnsZoneConfiguration, DnsDraftIssue> {
        let domain = domain.trimmed
        let mname = mname.trimmed
        let rname = rname.trimmed
        guard !domain.isEmpty else { return .failure(.required("Domain")) }
        guard !mname.isEmpty else { return .failure(.required("Primary name server")) }
        guard !rname.isEmpty else { return .failure(.required("Responsible mailbox")) }
        do throws(DnsDraftIssue) {
            let soa = DnsSOAConfiguration(
                mname: mname,
                rname: rname,
                refresh: try DnsDraftIssue.seconds(refresh, field: "Refresh"),
                retry: try DnsDraftIssue.seconds(retry, field: "Retry"),
                expire: try DnsDraftIssue.seconds(expire, field: "Expire"),
                minimum: try DnsDraftIssue.seconds(minimum, field: "Minimum TTL")
            )
            return .success(DnsZoneConfiguration(domain: domain, soa: soa, enabled: enabled))
        } catch {
            return .failure(error)
        }
    }
}

/// Editable text for a record write, again a full replacement. Priority,
/// weight and port keep presence: an empty field is absent, `0` is zero.
nonisolated struct DnsRecordDraft: Equatable, Sendable {
    static let knownTypes = ["A", "AAAA", "CNAME", "MX", "TXT", "NS", "SRV", "CAA", "PTR"]

    var name = ""
    var type = "A"
    var value = ""
    var ttl = ""
    var priority = ""
    var weight = ""
    var port = ""
    var enabled = true

    init() {}

    init(_ configuration: DnsRecordConfiguration) {
        name = configuration.name
        type = configuration.type
        value = configuration.value
        ttl = String(configuration.ttl)
        priority = configuration.priority.map(String.init) ?? ""
        weight = configuration.weight.map(String.init) ?? ""
        port = configuration.port.map(String.init) ?? ""
        enabled = configuration.enabled
    }

    /// The types the picker offers, keeping a stored type the list lacks.
    var typeChoices: [String] {
        Self.knownTypes.contains(type) ? Self.knownTypes : Self.knownTypes + [type]
    }

    var usesPriority: Bool { type == "MX" || type == "SRV" }
    var usesWeightAndPort: Bool { type == "SRV" }

    var issue: String? {
        switch result {
        case .success: nil
        case let .failure(issue): issue.message
        }
    }

    var configuration: DnsRecordConfiguration? {
        try? result.get()
    }

    private var result: Result<DnsRecordConfiguration, DnsDraftIssue> {
        let name = name.trimmed
        let type = type.trimmed.uppercased()
        let value = value.trimmed
        guard !name.isEmpty else { return .failure(.required("Name")) }
        guard !type.isEmpty else { return .failure(.required("Type")) }
        guard !value.isEmpty else { return .failure(.required("Value")) }
        do throws(DnsDraftIssue) {
            return .success(DnsRecordConfiguration(
                name: name,
                type: type,
                value: value,
                ttl: try DnsDraftIssue.seconds(ttl, field: "TTL"),
                priority: try DnsDraftIssue.optionalNumber(priority, field: "Priority"),
                weight: try DnsDraftIssue.optionalNumber(weight, field: "Weight"),
                port: try DnsDraftIssue.optionalNumber(port, field: "Port"),
                enabled: enabled
            ))
        } catch {
            return .failure(error)
        }
    }
}

nonisolated enum DnsDraftIssue: Error, Equatable {
    case required(String)
    case notANumber(String)

    var message: String {
        switch self {
        case let .required(field): "\(field) is required."
        case let .notANumber(field): "\(field) must be a whole number."
        }
    }

    static func seconds(_ text: String, field: String) throws(DnsDraftIssue) -> UInt32 {
        let text = text.trimmed
        guard !text.isEmpty else { throw .required(field) }
        guard let value = UInt32(text) else { throw .notANumber(field) }
        return value
    }

    static func optionalNumber(_ text: String, field: String) throws(DnsDraftIssue) -> UInt32? {
        let text = text.trimmed
        guard !text.isEmpty else { return nil }
        guard let value = UInt32(text) else { throw .notANumber(field) }
        return value
    }
}

private extension String {
    nonisolated var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
