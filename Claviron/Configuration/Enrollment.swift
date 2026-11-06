import CryptoKit
import Foundation
import Security

nonisolated struct EnrollmentInput: Sendable {
    var address = ""
    var username = ""
    var password = ""

    func registrationURL() throws -> URL {
        guard address.isValidHTTPSEndpoint,
              var registration = URLComponents(string: address) else {
            throw EnrollmentError.invalidAddress
        }
        registration.path = "/.well-known/claviron/grpc-registration"
        guard let url = registration.url else { throw EnrollmentError.invalidAddress }
        return url
    }

    func endpoint() throws -> URL {
        let url = try registrationURL()
        guard !username.isBlank, !password.isEmpty else {
            throw EnrollmentError.missingCredentials
        }
        return url
    }
}

nonisolated enum EnrollmentError: Equatable, LocalizedError {
    case invalidAddress
    case invalidManagementAddress
    case sameOrigin
    case missingCredentials
    case probeRejected(Int)
    case invalidProbe
    case rejected(Int)
    case invalidCertificate

    var errorDescription: String? {
        switch self {
        case .invalidAddress: "Enter an HTTPS registration address without a path."
        case .invalidManagementAddress: "Registration returned an invalid management address."
        case .sameOrigin: "Registration returned its own address as the management address."
        case .missingCredentials: "Enter your username and password."
        case .invalidProbe: "The server did not identify a Claviron registration endpoint."
        case .probeRejected(let status): "The registration endpoint returned HTTP \(status)."
        case .rejected(401), .rejected(403): "The server denied registration."
        case .rejected(409): "A certificate already exists for this account."
        case .rejected(let status): "Registration failed (HTTP \(status))."
        case .invalidCertificate: "The server returned an invalid client certificate."
        }
    }
}

nonisolated struct EnrollmentCertificates: Sendable {
    let clientChainPEM: Data
    let authorityPEM: Data
}

nonisolated struct EnrollmentResult: Sendable {
    let managementAddress: String
    let certificates: EnrollmentCertificates
}

nonisolated enum Enrollment {
    private struct RequestBody: Encodable {
        let username: String
        let password: String
        let csr_der: Data
    }

    private struct ResponseBody: Decodable {
        let management_address: String
        let certificate_chain_pem: String
        let authority_certificate_pem: String
    }

    static func probe(_ input: EnrollmentInput) async throws {
        let endpoint = try input.registrationURL()
        var request = URLRequest(url: endpoint, cachePolicy: .reloadIgnoringLocalCacheData)
        request.httpMethod = "HEAD"
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        let (_, response) = try await session.data(for: request, delegate: NoRedirect())
        try validateProbeResponse(response)
    }

    static func validateProbeResponse(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else {
            throw EnrollmentError.invalidProbe
        }
        guard http.statusCode == 204 else {
            throw EnrollmentError.probeRejected(http.statusCode)
        }
        guard http.value(forHTTPHeaderField: "Claviron-Registration") == "1" else {
            throw EnrollmentError.invalidProbe
        }
    }

    static func issue(
        _ input: EnrollmentInput,
        key: P256.Signing.PrivateKey
    ) async throws -> EnrollmentResult {
        let endpoint = try input.endpoint()
        let csr = try certificateRequest(key)
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            RequestBody(username: input.username, password: input.password, csr_der: csr)
        )

        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        let (bytes, response) = try await session.bytes(for: request, delegate: NoRedirect())
        guard let http = response as? HTTPURLResponse, http.statusCode == 201 else {
            throw EnrollmentError.rejected((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        var body = Data()
        for try await byte in bytes {
            guard body.count < ImportedCredential.maximumByteCount else {
                throw EnrollmentError.invalidCertificate
            }
            body.append(byte)
        }
        return try validateResponse(body, registration: endpoint, publicKey: key.publicKey)
    }

    static func validateResponse(
        _ body: Data,
        registration: URL,
        publicKey: P256.Signing.PublicKey
    ) throws -> EnrollmentResult {
        let issued = try JSONDecoder().decode(ResponseBody.self, from: body)
        try validateManagementAddress(issued.management_address, registration: registration)
        try verifyIdentity(issued, publicKey: publicKey.x963Representation)
        return EnrollmentResult(
            managementAddress: issued.management_address,
            certificates: EnrollmentCertificates(
                clientChainPEM: Data(issued.certificate_chain_pem.utf8),
                authorityPEM: Data(issued.authority_certificate_pem.utf8)
            )
        )
    }

    static func validateManagementAddress(_ address: String, registration: URL) throws {
        guard address.isValidHTTPSEndpoint,
              let management = URLComponents(string: address),
              let managementHost = management.host,
              let registrationHost = URLComponents(url: registration, resolvingAgainstBaseURL: false)?.host else {
            throw EnrollmentError.invalidManagementAddress
        }
        let dots = CharacterSet(charactersIn: ".")
        let sameHost = managementHost.trimmingCharacters(in: dots)
            .caseInsensitiveCompare(registrationHost.trimmingCharacters(in: dots)) == .orderedSame
        guard !sameHost || (management.port ?? 443) != (registration.port ?? 443) else {
            throw EnrollmentError.sameOrigin
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

private final class NoRedirect: NSObject, URLSessionTaskDelegate {
    nonisolated func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}
