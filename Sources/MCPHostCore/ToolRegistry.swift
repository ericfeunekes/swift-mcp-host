import Foundation

/// A tool prepared for serving: its agent-facing definition and a type-erased call path.
public struct RegisteredTool: Sendable {
    public let metadata: ToolMetadata
    /// The input schema agents see, after the portable profile and description rules are applied.
    public let inputSchema: JSONValue
    public let outputSchema: JSONValue
    let invoke: @Sendable (JSONValue, ToolContext) async -> ToolCallOutcome
}

/// What happened when a tool was called. Rendered per protocol revision by the pipeline.
public enum ToolCallOutcome: Sendable {
    case success(structured: JSONValue)
    case invalidArguments([ArgumentIssue])
    case toolError(code: String, message: String, nextStep: String, details: JSONValue?)
    /// A server-side fault: the handler's output did not match its schema or could not be encoded.
    case internalFailure(String)
}

/// Every problem found while registering tools, reported together.
public struct ToolRegistrationError: Error, CustomStringConvertible {
    public let problems: [String]
    public var description: String {
        "Tool registration failed:\n" + problems.map { "- \($0)" }.joined(separator: "\n")
    }
}

/// The server's tools, in registration order.
public struct ToolRegistry: Sendable {
    public let tools: [RegisteredTool]

    public init(_ types: [any MCPTool.Type]) throws(ToolRegistrationError) {
        var problems: [String] = []
        var tools: [RegisteredTool] = []
        var names: Set<String> = []
        for type in types {
            let name = type.metadata.name
            if !names.insert(name).inserted { problems.append("Two tools are named `\(name)`; tool names must be unique.") }
            switch Self.register(type) {
            case .success(let tool): tools.append(tool)
            case .failure(let error): problems += error.problems.map { "`\(name)`: \($0)" }
            }
        }
        guard problems.isEmpty else { throw ToolRegistrationError(problems: problems) }
        self.tools = tools
    }

    public func tool(named name: String) -> RegisteredTool? {
        tools.first { $0.metadata.name == name }
    }

    private static func register<T: MCPTool>(_ type: T.Type) -> Result<RegisteredTool, ToolRegistrationError> {
        let metadata = T.metadata
        var preparation = SchemaPreparation()
        let input = preparation.prepare(root: T.schema.definition().jsonValue, type: T.self, role: "input")
        let output = preparation.prepare(root: T.Output.schema.definition().jsonValue, type: T.Output.self, role: "output")
        if metadata.description.count < ToolRules.minimumDescriptionLength {
            preparation.record("The description is \(metadata.description.count) characters; write at least \(ToolRules.minimumDescriptionLength) covering what the tool does, when to use it, when not to, and its limits.")
        }
        for (role, schema) in [("input", input), ("output", output)] where (try? validator(for: schema)) == nil {
            preparation.record("The prepared \(role) schema is not a valid JSON Schema 2020-12 document.")
        }
        guard preparation.problems.isEmpty else { return .failure(ToolRegistrationError(problems: preparation.problems)) }

        let invoke: @Sendable (JSONValue, ToolContext) async -> ToolCallOutcome = { arguments, context in
            await call(T.self, arguments: arguments, context: context, input: input, output: output)
        }
        return .success(RegisteredTool(metadata: metadata, inputSchema: input, outputSchema: output, invoke: invoke))
    }

    private static func call<T: MCPTool>(
        _ type: T.Type, arguments: JSONValue, context: ToolContext, input: JSONValue, output: JSONValue
    ) async -> ToolCallOutcome {
        let validation = validate(arguments, against: input)
        guard validation.isValid else {
            return .invalidArguments(ArgumentIssueMapper.issues(from: validation, arguments: arguments, schema: input))
        }
        let tool: T
        switch T.schema.parse(Defaults.apply(input, to: arguments)) {
        case .valid(let parsed): tool = parsed
        case .invalid(let issues): return .invalidArguments(ArgumentIssueMapper.issues(from: issues))
        }

        let result: T.Output
        do {
            result = try await tool.call(context: context)
        } catch {
            return .toolError(code: error.code, message: error.message, nextStep: error.nextStep, details: error.details)
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(result), let structured = try? JSONValue.parse(data) else {
            return .internalFailure("The output of `\(T.metadata.name)` could not be encoded as JSON.")
        }
        guard validate(structured, against: output).isValid else {
            return .internalFailure("The output of `\(T.metadata.name)` does not match its output schema.")
        }
        return .success(structured: structured)
    }

    private static func validate(_ instance: JSONValue, against schema: JSONValue) -> ValidationResult {
        // Registration already built a validator from this exact schema, so construction cannot fail.
        // A validator is built per call because `Schema` is not safe to share across concurrent calls.
        try! validator(for: schema).validate(instance, at: JSONPointer())
    }

    private static func validator(for schema: JSONValue) throws -> Schema {
        try Schema(rawSchema: schema, context: .init(dialect: .draft2020_12))
    }
}

/// Author-facing rules the compiler cannot check.
public enum ToolRules {
    /// Short descriptions leave agents guessing when to use a tool. See docs/decisions.md#owner-decisions.
    public static let minimumDescriptionLength = 40
}

/// Fills declared defaults for absent properties, so the parser sees a complete value.
enum Defaults {
    static func apply(_ schema: JSONValue, to value: JSONValue) -> JSONValue {
        switch value {
        case .object(var object):
            guard case .object(let node) = schema, case .object(let properties)? = node["properties"] else { return value }
            for (key, property) in properties {
                if let present = object[key] {
                    object[key] = apply(property, to: present)
                } else if case .object(let propertyNode) = property, let fallback = propertyNode["default"] {
                    object[key] = fallback
                }
            }
            return .object(object)
        case .array(let items):
            guard case .object(let node) = schema, let itemSchema = node["items"] else { return value }
            return .array(items.map { apply(itemSchema, to: $0) })
        default:
            return value
        }
    }
}
