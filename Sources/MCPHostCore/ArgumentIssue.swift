import OrderedCollections

/// One problem with a tool call's arguments, in the shape agents use to self-correct.
/// See docs/requirements.md#argument-errors.
public struct ArgumentIssue: Sendable, Equatable {
    public let type: String
    /// JSON Pointer to the value, or to where a missing property belongs.
    public let path: String
    public let message: String
    /// The rejected value, bounded in size. Absent for `missing`.
    public let input: JSONValue?
    /// The constraint that failed.
    public let context: JSONValue
    public let hint: String?

    public var jsonValue: JSONValue {
        var object: OrderedDictionary<String, JSONValue> = [
            "type": .string(type), "path": .string(path), "message": .string(message),
        ]
        if let input { object["input"] = input }
        object["context"] = context
        if let hint { object["hint"] = .string(hint) }
        return .object(object)
    }
}

/// Maps validator output against the prepared input schema to argument issues.
enum ArgumentIssueMapper {
    static let inputPreviewBytes = 200

    static func issues(from result: ValidationResult, arguments: JSONValue, schema: JSONValue) -> [ArgumentIssue] {
        var leaves: [ValidationError] = []
        func collect(_ errors: [ValidationError]?) {
            for error in errors ?? [] {
                // `additionalProperties` reports one nested `false`-schema failure per extra key; the
                // mapper lists the extra keys itself, so the keyword is treated as the leaf.
                if let nested = error.errors, !nested.isEmpty, error.keyword != "additionalProperties" {
                    collect(nested)
                } else {
                    leaves.append(error)
                }
            }
        }
        collect(result.errors)
        return leaves.flatMap { issues(for: $0, arguments: arguments, schema: schema) }
    }

    private static func issues(for error: ValidationError, arguments: JSONValue, schema: JSONValue) -> [ArgumentIssue] {
        let instancePath = error.instanceLocation.jsonPointerString
        let instance = arguments.value(at: error.instanceLocation)
        let constraint = schema.value(at: error.keywordLocation) ?? .null
        let node = schema.value(at: JSONPointer(from: parent(of: error.keywordLocation.jsonPointerString))) ?? .null
        let field = display(instancePath)

        func issue(_ type: String, _ message: String, context: JSONValue, hint: String? = nil) -> ArgumentIssue {
            ArgumentIssue(type: type, path: instancePath, message: message, input: instance.map(preview), context: context, hint: hint)
        }

        switch error.keyword {
        case "required":
            guard case .array(let names) = constraint, case .object(let present)? = instance else { return [] }
            return names.compactMap { name -> ArgumentIssue? in
                guard case .string(let name) = name, present[name] == nil else { return nil }
                let path = instancePath + "/" + escape(name)
                let description = node.property(name)?.descriptionText.map { " \(display(path)): \(firstLine($0))" } ?? ""
                return ArgumentIssue(
                    type: "missing", path: path, message: "\(display(path)) is required.", input: nil,
                    context: .object([:]), hint: "Add \(display(path)).\(description)")
            }
        case "additionalProperties":
            guard case .object(let present)? = instance else { return [] }
            let allowed = node.propertyNames
            return present.keys.filter { !allowed.contains($0) }.map { key in
                let path = instancePath + "/" + escape(key)
                let suggestion = closest(to: key, in: allowed).map { " Did you mean `\($0)`?" } ?? ""
                return ArgumentIssue(
                    type: "unexpected_property", path: path, message: "\(display(path)) is not an argument of this tool.",
                    input: present[key].map(preview), context: .object(["allowed": .array(allowed.map(JSONValue.string))]),
                    hint: "Remove \(display(path)).\(suggestion) Allowed: \(allowed.map { "`\($0)`" }.joined(separator: ", ")).")
            }
        case "type":
            return [issue("wrong_type", "\(field) must be \(typeName(constraint)), not \(typeName(instance)).", context: .object(["expected": constraint]))]
        case "enum", "const":
            let allowed: [JSONValue] = if case .array(let values) = constraint { values } else { [constraint] }
            let list = allowed.map { (try? $0.serialized()) ?? "\($0)" }.joined(separator: ", ")
            return [issue("not_in_enum", "\(field) must be one of \(list).", context: .object(["allowed": .array(allowed)]), hint: "Use one of \(list); the field description explains each value.")]
        case "minimum", "exclusiveMinimum", "maximum", "exclusiveMaximum", "multipleOf":
            let phrase = [
                "minimum": "at least", "exclusiveMinimum": "greater than", "maximum": "at most",
                "exclusiveMaximum": "less than", "multipleOf": "a multiple of",
            ][error.keyword]!
            return [issue("out_of_range", "\(field) must be \(phrase) \(number(constraint)).", context: .object([error.keyword: constraint]))]
        case "minLength":
            return [issue("too_short", "\(field) must have at least \(number(constraint)) characters.", context: .object([error.keyword: constraint]))]
        case "maxLength":
            return [issue("too_long", "\(field) must have at most \(number(constraint)) characters.", context: .object([error.keyword: constraint]))]
        case "pattern":
            return [issue("pattern_mismatch", "\(field) must match the pattern \(number(constraint)).", context: .object([error.keyword: constraint]))]
        case "format":
            return [issue("invalid_format", "\(field) must be a valid \(number(constraint)).", context: .object([error.keyword: constraint]))]
        case "minItems":
            return [issue("too_few_items", "\(field) must have at least \(number(constraint)) items.", context: .object([error.keyword: constraint]))]
        case "maxItems":
            return [issue("too_many_items", "\(field) must have at most \(number(constraint)) items.", context: .object([error.keyword: constraint]))]
        default:
            return [issue("invalid_value", "\(field): \(error.message)", context: .object([error.keyword: constraint]))]
        }
    }

    /// Parse failures after schema validation passed, such as an integer too large for Swift `Int`.
    static func issues(from parseIssues: [ParseIssue]) -> [ArgumentIssue] {
        parseIssues.map {
            ArgumentIssue(type: "invalid_value", path: "", message: $0.description, input: nil, context: .object([:]), hint: nil)
        }
    }

    static func preview(_ value: JSONValue) -> JSONValue {
        guard let text = try? value.serialized(), text.utf8.count > inputPreviewBytes else { return value }
        return .string(String(text.prefix(inputPreviewBytes)) + "…")
    }

    static func display(_ pointer: String) -> String {
        let tokens = pointer.split(separator: "/", omittingEmptySubsequences: false).dropFirst()
            .map { $0.replacing("~1", with: "/").replacing("~0", with: "~") }
        guard !tokens.isEmpty else { return "The arguments" }
        let text = tokens.reduce(into: "") { result, token in
            if Int(token) != nil { result += "[\(token)]" } else { result += result.isEmpty ? token : ".\(token)" }
        }
        return "`\(text)`"
    }

    private static func parent(of pointer: String) -> String {
        guard let slash = pointer.lastIndex(of: "/") else { return "" }
        return String(pointer[..<slash])
    }

    private static func escape(_ token: String) -> String {
        token.replacing("~", with: "~0").replacing("/", with: "~1")
    }

    private static func firstLine(_ text: String) -> String {
        String(text.split(separator: "\n", maxSplits: 1).first ?? "")
    }

    private static func number(_ value: JSONValue) -> String {
        switch value {
        case .numberLiteral(let number):
            if let integer = Int(number.rawValue) { String(integer) }
            else if let double = Double(number.rawValue), double == double.rounded(), abs(double) < 1e15 { String(Int(double)) }
            else { number.rawValue }
        case .string(let text): "`\(text)`"
        default: (try? value.serialized()) ?? "\(value)"
        }
    }

    private static func typeName(_ value: JSONValue?) -> String {
        switch value {
        case .string(let name)?: article(name)
        case .array(let names)?: names.map { typeName($0) }.joined(separator: " or ")
        case .numberLiteral(let number)?: number.isInteger ? "an integer" : "a number"
        case .object?: "an object"
        case .boolean?: "a boolean"
        case .null?: "null"
        case nil: "missing"
        }
    }

    private static func article(_ name: String) -> String {
        name == "null" ? "null" : (name.first.map { "aeiou".contains($0) } == true ? "an \(name)" : "a \(name)")
    }

    private static func closest(to key: String, in candidates: [String]) -> String? {
        candidates
            .map { ($0, distance(key.lowercased(), $0.lowercased())) }
            .filter { $0.1 <= max(1, key.count / 3) }
            .min { $0.1 < $1.1 }?.0
    }

    private static func distance(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var row = Array(0...b.count)
        for i in 1...a.count {
            var previous = row[0]
            row[0] = i
            for j in 1...b.count {
                let current = row[j]
                row[j] = a[i - 1] == b[j - 1] ? previous : Swift.min(previous, row[j], row[j - 1]) + 1
                previous = current
            }
        }
        return row[b.count]
    }
}

extension JSONValue {
    func property(_ name: String) -> JSONValue? {
        guard case .object(let object) = self, case .object(let properties)? = object["properties"] else { return nil }
        return properties[name]
    }

    var propertyNames: [String] {
        guard case .object(let object) = self, case .object(let properties)? = object["properties"] else { return [] }
        return Array(properties.keys)
    }
}
