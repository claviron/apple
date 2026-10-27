import Foundation
import Testing
@testable import ClavironControlPlane

@Suite("Claviron endpoint")
struct ClavironEndpointTests {
    @Test("HTTPS origins map to gRPC host and port")
    func httpsOriginMapsToHostAndPort() throws {
        let endpoint = try ClavironEndpoint(
            serverAddress: "https://control.example.com:7443/",
            credentials: .fixture
        )

        #expect(endpoint.host == "control.example.com")
        #expect(endpoint.port == 7_443)
    }

    @Test("HTTPS defaults to port 443")
    func httpsDefaultsToPort443() throws {
        let endpoint = try ClavironEndpoint(
            serverAddress: "https://control.example.com",
            credentials: .fixture
        )

        #expect(endpoint.port == 443)
    }

    @Test(
        "Non-origin server addresses are rejected",
        arguments: [
            "http://control.example.com:7443",
            "https://user@control.example.com:7443",
            "https://control.example.com:7443/control",
            "https://control.example.com:7443?mode=grpc",
            "https://control.example.com:7443#control",
        ]
    )
    func nonOriginAddressesAreRejected(address: String) {
        #expect(throws: ClavironEndpointError.invalidHTTPSAddress(address)) {
            try ClavironEndpoint(
                serverAddress: address,
                credentials: .fixture
            )
        }
    }

    @Test(
        "Ports outside the TCP range are rejected",
        arguments: [0, 65_536, 99_999]
    )
    func invalidPortsAreRejected(port: Int) {
        #expect(throws: ClavironEndpointError.invalidPort(port)) {
            try ClavironEndpoint(
                serverAddress: "https://control.example.com:\(port)",
                credentials: .fixture
            )
        }
    }
}

private extension ClavironTLSCredentials {
    static let fixture = ClavironTLSCredentials(
        certificateAuthorityFile: URL(filePath: "/credentials/ca.pem"),
        clientCertificateFile: URL(filePath: "/credentials/client.pem"),
        clientPrivateKeyFile: URL(filePath: "/credentials/client-key.pem")
    )
}
