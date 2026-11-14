import CryptoKit
import Foundation
import Network
import os
import Security

/// What the operator gives to enroll this device: the server's enroll
/// address, an account, and this device's label. The server answers with its
/// own name and its management address.
nonisolated struct EnrollmentInput: Sendable {
    var address = ""
    var username = ""
    var password = ""
    /// One DNS label naming this device's certificate, such as `laptop-app`.
    var device = EnrollmentInput.defaultDevice

    /// The enrollment session's one path on the server's enroll address.
    func enrollmentURL() throws -> URL {
        guard address.isValidHTTPSEndpoint,
              var components = URLComponents(string: address) else {
            throw EnrollmentError.invalidAddress
        }
        components.path = Enrollment.path
        guard let url = components.url else { throw EnrollmentError.invalidAddress }
        return url
    }

    func endpoint() throws -> URL {
        let url = try enrollmentURL()
        guard !username.isBlank, !password.isEmpty else {
            throw EnrollmentError.missingCredentials
        }
        guard Self.isDeviceLabel(device) else { throw EnrollmentError.invalidDevice }
        return url
    }

    /// This Mac as `<short-hostname>-app`; an iPhone or iPad, whose name an
    /// app cannot read, as `ios-app` for the operator to change.
    static var defaultDevice: String {
        #if os(macOS)
        deviceLabel(host: ProcessInfo.processInfo.hostName)
        #else
        "ios-app"
        #endif
    }

    /// A host name lowered and folded into one label, with `-app` after it.
    static func deviceLabel(host: String) -> String {
        let short = host.split(separator: ".", maxSplits: 1).first.map(String.init) ?? ""
        let folded = String(short.lowercased().map { character in
            character.isASCII && (character.isLetter || character.isNumber) ? character : "-"
        })
        let hyphen = CharacterSet(charactersIn: "-")
        let label = String(folded.trimmingCharacters(in: hyphen).prefix(59))
        return label.trimmingCharacters(in: hyphen) + "-app"
    }

    /// One DNS label: 1 to 63 lowercase letters, digits and inner hyphens.
    static func isDeviceLabel(_ label: String) -> Bool {
        let bytes = Array(label.utf8)
        return (1...63).contains(bytes.count)
            && bytes.allSatisfy { (97...122).contains($0) || (48...57).contains($0) || $0 == 45 }
            && bytes.first != 45 && bytes.last != 45
    }
}

nonisolated enum EnrollmentError: Equatable, LocalizedError {
    case invalidAddress
    case invalidManagementAddress
    case missingCredentials
    case invalidDevice
    case notOffered
    case probeRejected(Int)
    case invalidProbe
    case rejected(Int)
    case invalidResponse
    case invalidCertificate
    case connection(String)

    var errorDescription: String? {
        switch self {
        case .invalidAddress: "Enter an HTTPS enroll address without a path."
        case .invalidManagementAddress: "Enrollment returned an invalid management address."
        case .missingCredentials: "Enter your username and password."
        case .invalidDevice: "Name this device with lowercase letters, digits and inner hyphens."
        case .notOffered: "The server does not offer mTLS enrollment at this address."
        case .invalidProbe: "The server did not identify a Claviron enrollment endpoint."
        case .probeRejected(let status): "The enrollment endpoint returned HTTP \(status)."
        case .rejected(400): "The server refused the request: the device name or a field."
        case .rejected(401), .rejected(403): "The server denied enrollment."
        case .rejected(409): "This device name already has a certificate for another key."
        case .rejected(let status): "Enrollment failed (HTTP \(status))."
        case .invalidResponse: "The server's answer could not be read."
        case .invalidCertificate: "The server returned an invalid client certificate."
        case .connection(let reason): "Could not reach the enroll address: \(reason)"
        }
    }
}

nonisolated struct EnrollmentCertificates: Sendable {
    let clientChainPEM: Data
    let authorityPEM: Data
}

nonisolated struct EnrollmentResult: Sendable {
    /// The server's own name, which the saved server is named after.
    let serverName: String
    let managementAddress: String
    let certificates: EnrollmentCertificates
}

/// mTLS enrollment, `claviron-mtls-enroll/1`: one HTTP/1.1 exchange on a TLS
/// connection that offers the enrollment ALPN id alone, as Claviron gRPC's
/// enrollment contract describes.
nonisolated enum Enrollment {
    static let applicationProtocol = "claviron-mtls-enroll/1"
    static let path = "/.well-known/claviron/mtls-enroll"

    private struct RequestBody: Encodable {
        let credential: Credential
        let device: String
        let csr_der: Data
    }

    private struct Credential: Encodable {
        let password: Password
    }

    private struct Password: Encodable {
        let username: String
        let password: String
    }

    private struct ResponseBody: Decodable {
        let server_name: String
        let management_address: String
        let certificate_chain_pem: String
        let authority_certificate_pem: String
    }

    static func probe(_ input: EnrollmentInput) async throws {
        let url = try input.enrollmentURL()
        let response = try await EnrollmentConnection.exchange(
            url: url, request: request(method: "HEAD", url: url, body: nil)
        )
        try validateProbe(response)
    }

    static func validateProbe(_ response: EnrollmentHTTPResponse) throws {
        guard response.status == 204 else {
            throw EnrollmentError.probeRejected(response.status)
        }
        guard response.headers["claviron-mtls-enroll"] == "1" else {
            throw EnrollmentError.invalidProbe
        }
    }

    static func issue(
        _ input: EnrollmentInput,
        key: P256.Signing.PrivateKey
    ) async throws -> EnrollmentResult {
        let url = try input.endpoint()
        let body = try JSONEncoder().encode(RequestBody(
            credential: Credential(password: Password(username: input.username, password: input.password)),
            device: input.device,
            csr_der: try certificateRequest(key)
        ))
        let response = try await EnrollmentConnection.exchange(
            url: url, request: request(method: "POST", url: url, body: body)
        )
        guard response.status == 201 else {
            throw EnrollmentError.rejected(response.status)
        }
        return try validateResponse(response.body, publicKey: key.publicKey)
    }

    /// One request that asks the server to close the connection after it.
    static func request(method: String, url: URL, body: Data?) -> Data {
        var authority = url.host() ?? ""
        if let port = url.port, port != 443 { authority += ":\(port)" }
        var head = "\(method) \(path) HTTP/1.1\r\nHost: \(authority)\r\nAccept: application/json\r\nConnection: close\r\n"
        if let body {
            head += "Content-Type: application/json\r\nContent-Length: \(body.count)\r\n"
        }
        head += "\r\n"
        return Data(head.utf8) + (body ?? Data())
    }

    static func validateResponse(
        _ body: Data,
        publicKey: P256.Signing.PublicKey
    ) throws -> EnrollmentResult {
        guard let issued = try? JSONDecoder().decode(ResponseBody.self, from: body),
              !issued.server_name.isBlank else {
            throw EnrollmentError.invalidResponse
        }
        try validateManagementAddress(issued.management_address)
        try verifyIdentity(issued, publicKey: publicKey.x963Representation)
        return EnrollmentResult(
            serverName: issued.server_name,
            managementAddress: issued.management_address,
            certificates: EnrollmentCertificates(
                clientChainPEM: Data(issued.certificate_chain_pem.utf8),
                authorityPEM: Data(issued.authority_certificate_pem.utf8)
            )
        )
    }

    /// The management address may be the enroll host itself: its ordinary
    /// connections keep mutual TLS beside the enrollment session.
    static func validateManagementAddress(_ address: String) throws {
        guard address.isValidHTTPSEndpoint, URLComponents(string: address)?.host != nil else {
            throw EnrollmentError.invalidManagementAddress
        }
    }

    static func certificateRequest(_ key: P256.Signing.PrivateKey) throws -> Data {
        // PKCS#10 v1, an empty subject and attributes, and the device's SPKI.
        let information = DER.encode(0x30, Data([0x02, 0x01, 0x00, 0x30, 0x00])
            + key.publicKey.derRepresentation + Data([0xa0, 0x00]))
        let signature = try key.signature(for: information).derRepresentation
        let ecdsaWithSHA256 = Data([0x30, 0x0a, 0x06, 0x08, 0x2a, 0x86, 0x48, 0xce, 0x3d, 0x04, 0x03, 0x02])
        return DER.encode(0x30, information + ecdsaWithSHA256 + DER.encode(0x03, Data([0]) + signature))
    }

    private static func verifyIdentity(_ issued: ResponseBody, publicKey: Data) throws {
        let chain = try certificates(in: issued.certificate_chain_pem)
        let anchors = try certificates(in: issued.authority_certificate_pem)
        guard anchors.count == 1, let anchor = anchors.first, let leaf = chain.first else {
            throw EnrollmentError.invalidCertificate
        }
        let anchorDER = SecCertificateCopyData(anchor)
        guard !chain.contains(where: { SecCertificateCopyData($0) == anchorDER }),
              let key = SecCertificateCopyKey(leaf),
              let bytes = SecKeyCopyExternalRepresentation(key, nil),
              bytes as Data == publicKey else {
            throw EnrollmentError.invalidCertificate
        }

        var trust: SecTrust?
        guard SecTrustCreateWithCertificates(chain as CFArray, SecPolicyCreateSSL(false, nil), &trust) == errSecSuccess,
              let trust,
              SecTrustSetAnchorCertificates(trust, anchors as CFArray) == errSecSuccess,
              SecTrustSetAnchorCertificatesOnly(trust, true) == errSecSuccess,
              SecTrustSetNetworkFetchAllowed(trust, false) == errSecSuccess,
              SecTrustEvaluateWithError(trust, nil) else {
            throw EnrollmentError.invalidCertificate
        }
    }

    private static func certificates(in pem: String) throws -> [SecCertificate] {
        let begin = "-----BEGIN CERTIFICATE-----"
        let end = "-----END CERTIFICATE-----"
        var blocks = pem.components(separatedBy: end)
        guard let remainder = blocks.popLast(), remainder.isBlank, !blocks.isEmpty else {
            throw EnrollmentError.invalidCertificate
        }
        return try blocks.map { block in
            let entry = block.trimmingCharacters(in: .whitespacesAndNewlines)
            guard entry.hasPrefix(begin),
                  let bytes = Data(base64Encoded: entry.dropFirst(begin.count).filter { !$0.isWhitespace }),
                  let certificate = SecCertificateCreateWithData(nil, bytes as CFData) else {
                throw EnrollmentError.invalidCertificate
            }
            return certificate
        }
    }
}

/// An HTTP/1.1 answer: its status, lowercase header names, and body.
nonisolated struct EnrollmentHTTPResponse: Equatable, Sendable {
    let status: Int
    let headers: [String: String]
    let body: Data

    /// The whole answer the server wrote before closing the connection.
    static func parse(_ data: Data) throws -> Self {
        guard let end = data.range(of: Data("\r\n\r\n".utf8)),
              let head = String(data: data[..<end.lowerBound], encoding: .utf8) else {
            throw EnrollmentError.invalidResponse
        }
        var lines = head.components(separatedBy: "\r\n")
        let statusLine = lines.removeFirst().split(separator: " ", maxSplits: 2)
        guard statusLine.count >= 2, statusLine[0].hasPrefix("HTTP/1."),
              let status = Int(statusLine[1]) else {
            throw EnrollmentError.invalidResponse
        }
        var headers: [String: String] = [:]
        for line in lines {
            guard let colon = line.firstIndex(of: ":") else { throw EnrollmentError.invalidResponse }
            headers[line[..<colon].lowercased()] = line[line.index(after: colon)...]
                .trimmingCharacters(in: .whitespaces)
        }
        // The server answers with a length; a chunked answer is not read here.
        guard headers["transfer-encoding"] == nil else { throw EnrollmentError.invalidResponse }
        var body = Data(data[end.upperBound...])
        if let length = headers["content-length"].flatMap(Int.init) {
            guard body.count >= length else { throw EnrollmentError.invalidResponse }
            body = body.prefix(length)
        }
        return Self(status: status, headers: headers, body: body)
    }
}

/// One TLS connection offering the enrollment ALPN id alone, carrying one
/// request and the answer up to the server's close. The server's certificate
/// is verified against the system's trust. No deadline is invented: the
/// caller's cancellation ends the connection.
nonisolated enum EnrollmentConnection {
    static func exchange(url: URL, request: Data) async throws -> EnrollmentHTTPResponse {
        guard let host = url.host(),
              let port = NWEndpoint.Port(rawValue: UInt16(url.port ?? 443)) else {
            throw EnrollmentError.invalidAddress
        }
        let tls = NWProtocolTLS.Options()
        sec_protocol_options_add_tls_application_protocol(
            tls.securityProtocolOptions, Enrollment.applicationProtocol
        )
        let connection = NWConnection(
            host: NWEndpoint.Host(host), port: port,
            using: NWParameters(tls: tls, tcp: NWProtocolTCP.Options())
        )
        defer { connection.cancel() }
        return try await withTaskCancellationHandler {
            try await ready(connection)
            guard negotiatedProtocol(connection) == Enrollment.applicationProtocol else {
                throw EnrollmentError.notOffered
            }
            try await send(request, on: connection)
            return try EnrollmentHTTPResponse.parse(try await receiveAll(connection))
        } onCancel: {
            connection.cancel()
        }
    }

    private static func ready(_ connection: NWConnection) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let resumed = OSAllocatedUnfairLock(initialState: false)
            let finish: @Sendable (Result<Void, Error>) -> Void = { result in
                let first = resumed.withLock { done in
                    defer { done = true }
                    return !done
                }
                if first { continuation.resume(with: result) }
            }
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    finish(.success(()))
                case let .failed(error), let .waiting(error):
                    finish(.failure(EnrollmentError.connection(error.localizedDescription)))
                case .cancelled:
                    finish(.failure(CancellationError()))
                default:
                    break
                }
            }
            connection.start(queue: .global(qos: .userInitiated))
        }
    }

    private static func negotiatedProtocol(_ connection: NWConnection) -> String? {
        guard let metadata = connection.metadata(definition: NWProtocolTLS.definition) as? NWProtocolTLS.Metadata,
              let negotiated = sec_protocol_metadata_get_negotiated_protocol(metadata.securityProtocolMetadata) else {
            return nil
        }
        return String(cString: negotiated)
    }

    private static func send(_ data: Data, on connection: NWConnection) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error {
                    continuation.resume(throwing: EnrollmentError.connection(error.localizedDescription))
                } else {
                    continuation.resume()
                }
            })
        }
    }

    /// Everything the server writes until it closes, bounded like an import.
    private static func receiveAll(_ connection: NWConnection) async throws -> Data {
        var received = Data()
        while true {
            let (chunk, complete) = try await receive(connection)
            received.append(chunk)
            guard received.count <= ImportedCredential.maximumByteCount else {
                throw EnrollmentError.invalidResponse
            }
            if complete { return received }
        }
    }

    private static func receive(_ connection: NWConnection) async throws -> (Data, Bool) {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<(Data, Bool), Error>) in
            connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1_024) { data, _, isComplete, error in
                if let error {
                    continuation.resume(throwing: EnrollmentError.connection(error.localizedDescription))
                } else {
                    continuation.resume(returning: (data ?? Data(), isComplete))
                }
            }
        }
    }
}
