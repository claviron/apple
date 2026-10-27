import Foundation

public struct ClavironTLSCredentials: Equatable, Sendable {
    public let certificateAuthorityFile: URL
    public let clientCertificateFile: URL
    public let clientPrivateKeyFile: URL

    public init(
        certificateAuthorityFile: URL,
        clientCertificateFile: URL,
        clientPrivateKeyFile: URL
    ) {
        self.certificateAuthorityFile = certificateAuthorityFile
        self.clientCertificateFile = clientCertificateFile
        self.clientPrivateKeyFile = clientPrivateKeyFile
    }
}

public struct ClavironEndpoint: Equatable, Sendable {
    public let host: String
    public let port: Int
    public let credentials: ClavironTLSCredentials

    public init(
        serverAddress: String,
        credentials: ClavironTLSCredentials
    ) throws {
        guard
            let components = URLComponents(string: serverAddress),
            components.scheme?.lowercased() == "https",
            let host = components.host,
            !host.isEmpty,
            components.user == nil,
            components.password == nil,
            components.query == nil,
            components.fragment == nil,
            components.path.isEmpty || components.path == "/"
        else {
            throw ClavironEndpointError.invalidHTTPSAddress(serverAddress)
        }

        let port = components.port ?? 443
        guard (1 ... 65_535).contains(port) else {
            throw ClavironEndpointError.invalidPort(port)
        }

        self.host = host
        self.port = port
        self.credentials = credentials
    }
}

public enum ClavironEndpointError: Error, Equatable, LocalizedError, Sendable {
    case invalidHTTPSAddress(String)
    case invalidPort(Int)

    public var errorDescription: String? {
        switch self {
        case let .invalidHTTPSAddress(address):
            "Claviron server address must be an HTTPS origin without a path: \(address)"
        case let .invalidPort(port):
            "Claviron server port is outside the valid range: \(port)"
        }
    }
}
