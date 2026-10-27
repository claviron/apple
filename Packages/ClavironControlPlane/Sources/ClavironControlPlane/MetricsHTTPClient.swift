import Foundation
import NIOCore
import NIOPosix
import NIOHTTP1
import NIOHTTP2
import NIOSSL

/// HTTP/2 scrapes share the management profile's identity and retain their TLS
/// connection until the owning client disconnects. There is no background loop.
actor MetricsHTTPClient {
    private struct Connection: Sendable {
        let channel: any Channel
        let multiplexer: HTTP2StreamMultiplexer.SendableView
    }

    private let endpoint: ClavironEndpoint
    private var connection: Connection?
    private var closed = false

    init(endpoint: ClavironEndpoint) { self.endpoint = endpoint }

    deinit { connection?.channel.close(promise: nil) }

    func load() async throws -> RuntimeMemorySnapshot {
        let connection = try await connected()
        let promise = connection.channel.eventLoop.makePromise(of: (any Channel).self)
        connection.multiplexer.createStreamChannel(promise: promise) { channel in
            channel.pipeline.addHandler(HTTP2FramePayloadToHTTP1ClientCodec(httpProtocol: .https))
        }
        let stream = try await promise.futureResult.flatMapThrowing { channel in
            try NIOAsyncChannel<HTTPClientResponsePart, HTTPClientRequestPart>(wrappingChannelSynchronously: channel)
        }.get()
        let host = endpoint.host.contains(":") ? "[\(endpoint.host)]" : endpoint.host
        let authority = endpoint.port == 443 ? host : "\(host):\(endpoint.port)"
        return try await stream.executeThenClose { inbound, outbound in
            let head = HTTPRequestHead(version: .http2, method: .GET, uri: "/metrics", headers: HTTPHeaders([
                ("host", authority), ("accept", "text/plain; version=0.0.4")
            ]))
            try await outbound.write(.head(head))
            try await outbound.write(.end(nil))
            var buffer = ByteBuffer()
            var receivedHead = false
            for try await part in inbound {
                switch part {
                case let .head(head):
                    if head.status.code < 200 { continue }
                    try Self.checkAdmission(head.headers)
                    guard head.status == .ok else {
                        throw ClavironClientFailure(kind: head.status == .notFound ? .protocolMismatch : .serverRejected,
                                                   diagnosticDetail: "The metrics endpoint returned HTTP \(head.status.code).")
                    }
                    receivedHead = true
                case var .body(bytes):
                    buffer.writeBuffer(&bytes)
                case let .end(trailers):
                    if let trailers { try Self.checkAdmission(trailers) }
                    guard receivedHead, let text = buffer.readString(length: buffer.readableBytes) else {
                        throw ClavironClientFailure(kind: .protocolMismatch, diagnosticDetail: "The metrics response was incomplete.")
                    }
                    return try RuntimeMemorySnapshot(prometheus: text)
                }
            }
            throw ClavironClientFailure(kind: .unavailable, diagnosticDetail: "The metrics connection closed before the response completed.")
        }
    }

    func close() async {
        closed = true
        let previous = connection
        connection = nil
        try? await previous?.channel.close().get()
    }

    private func connected() async throws -> Connection {
        guard !closed else { throw CancellationError() }
        if let connection, connection.channel.isActive { return connection }
        let next = try await Self.connect(endpoint)
        guard !closed else {
            try? await next.channel.close().get()
            throw CancellationError()
        }
        if let connection, connection.channel.isActive {
            try? await next.channel.close().get()
            return connection
        }
        connection = next
        return next
    }

    private static func connect(_ endpoint: ClavironEndpoint) async throws -> Connection {
        var tls = TLSConfiguration.makeClientConfiguration()
        tls.certificateVerification = .fullVerification
        tls.trustRoots = .certificates(try NIOSSLCertificate.fromPEMFile(endpoint.credentials.certificateAuthorityFile.path))
        tls.certificateChain = try NIOSSLCertificate.fromPEMFile(endpoint.credentials.clientCertificateFile.path).map { .certificate($0) }
        tls.privateKey = .privateKey(try NIOSSLPrivateKey(file: endpoint.credentials.clientPrivateKeyFile.path, format: .pem))
        tls.applicationProtocols = ["h2"]
        let context = try NIOSSLContext(configuration: tls)
        let hostname = (try? SocketAddress(ipAddress: endpoint.host, port: endpoint.port)) == nil ? endpoint.host : nil
        let channel = try await ClientBootstrap(group: MultiThreadedEventLoopGroup.singleton)
            .channelInitializer { channel in
                do {
                    let handler = try NIOSSLClientHandler(context: context, serverHostname: hostname)
                    return channel.pipeline.addHandler(handler).flatMap {
                        channel.configureHTTP2Pipeline(mode: .client, inboundStreamInitializer: nil).map { _ in () }
                    }
                } catch { return channel.eventLoop.makeFailedFuture(error) }
            }
            .connect(host: endpoint.host, port: endpoint.port).get()
        do {
            let multiplexer = try await channel.pipeline.handler(type: HTTP2StreamMultiplexer.self).map { $0.sendableView }.get()
            return Connection(channel: channel, multiplexer: multiplexer)
        } catch {
            try? await channel.close().get()
            throw error
        }
    }

    private static func checkAdmission(_ headers: HTTPHeaders) throws {
        guard let raw = headers.first(name: "grpc-status"), raw != "0" else { return }
        let message = headers.first(name: "grpc-message")?.removingPercentEncoding ?? "Metrics access was rejected."
        throw ClavironClientFailure(kind: raw == "7" || raw == "16" ? .authenticationRejected : .serverRejected, diagnosticDetail: message)
    }
}
