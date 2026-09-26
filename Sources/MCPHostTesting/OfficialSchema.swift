import Foundation
import JSONSchema
import MCPHostCore

/// Validates JSON against a named definition in an official MCP `schema.json`.
///
/// Used by contract tests to prove emitted messages match the published protocol.
public struct OfficialSchema: Sendable {
    public let revision: ProtocolRevision
    private let document: JSONValue
    private let definitionsKey: String

    /// Loads `<directory>/<revision>/schema.json`.
    ///
    /// 2025-06-18 is published as draft-07 with `definitions`, which the validator does not
    /// implement; it is evaluated as 2020-12. `draftSevenOnlyKeywords` lets a test prove the
    /// document uses no keyword whose meaning differs between the two dialects.
    public init(revision: ProtocolRevision, directory: URL) throws {
        self.revision = revision
        let data = try Data(contentsOf: directory.appending(path: "\(revision.rawValue)/schema.json"))
        guard case .object(var document) = try JSONValue.parse(data) else {
            throw OfficialSchemaError.notAnObject(revision)
        }
        definitionsKey = document["$defs"] != nil ? "$defs" : "definitions"
        document["$schema"] = .string(Dialect.draft2020_12.rawValue)
        self.document = .object(document)
    }

    /// Definition names in this revision's schema.
    public var definitionNames: Set<String> {
        guard case .object(let root) = document, case .object(let definitions)? = root[definitionsKey] else { return [] }
        return Set(definitions.keys)
    }

    /// Validates `instance` against the definition `name`.
    public func validate(_ instance: JSONValue, as name: String) throws -> ValidationResult {
        guard definitionNames.contains(name) else { throw OfficialSchemaError.unknownDefinition(name, revision) }
        guard case .object(var root) = document else { throw OfficialSchemaError.notAnObject(revision) }
        root["$ref"] = .string("#/\(definitionsKey)/\(name)")
        let schema = try Schema(rawSchema: .object(root), context: .init(dialect: .draft2020_12))
        return schema.validate(instance, at: JSONPointer())
    }

    /// Draft-07 keywords whose meaning changed or which were removed in 2020-12, found anywhere in the document.
    public var draftSevenOnlyKeywords: Set<String> {
        var found: Set<String> = []
        func visit(_ value: JSONValue) {
            switch value {
            case .object(let object):
                for (key, child) in object {
                    if key == "additionalItems" || key == "dependencies" { found.insert(key) }
                    if key == "items", case .array = child { found.insert("items (array form)") }
                    visit(child)
                }
            case .array(let array):
                array.forEach(visit)
            default:
                break
            }
        }
        visit(document)
        return found
    }
}

public enum OfficialSchemaError: Error, CustomStringConvertible {
    case notAnObject(ProtocolRevision)
    case unknownDefinition(String, ProtocolRevision)

    public var description: String {
        switch self {
        case .notAnObject(let revision): "schema.json for \(revision.rawValue) is not a JSON object"
        case .unknownDefinition(let name, let revision): "\(name) is not defined in the \(revision.rawValue) schema"
        }
    }
}
