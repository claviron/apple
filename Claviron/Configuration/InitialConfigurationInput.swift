import Foundation

nonisolated struct InitialConfigurationInput: Equatable, Sendable {
    var serverName = ""
    var serverAddress = ""

    /// Fold this wizard run into a configuration that already has entries.
    /// The wizard is the one place that adds a server and the credentials it
    /// connects with together, so it is also useful after the first run; the
    /// existing active selection is left alone unless there is none.
    func addingTo(
        _ configuration: ClientConfiguration,
        username: String,
        serverID: ServerID = ServerID(rawValue: UUID().uuidString.lowercased()),
        tlsProfileID: TLSProfileID = TLSProfileID(rawValue: UUID().uuidString.lowercased()),
        credentialPaths: TLSCredentialPaths
    ) throws -> ClientConfiguration {
        var candidate = configuration
        candidate.tlsProfiles.append(
            TLSProfile(
                id: tlsProfileID,
                name: TLSProfile.identityName(username: username, serverName: serverName),
                caCertificatePath: credentialPaths.caCertificatePath,
                clientCertificatePath: credentialPaths.clientCertificatePath,
                clientPrivateKeyPath: credentialPaths.clientPrivateKeyPath,
                username: username
            )
        )
        candidate.servers.append(
            ServerProfile(
                id: serverID,
                name: serverName,
                address: serverAddress,
                tlsProfileID: tlsProfileID
            )
        )
        if candidate.activeServerID == nil {
            candidate.activeServerID = serverID
        }

        try candidate.validate()
        return candidate
    }
}
