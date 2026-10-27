import GRPCCore
import NIOSSL
import Testing
@testable import ClavironControlPlane

@Suite("Claviron client failure")
struct ClavironClientFailureTests {
    @Test(
        "RPC failures retain diagnostics and map to a user-facing kind",
        arguments: [
            (RPCError.Code.unauthenticated, ClavironClientFailure.Kind.authenticationRejected),
            (RPCError.Code.permissionDenied, ClavironClientFailure.Kind.authenticationRejected),
            (RPCError.Code.unavailable, ClavironClientFailure.Kind.unavailable),
            (RPCError.Code.deadlineExceeded, ClavironClientFailure.Kind.timedOut),
            (RPCError.Code.cancelled, ClavironClientFailure.Kind.cancelled),
            (RPCError.Code.unimplemented, ClavironClientFailure.Kind.protocolMismatch),
            (RPCError.Code.failedPrecondition, ClavironClientFailure.Kind.serverRejected),
        ]
    )
    func rpcFailuresAreMapped(
        code: RPCError.Code,
        expectedKind: ClavironClientFailure.Kind
    ) {
        let rpcError = RPCError(code: code, message: "diagnostic")
        let failure = DirectClavironClient.map(rpcError)

        #expect(failure.kind == expectedKind)
        #expect(failure.diagnosticDetail.contains("diagnostic"))
        #expect(failure.localizedDescription != failure.diagnosticDetail)
    }

    @Test(
        "TLS trust and handshake failures retain their transport cause",
        arguments: [
            NIOSSLError.unableToValidateCertificate,
            NIOSSLError.noCertificateToValidate,
            NIOSSLError.handshakeFailed(.sslError([])),
        ]
    )
    func tlsHandshakeFailuresAreDistinguished(tlsError: NIOSSLError) {
        let rpcError = RPCError(
            code: .unavailable,
            message: "could not establish connection",
            cause: tlsError
        )
        let failure = DirectClavironClient.map(rpcError)

        #expect(failure.kind == .tlsHandshakeFailed)
        #expect(failure.diagnosticDetail.contains("could not establish connection"))
        #expect(failure.diagnosticDetail.contains(String(describing: tlsError)))
        #expect(failure.localizedDescription == "The secure TLS connection could not be established.")
    }

    @Test("A nested hostname mismatch is distinguished from an unavailable server")
    func hostnameMismatchIsDistinguished() {
        let transportError = RuntimeError(
            code: .transportError,
            message: "transport failed",
            cause: NIOSSLExtraError.failedToValidateHostname
        )
        let rpcError = RPCError(
            code: .unavailable,
            message: "could not establish connection",
            cause: transportError
        )

        #expect(DirectClavironClient.map(rpcError).kind == .tlsHandshakeFailed)
    }
}
