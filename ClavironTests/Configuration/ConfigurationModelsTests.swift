import Testing
@testable import Claviron

struct ConfigurationModelsTests {
    @Test
    func validConfigurationAllowsServersToShareTLSProfile() throws {
        let configuration = TestConfiguration.valid

        try configuration.validate()

        #expect(configuration.servers.count == 2)
        #expect(Set(configuration.servers.map(\.tlsProfileID)).count == 1)
        #expect(configuration.activeServer?.id == TestConfiguration.primaryServerID)
    }

    @Test
    func serverMustReferenceExistingTLSProfile() {
        var configuration = TestConfiguration.valid
        configuration.servers[0].tlsProfileID = TLSProfileID(rawValue: "missing")

        #expect(throws: ConfigurationValidationError.missingTLSProfile(
            serverID: TestConfiguration.primaryServerID,
            tlsProfileID: TLSProfileID(rawValue: "missing")
        )) {
            try configuration.validate()
        }
    }

    @Test
    func serverAddressMustUseHTTPS() {
        var configuration = TestConfiguration.valid
        configuration.servers[0].address = "http://control.example.com:7443"

        #expect(throws: ConfigurationValidationError.invalidServerAddress(
            TestConfiguration.primaryServerID,
            "http://control.example.com:7443"
        )) {
            try configuration.validate()
        }
    }

    @Test(
        "Server address must be an HTTPS origin",
        arguments: [
            "https://user@control.example.com:7443",
            "https://control.example.com:7443/control",
            "https://control.example.com:7443?mode=grpc",
            "https://control.example.com:7443#control",
            "https://control.example.com:0",
            "https://control.example.com:65536",
        ]
    )
    func serverAddressRejectsNonOriginComponents(_ address: String) {
        var configuration = TestConfiguration.valid
        configuration.servers[0].address = address

        #expect(throws: ConfigurationValidationError.invalidServerAddress(
            TestConfiguration.primaryServerID,
            address
        )) {
            try configuration.validate()
        }
    }

    @Test
    func configurationRequiresExactlyOneKnownActiveServer() {
        var configuration = TestConfiguration.valid
        configuration.activeServerID = nil

        #expect(throws: ConfigurationValidationError.missingActiveServer) {
            try configuration.validate()
        }

        configuration.activeServerID = ServerID(rawValue: "unknown")
        #expect(throws: ConfigurationValidationError.unknownActiveServer(
            ServerID(rawValue: "unknown")
        )) {
            try configuration.validate()
        }
    }

    @Test
    func duplicateIDsAndIncompleteCredentialsAreRejected() {
        var duplicateServer = TestConfiguration.valid
        duplicateServer.servers.append(duplicateServer.servers[0])
        #expect(throws: ConfigurationValidationError.duplicateServerID(
            TestConfiguration.primaryServerID
        )) {
            try duplicateServer.validate()
        }

        var duplicateTLSProfile = TestConfiguration.valid
        duplicateTLSProfile.tlsProfiles.append(duplicateTLSProfile.tlsProfiles[0])
        #expect(throws: ConfigurationValidationError.duplicateTLSProfileID(
            TestConfiguration.sharedTLSProfileID
        )) {
            try duplicateTLSProfile.validate()
        }

        var incompleteTLS = TestConfiguration.valid
        incompleteTLS.tlsProfiles[0].clientPrivateKeyPath = "  "
        #expect(throws: ConfigurationValidationError.emptyCredentialPath(
            profileID: TestConfiguration.sharedTLSProfileID,
            field: .clientPrivateKey
        )) {
            try incompleteTLS.validate()
        }
    }

    @Test
    func identifiersCannotBeUsedAsFileSystemPaths() {
        var unsafeServer = TestConfiguration.valid
        unsafeServer.servers[0] = ServerProfile(
            id: ServerID(rawValue: "../server"),
            name: unsafeServer.servers[0].name,
            address: unsafeServer.servers[0].address,
            tlsProfileID: unsafeServer.servers[0].tlsProfileID
        )
        unsafeServer.activeServerID = ServerID(rawValue: "../server")

        #expect(throws: ConfigurationValidationError.invalidServerID(
            ServerID(rawValue: "../server")
        )) {
            try unsafeServer.validate()
        }

        var unsafeTLSProfile = TestConfiguration.valid
        unsafeTLSProfile.tlsProfiles[0] = TLSProfile(
            id: TLSProfileID(rawValue: ".."),
            name: unsafeTLSProfile.tlsProfiles[0].name,
            caCertificatePath: unsafeTLSProfile.tlsProfiles[0].caCertificatePath,
            clientCertificatePath: unsafeTLSProfile.tlsProfiles[0].clientCertificatePath,
            clientPrivateKeyPath: unsafeTLSProfile.tlsProfiles[0].clientPrivateKeyPath
        )

        #expect(throws: ConfigurationValidationError.invalidTLSProfileID(
            TLSProfileID(rawValue: "..")
        )) {
            try unsafeTLSProfile.validate()
        }
    }
}

enum TestConfiguration {
    static let primaryServerID = ServerID(rawValue: "production")
    static let sharedTLSProfileID = TLSProfileID(rawValue: "operator")

    static var valid: ClientConfiguration {
        ClientConfiguration(
            activeServerID: primaryServerID,
            servers: [
                ServerProfile(
                    id: primaryServerID,
                    name: "Production",
                    address: "https://control.example.com:7443",
                    tlsProfileID: sharedTLSProfileID
                ),
                ServerProfile(
                    id: ServerID(rawValue: "staging"),
                    name: "Staging",
                    address: "https://staging.example.com:7443",
                    tlsProfileID: sharedTLSProfileID
                ),
            ],
            tlsProfiles: [
                TLSProfile(
                    id: sharedTLSProfileID,
                    name: "Operator",
                    caCertificatePath: "credentials/operator/ca.pem",
                    clientCertificatePath: "credentials/operator/client.pem",
                    clientPrivateKeyPath: "credentials/operator/client-key.pem"
                ),
            ]
        )
    }
}
