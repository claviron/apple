import ClavironControlPlane
import Testing
@testable import Claviron

struct HostingAliasTests {
    @Test
    func addDraftTrimsAndNeedsAHostname() {
        var draft = HostingAliasDraft()
        let editor = HostingAliasEditor.add(siteName: "example.com")

        #expect(draft.action(for: editor) == nil)

        draft.hostname = "  www.example.com "
        #expect(draft.action(for: editor) == .addAlias(
            vhostName: "example.com",
            hostname: "www.example.com"
        ))
    }

    @Test
    func moveDraftNeedsAnotherSite() {
        var draft = HostingAliasDraft()
        let editor = HostingAliasEditor.move(hostname: "www.example.com", from: "example.com")

        #expect(draft.action(for: editor) == nil)
        draft.targetSite = "example.com"
        #expect(draft.action(for: editor) == nil)
        draft.targetSite = "example.org"
        #expect(draft.action(for: editor) == .replaceAlias(
            hostname: "www.example.com",
            vhostName: "example.org"
        ))
    }

    @Test
    func serverRefusalIsAFailureNotAQuietSuccess() {
        let refused = HostingActionOutcome.succeeded(
            .removeAlias(hostname: "www.example.com"),
            .operation(success: false, message: "Alias is pinned")
        )
        #expect(refused.isFailure)
        #expect(refused.summary == "Alias is pinned")

        let accepted = HostingActionOutcome.succeeded(
            .removeAlias(hostname: "www.example.com"),
            .operation(success: true, message: "Removed alias 'www.example.com'")
        )
        #expect(!accepted.isFailure)
        #expect(accepted.summary == "Removed alias 'www.example.com'")
    }
}
