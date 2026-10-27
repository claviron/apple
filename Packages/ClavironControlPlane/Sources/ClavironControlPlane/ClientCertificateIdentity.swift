import Foundation

public enum ClientCertificateIdentity {
    public static func userSubject(_ key: ManagedRecordKey) -> String? {
        guard key.resource == .user, let id = UUID(uuidString: key.reference),
              id != UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)) else { return nil }
        return "urn:uuid:" + id.uuidString.lowercased()
    }

    public static func subject(_ identifier: String) -> String? {
        let value = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        if let subject = userSubject(ManagedRecordKey(resource: .user, reference: value)) { return subject }
        if value.lowercased().hasPrefix("urn:uuid:") {
            return userSubject(ManagedRecordKey(resource: .user, reference: String(value.dropFirst(9))))
        }
        guard !value.isEmpty, !value.unicodeScalars.contains(where: { CharacterSet.whitespacesAndNewlines.contains($0) || CharacterSet.controlCharacters.contains($0) }),
              let components = URLComponents(string: value), components.scheme != nil, components.url != nil else { return nil }
        return value
    }
}
