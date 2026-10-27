import ClavironControlPlane
import Foundation

nonisolated struct ManagementField: Identifiable, Equatable, Sendable {
    enum Kind: String, Sendable { case string, integer, number, boolean, object, array }
    let id: String
    let title: String
    let description: String?
    let kind: Kind
    let required: Bool
    let nullable: Bool
    let secret: Bool
    let choices: [ManagementValue]
    let defaultValue: ManagementValue?
}

/// A native renderer for scalar controls and explicit JSON object/array inputs.
/// Layout hints never execute code or fetch schema references.
nonisolated struct ManagementFormFields: Equatable, Sendable {
    let fields: [ManagementField]

    init(_ form: ManagementForm) throws {
        guard form.schema["$schema"]?.string == "https://json-schema.org/draft/2020-12/schema",
              form.schema["type"]?.string == "object",
              let properties = form.schema["properties"]?.object,
              properties.count <= 256 else { throw Self.unsupported }
        let unsupported = ["$ref", "allOf", "anyOf", "oneOf", "if", "then", "else", "dependentSchemas"]
        guard unsupported.allSatisfy({ form.schema[$0] == nil }) else { throw Self.unsupported }
        let controls: [(String, String?)]
        if let layout = form.layout { controls = try Self.controls(layout) }
        else { controls = properties.keys.sorted().map { ($0, nil) } }
        guard Set(controls.map(\.0)).count == controls.count else { throw Self.unsupported }
        let required = form.schema["required"]?.array?.compactMap(\.string) ?? []
        fields = try controls.compactMap { name, label in
            guard let field = properties[name]?.object,
                  unsupported.allSatisfy({ field[$0] == nil }) else { throw Self.unsupported }
            if field["readOnly"]?.bool == true { return nil }
            let choices = field["enum"]?.array ?? []
            let types = field["type"]?.array?.compactMap(\.string)
                ?? field["type"]?.string.map { [$0] } ?? []
            let nonNull = types.filter { $0 != "null" }
            let inferred: String? = choices.first(where: { $0 != .null }).map {
                switch $0 {
                case .string: "string"
                case .integer, .unsigned: "integer"
                case .number: "number"
                case .bool: "boolean"
                case .array: "array"
                case .object: "object"
                case .null: "null"
                }
            }
            guard nonNull.count <= 1, let kind = ManagementField.Kind(rawValue: nonNull.first ?? inferred ?? "") else { throw Self.unsupported }
            guard choices.allSatisfy({ value in
                switch (kind, value) {
                case (_, .null), (.string, .string), (.integer, .integer), (.integer, .unsigned),
                     (.number, .integer), (.number, .unsigned), (.number, .number),
                     (.boolean, .bool), (.object, .object), (.array, .array): true
                default: false
                }
            }) else { throw Self.unsupported }
            return ManagementField(
                id: name,
                title: label ?? field["title"]?.string ?? ManagementResourceName.title(name, fallback: name),
                description: field["description"]?.string,
                kind: kind,
                required: required.contains(name),
                nullable: types.contains("null") || choices.contains(.null),
                secret: field["writeOnly"]?.bool == true || field["format"]?.string == "password",
                choices: choices,
                defaultValue: field["default"]
            )
        }
    }

    private static func controls(_ layout: [String: ManagementValue]) throws -> [(String, String?)] {
        guard layout["rule"] == nil else { throw unsupported }
        switch layout["type"]?.string {
        case "Control":
            guard let scope = layout["scope"]?.string, scope.hasPrefix("#/properties/"),
                  !scope.dropFirst(13).contains("/") else { throw unsupported }
            let name = String(scope.dropFirst(13)).replacingOccurrences(of: "~1", with: "/").replacingOccurrences(of: "~0", with: "~")
            return [(name, layout["label"]?.string)]
        case "VerticalLayout", "HorizontalLayout", "Group":
            guard let elements = layout["elements"]?.array else { throw unsupported }
            return try elements.flatMap { element in
                guard let object = element.object else { throw unsupported }
                return try controls(object)
            }
        default: throw unsupported
        }
    }

    static var unsupported: ManagementClientError {
        ManagementClientError("This form uses a schema or layout that this app cannot edit safely.")
    }
}

nonisolated enum ManagementFieldInput: Hashable, Sendable {
    case omitted, null, text(String)
    init(_ value: ManagementValue?) {
        switch value { case nil: self = .omitted; case .null?: self = .null; case let value?: self = .text(value.text) }
    }
    var text: String { if case let .text(value) = self { value } else { "" } }
}

nonisolated struct ManagementFormDraft: Equatable, Sendable {
    let definition: ManagementFormFields
    let original: [String: ManagementValue]?
    var inputs: [String: ManagementFieldInput]

    init(definition: ManagementFormFields, record: [String: ManagementValue]?) {
        self.definition = definition
        original = record
        inputs = Dictionary(uniqueKeysWithValues: definition.fields.map { field in
            (field.id, ManagementFieldInput(field.secret ? nil : record == nil ? field.defaultValue : record?[field.id]))
        })
    }

    /// Update requests contain only changed top-level fields. Null is explicit;
    /// omission never deletes a property or resends an unchanged secret.
    func document() throws -> [String: ManagementValue] {
        var result: [String: ManagementValue] = [:]
        for field in definition.fields {
            let input = inputs[field.id] ?? .omitted
            let value: ManagementValue
            switch input {
            case .omitted:
                if original == nil && field.required {
                    throw ManagementInputError(path: Self.pointer(field.id), message: "This field is required.")
                }
                continue
            case .null:
                guard field.nullable else { throw ManagementInputError(path: Self.pointer(field.id), message: "This field does not accept null.") }
                value = .null
            case let .text(text):
                do {
                    switch field.kind {
                    case .string: value = .string(text)
                    case .integer:
                        if let integer = Int64(text) { value = .integer(integer) }
                        else if let integer = UInt64(text) { value = .unsigned(integer) }
                        else { throw ManagementClientError("Enter a whole number.") }
                    case .number:
                        let parsed = try ManagementValue.decode(Data(text.utf8))
                        switch parsed { case .integer, .unsigned, .number: value = parsed; default: throw ManagementClientError("Enter a number.") }
                    case .boolean:
                        guard text == "true" || text == "false" else { throw ManagementClientError("Choose true or false.") }
                        value = .bool(text == "true")
                    case .object, .array:
                        let parsed = try ManagementValue.decode(Data(text.utf8))
                        guard field.kind == .object ? parsed.object != nil : parsed.array != nil else { throw ManagementClientError("Enter a JSON value of the declared type.") }
                        value = parsed
                    }
                } catch {
                    throw ManagementInputError(path: Self.pointer(field.id), message: "Enter a valid \(field.kind.rawValue) value.")
                }
            }
            if original == nil || field.secret || original?[field.id] != value { result[field.id] = value }
        }
        return result
    }

    static func pointer(_ field: String) -> String {
        "/" + field.replacingOccurrences(of: "~", with: "~0").replacingOccurrences(of: "/", with: "~1")
    }
}

nonisolated struct ManagementInputError: Error, LocalizedError {
    let path: String
    let message: String
    var errorDescription: String? { message }
}
