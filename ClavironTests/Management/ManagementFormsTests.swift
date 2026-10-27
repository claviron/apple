import ClavironControlPlane
import Foundation
import Testing
@testable import Claviron

@MainActor
struct ManagementFormsTests {
    private func form() throws -> ManagementForm {
        let source = """
        {"$schema":"https://json-schema.org/draft/2020-12/schema","type":"object",
         "required":["username"],"properties":{
         "username":{"type":"string"},"locale":{"type":["string","null"]},
         "status":{"type":"integer","enum":[1,-1],"default":1},
         "password":{"type":"string","writeOnly":true}}}
        """
        return ManagementForm(schema: try #require(ManagementValue.decode(Data(source.utf8)).object))
    }

    @Test
    func updatesAreSparseAndDoNotResendSecretsOrDefaults() throws {
        let definition = try ManagementFormFields(form())
        var draft = ManagementFormDraft(definition: definition, record: ["username": .string("operator"), "password": .string("not-a-real-secret")])
        #expect(try draft.document().isEmpty)
        #expect(draft.inputs["password"] == .omitted)
        #expect(draft.inputs["status"] == .omitted)
        draft.inputs["locale"] = .null
        #expect(try draft.document() == ["locale": .null])
        draft.inputs["username"] = .text("renamed")
        #expect(try draft.document() == ["locale": .null, "username": .string("renamed")])
        draft.inputs["username"] = .omitted
        #expect(try draft.document() == ["locale": .null])
    }

    @Test
    func createUsesDeclaredDefaultsButRequiresExplicitRequiredFields() throws {
        var draft = try ManagementFormDraft(definition: ManagementFormFields(form()), record: nil)
        #expect(throws: ManagementInputError.self) { try draft.document() }
        draft.inputs["username"] = .text("operator")
        #expect(try draft.document() == ["username": .string("operator"), "status": .integer(1)])
    }

    @Test
    func layoutOrdersControlsAndRemoteReferencesAreNotResolved() throws {
        var source = try form()
        source = ManagementForm(schema: source.schema, layout: ["type": .string("VerticalLayout"), "elements": .array([
            .object(["type": .string("Control"), "scope": .string("#/properties/status")]),
            .object(["type": .string("Control"), "scope": .string("#/properties/username")]),
        ])])
        #expect(try ManagementFormFields(source).fields.map(\.id) == ["status", "username"])
        var unsupported = source.schema
        unsupported["$ref"] = .string("https://example.invalid/schema")
        #expect(throws: ManagementClientError.self) { try ManagementFormFields(ManagementForm(schema: unsupported)) }
        let condition = ManagementForm(schema: source.schema, layout: ["type": .string("VerticalLayout"), "rule": .object([:]), "elements": .array([])])
        #expect(throws: ManagementClientError.self) { try ManagementFormFields(condition) }
    }

    @Test
    func selectedUserIsBoundByUUIDAndNeverByCN() throws {
        let reference = "d65fe5f7-856d-4b76-85c0-fc8a6941ee3c"
        var draft = LocalCertificateDraft(kind: .client)
        draft.names.commonName = "display-label"
        draft.validityDays = "14"
        draft.clientIdentity = .user
        #expect(draft.action == nil)
        draft.user = ManagedRecord(key: ManagedRecordKey(resource: .user, reference: reference), revision: "v1", values: ["username": .string("operator")])
        #expect(draft.request?.commonName == "display-label")
        #expect(draft.request?.subjectURI == "urn:uuid:" + reference)
        draft.kind = .server
        #expect(draft.request?.subjectURI == nil)
        draft.kind = .client
        draft.clientIdentity = .commonName
        draft.identifier = "invalid identifier"
        #expect(draft.action == nil)
        draft.identifier = reference
        #expect(draft.request?.subjectURI == "urn:uuid:" + reference)
        draft.identifier = ""
        #expect(draft.request?.subjectURI == nil)
    }
}
