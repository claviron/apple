import Testing
@testable import ClavironControlPlane

@Suite("Generated protocol")
struct GeneratedProtocolTests {
    @Test("The server manager client binding is available")
    func serverManagerClientBindingIsAvailable() {
        #expect(
            Claviron_Server_ServerManager.descriptor.fullyQualifiedService
                == "claviron.server.ServerManager"
        )
    }

    @Test("Optional protobuf fields retain presence")
    func optionalFieldsRetainPresence() {
        var pool = Claviron_Applications_ApplicationPoolStatus()

        #expect(!pool.hasAccepting)
        pool.accepting = false
        #expect(pool.hasAccepting)
        #expect(pool.accepting == false)
        pool.clearAccepting()
        #expect(!pool.hasAccepting)
    }
}
