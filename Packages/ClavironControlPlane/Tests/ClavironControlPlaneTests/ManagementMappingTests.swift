import Foundation
import GRPCCore
import Testing
@testable import ClavironControlPlane

struct ManagementMappingTests {
    @Test
    func conflictsAndSchemaChangesAskForReloadWithoutEchoingServerDetails() {
        let error = DirectClavironClient.managementFailure(RPCError(code: .aborted, message: "private backend detail"))
        #expect(error.localizedDescription.contains("Reload"))
        #expect(!error.localizedDescription.contains("private backend detail"))
        let schema = DirectClavironClient.managementFailure(RPCError(code: .failedPrecondition, message: "private backend detail"))
        #expect(schema.localizedDescription.contains("schema changed"))
    }
    @Test
    func recordsPreserveLargeIDsAndRejectMissingIdentity() throws {
        let data = Data("{\"id\":9007199254740993,\"maximum\":18446744073709551615}".utf8)
        let value = try ManagementValue.decode(data)
        #expect(value.object?["id"] == .integer(9_007_199_254_740_993))
        #expect(value.object?["maximum"] == .unsigned(UInt64.max))
        #expect(try ManagementValue.decode(value.encoded()) == value)
        var record = Claviron_Users_ManagedRecord()
        record.key.resource = .user
        record.key.reference = "public-reference"
        record.revision = "v1"
        record.dataJson = data
        #expect(try DirectClavironClient.managedRecord(record).key.reference == "public-reference")
        record.revision = ""
        #expect(throws: (any Error).self) { try DirectClavironClient.managedRecord(record) }
        record.revision = "v1"
        record.dataJson = Data("[]".utf8)
        #expect(throws: (any Error).self) { try DirectClavironClient.managedRecord(record) }
    }

    @Test
    func validationIsNotACommittedMutationAndMissingOutcomeIsInvalid() throws {
        var response = Claviron_Users_RecordMutationResult()
        #expect(throws: (any Error).self) { try DirectClavironClient.managementMutation(response) }
        var failure = Claviron_Management_ValidationFailure()
        var violation = Claviron_Management_FieldViolation()
        violation.path = "/username"
        violation.code = "unique"
        violation.message = "Choose another username."
        failure.violations = [violation]
        response.outcome = .validation(failure)
        #expect(try DirectClavironClient.managementMutation(response) == .validation([
            ManagementViolation(path: "/username", code: "unique", message: "Choose another username."),
        ]))
    }

    @Test
    func paginationRejectsWrongResourceAndDuplicateKeys() throws {
        var response = Claviron_Users_ListRecordsResponse()
        var record = Claviron_Users_ManagedRecord()
        record.key.resource = .role
        record.key.reference = "example"
        record.revision = "revision"
        record.dataJson = Data("{}".utf8)
        response.records = [record]
        let query = ManagementQuery(resource: .user, pageSize: 20)
        #expect(throws: (any Error).self) { try DirectClavironClient.managementPage(response, query: query) }
        record.key.resource = .user
        response.records = [record, record]
        #expect(throws: (any Error).self) { try DirectClavironClient.managementPage(response, query: query) }
    }

    @Test
    func userCertificateUsesUUIDSeparatelyAndVerifiesTheSignedIdentity() throws {
        let reference = "d65fe5f7-856d-4b76-85c0-fc8a6941ee3c"
        let subject = try #require(ClientCertificateIdentity.userSubject(ManagedRecordKey(resource: .user, reference: reference)))
        #expect(subject == "urn:uuid:" + reference)
        #expect(ClientCertificateIdentity.userSubject(ManagedRecordKey(resource: .user, reference: "operator")) == nil)
        #expect(ClientCertificateIdentity.userSubject(ManagedRecordKey(resource: .role, reference: reference)) == nil)
        #expect(ClientCertificateIdentity.subject("00000000-0000-0000-0000-000000000000") == nil)
        let request = LocalCertificateRequest(commonName: "operator", aliases: [], validityDays: 10, kind: .client, caPathLength: nil, issuer: nil, subjectURI: subject)
        let wire = DirectClavironClient.localCertificateMessage(request)
        #expect(wire.commonName == "operator")
        #expect(wire.subjectUri == subject)
        var response = Claviron_Mtls_CertificateInfo()
        response.kind = .client
        #expect(throws: (any Error).self) { try DirectClavironClient.issuedLocalCertificate(response, request: request) }
        do {
            _ = try DirectClavironClient.issuedLocalCertificate(response, request: request)
        } catch let failure as ClavironClientFailure {
            #expect(failure.kind == .certificateIdentityUnconfirmed)
            #expect(failure.localizedDescription.contains("Inspect"))
        }
        response.subjectUris = [subject]
        #expect(try DirectClavironClient.issuedLocalCertificate(response, request: request).subjectURIs == [subject])
    }
}
