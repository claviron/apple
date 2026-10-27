import Testing
@testable import ClavironControlPlane

@Suite("Hosting observation mapping")
struct HostingObservationMappingTests {
    @Test("Vhost, alias, and server facts preserve optional presence")
    func hostingFactsArePreserved() {
        var generated = Claviron_Aliases_HostingVhostInfo()
        generated.vhost.id = 7
        generated.vhost.name = "example.test"
        generated.vhost.enabled = true

        var alias = Claviron_Aliases_AliasInfo()
        alias.id = 8
        alias.hostname = "www.example.test"

        var server = Claviron_Aliases_ServerInfo()
        server.id = 9
        server.name = "edge"
        server.enabled = false
        generated.aliases = [alias]
        generated.servers = [server]

        let hosted = DirectClavironClient.hostedVhostObservation(generated)

        #expect(hosted.vhost == VhostObservation(
            id: 7,
            name: "example.test",
            enabled: true
        ))
        #expect(hosted.aliases == [
            VhostAliasObservation(
                id: 8,
                hostname: "www.example.test",
                enabled: nil
            ),
        ])
        #expect(hosted.servers == [
            HostingServerObservation(id: 9, name: "edge", enabled: false),
        ])
    }

    @Test("Alias writes keep the server's vhost and outcome sentence")
    func aliasReceiptsArePreserved() throws {
        var added = Claviron_Aliases_AliasResponse()
        added.alias.id = 12
        added.alias.hostname = "www.example.test"
        added.vhostName = "example.test"
        #expect(try DirectClavironClient.aliasReceipt(added) == .alias(
            VhostAliasObservation(id: 12, hostname: "www.example.test", enabled: nil),
            vhostName: "example.test"
        ))

        var removed = Claviron_Aliases_OperationResponse()
        removed.success = true
        removed.message = "Removed alias 'www.example.test'"
        #expect(DirectClavironClient.operationReceipt(removed) == .operation(
            success: true,
            message: "Removed alias 'www.example.test'"
        ))
        #expect(DirectClavironClient.operationReceipt(Claviron_Aliases_OperationResponse())
            == .operation(success: false, message: nil))
    }

    @Test("An alias response without an alias is a protocol mismatch")
    func emptyAliasResponseIsRefused() {
        #expect(throws: ClavironClientFailure.self) {
            try DirectClavironClient.aliasReceipt(Claviron_Aliases_AliasResponse())
        }
    }

    @Test("Missing vhost identity and explicit alias false remain distinct")
    func absenceRemainsExplicit() {
        var generated = Claviron_Aliases_HostingVhostInfo()
        var alias = Claviron_Aliases_AliasInfo()
        alias.enabled = false
        generated.aliases = [alias]

        let hosted = DirectClavironClient.hostedVhostObservation(generated)

        #expect(hosted.vhost == nil)
        #expect(hosted.aliases[0].enabled == false)
    }
    @Test("Read-only host definitions and alias restrictions preserve server reasons")
    func readOnlyFactsArePreserved() {
        var generated = Claviron_Aliases_HostingVhostInfo()
        generated.vhost.name = "app.test"
        generated.vhost.readOnly = true
        generated.vhost.readOnlyReason = "Edit the configuration; dynamic aliases may still be added."
        var fixed = Claviron_Aliases_AliasInfo()
        fixed.hostname = "fixed.test"
        fixed.readOnly = true
        fixed.readOnlyReason = "Change the host configuration."
        var dynamic = Claviron_Aliases_AliasInfo()
        dynamic.hostname = "dynamic.test"
        generated.aliases = [fixed, dynamic]

        let hosted = DirectClavironClient.hostedVhostObservation(generated)
        #expect(hosted.vhost?.readOnly == true)
        #expect(hosted.vhost?.readOnlyReason == generated.vhost.readOnlyReason)
        #expect(hosted.aliases[0].readOnly)
        #expect(hosted.aliases[0].readOnlyReason == fixed.readOnlyReason)
        #expect(!hosted.aliases[1].readOnly)
        #expect(hosted.aliases[1].readOnlyReason == nil)
    }

}
