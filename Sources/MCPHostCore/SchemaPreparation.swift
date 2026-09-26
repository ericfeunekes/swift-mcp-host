import OrderedCollections

/// Turns a generated schema into the schema agents see, enforcing the portable profile and
/// description rules. Every problem is collected so registration reports them all at once.
/// See docs/requirements.md#schemas.
struct SchemaPreparation {
    private(set) var problems: [String] = []

    /// Keywords outside the portable profile. Composition keywords break OpenAI strict mode
    /// and known client validators.
    static let forbiddenKeywords = ["allOf", "oneOf", "not", "if", "then", "else", "dependentRequired", "dependentSchemas"]

    mutating func record(_ problem: String) { problems.append(problem) }

    mutating func prepare(root: JSONValue, type: any MCPDescribedFields.Type, role: String) -> JSONValue {
        guard case .object(let object) = root, object["type"] == .string("object") else {
            problems.append("The \(role) schema must be a JSON object schema; declare the \(role) as a struct.")
            return root
        }
        return prepare(.object(object), type: type, path: [], role: role)
    }

    private mutating func prepare(_ node: JSONValue, type: Any.Type?, path: [String], role: String) -> JSONValue {
        guard case .object(var object) = node else { return node }
        let location = path.isEmpty ? "the \(role)" : "`\(path.joined(separator: "."))` in the \(role)"

        for keyword in Self.forbiddenKeywords where object[keyword] != nil {
            problems.append("\(location) uses `\(keyword)`, which is outside the portable schema profile. Use a plain struct, enum or optional instead.")
        }
        if case .string(let reference)? = object["$ref"], !reference.hasPrefix("#") {
            problems.append("\(location) references a remote schema (`\(reference)`); remote references are not allowed.")
        }

        if case .object(let properties)? = object["properties"] {
            let fields = (type as? any MCPDescribedFields.Type)?.describedFields
            if fields == nil {
                problems.append("\(location) is an object whose Swift type is not marked @MCPSchema; add `@MCPSchema` so its fields are checked for descriptions.")
            }
            var prepared = properties
            for (key, property) in properties {
                if property.descriptionText == nil {
                    problems.append("`\((path + [key]).joined(separator: "."))` in the \(role) has no description; add a /// comment to the property.")
                }
                let childType = fields?.first { $0.name == key }?.type
                prepared[key] = prepare(property, type: childType, path: path + [key], role: role)
            }
            object["properties"] = .object(prepared)
            if case .array(let required)? = object["required"] {
                let defaulted = Set(properties.filter { $0.value.hasDefault }.map(\.key))
                let remaining = required.filter { if case .string(let name) = $0 { !defaulted.contains(name) } else { true } }
                object["required"] = remaining.isEmpty ? nil : .array(remaining)
            }
        }

        if object.isObjectSchema {
            if let existing = object["additionalProperties"], existing != .boolean(false) {
                problems.append("\(location) allows arbitrary keys (a dictionary); the portable profile needs named fields. Use a struct or an array of structs.")
            }
            object["additionalProperties"] = .boolean(false)
        }

        if let items = object["items"] {
            object["items"] = prepare(items, type: type, path: path + ["[]"], role: role)
        }

        if case .array(let values)? = object["enum"] {
            if let described = type as? any MCPDescribedEnum.Type {
                let cases = described.caseDescriptions
                let declared = Set(cases.map(\.value))
                let emitted = Set(values.compactMap { if case .string(let value) = $0 { value } else { nil } })
                if declared != emitted {
                    problems.append("\(location) allows \(emitted.sorted()) but its @MCPEnum describes \(declared.sorted()).")
                }
                let list = cases.map { "- `\($0.value)`: \($0.description)" }.joined(separator: "\n")
                let base = JSONValue.object(object).descriptionText.map { $0 + "\n\n" } ?? ""
                object["description"] = .string(base + "Allowed values:\n" + list)
            } else {
                problems.append("\(location) has a fixed set of values; mark its Swift enum with @MCPEnum and document each case.")
            }
        }
        return .object(object)
    }
}

extension JSONValue {
    var descriptionText: String? {
        guard case .object(let object) = self, case .string(let text)? = object["description"],
              !text.allSatisfy(\.isWhitespace)
        else { return nil }
        return text
    }

    var hasDefault: Bool {
        if case .object(let object) = self { object["default"] != nil } else { false }
    }
}

extension OrderedDictionary<String, JSONValue> {
    var isObjectSchema: Bool {
        switch self["type"] {
        case .string("object"): true
        case .array(let types): types.contains(.string("object"))
        default: self["properties"] != nil
        }
    }
}
