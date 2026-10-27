// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "ClavironControlPlane",
    platforms: [
        .macOS(.v26),
        .iOS(.v26),
    ],
    products: [
        .library(
            name: "ClavironControlPlane",
            targets: ["ClavironControlPlane"]
        ),
    ],
    dependencies: [
        .package(
            url: "https://github.com/grpc/grpc-swift-2.git",
            exact: "2.4.3"
        ),
        .package(
            url: "https://github.com/grpc/grpc-swift-nio-transport.git",
            exact: "2.9.2"
        ),
        .package(
            url: "https://github.com/grpc/grpc-swift-protobuf.git",
            exact: "2.4.1"
        ),
        .package(
            url: "https://github.com/apple/swift-protobuf.git",
            exact: "1.38.1"
        ),
        .package(
            url: "https://github.com/apple/swift-nio-ssl.git",
            exact: "2.37.4"
        ),
        .package(url: "https://github.com/apple/swift-nio.git", exact: "2.102.0"),
        .package(url: "https://github.com/apple/swift-nio-http2.git", exact: "1.46.0"),
    ],
    targets: [
        .target(
            name: "ClavironControlPlane",
            dependencies: [
                .product(name: "GRPCCore", package: "grpc-swift-2"),
                .product(
                    name: "GRPCNIOTransportHTTP2Posix",
                    package: "grpc-swift-nio-transport"
                ),
                .product(name: "GRPCProtobuf", package: "grpc-swift-protobuf"),
                .product(name: "NIOSSL", package: "swift-nio-ssl"),
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOPosix", package: "swift-nio"),
                .product(name: "NIOHTTP1", package: "swift-nio"),
                .product(name: "NIOHTTP2", package: "swift-nio-http2"),
                .product(name: "SwiftProtobuf", package: "swift-protobuf"),
            ]
        ),
        .testTarget(
            name: "ClavironControlPlaneTests",
            dependencies: [
                "ClavironControlPlane",
                .product(name: "GRPCCore", package: "grpc-swift-2"),
                .product(name: "NIOSSL", package: "swift-nio-ssl"),
            ]
        ),
    ]
)
