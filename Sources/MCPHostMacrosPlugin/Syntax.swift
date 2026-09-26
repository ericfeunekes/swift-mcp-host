import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxMacros

/// Authoring-rule violations. Each message names what is missing and how to fix it,
/// because the reader is often an agent writing a tool.
enum AuthoringDiagnostic: DiagnosticMessage {
    case notAStruct(macro: String)
    case notAnEnum
    case missingTypeDoc(macro: String)
    case missingPropertyDoc(String)
    case missingCaseDoc(String)
    case missingSchemable(String)
    case unsupportedSchemableArgument(String)
    case unsupportedKeyOption(String)
    case caseWithAssociatedValues(String)
    case invalidToolName(String)
    case defaultNotInSchema(String)
    case readOnlyDestructive
    case emptyTitle

    var message: String {
        switch self {
        case .notAStruct(let macro):
            "@\(macro) applies to a struct."
        case .notAnEnum:
            "@MCPEnum applies to an enum."
        case .missingTypeDoc(let macro):
            macro == "MCPTool"
                ? "A tool needs a /// doc comment: what it does, when to use it, when not to, and its limits. It becomes the tool description agents read."
                : "A type used in tool inputs or outputs needs a /// doc comment describing it."
        case .missingPropertyDoc(let name):
            "Property '\(name)' needs a /// doc comment. It becomes the field description agents read."
        case .missingCaseDoc(let name):
            "Case '\(name)' needs a /// doc comment. Agents see it next to the allowed value."
        case .missingSchemable(let macro):
            "@\(macro) also needs @Schemable on the same declaration; it generates the schema this macro checks."
        case .unsupportedSchemableArgument(let argument):
            "@Schemable(\(argument):) is not supported with this library; property names are the JSON field names and enums are plain value lists."
        case .unsupportedKeyOption(let name):
            "Property '\(name)' renames its JSON key; this library uses property names as field names."
        case .caseWithAssociatedValues(let name):
            "Case '\(name)' has associated values; @MCPEnum supports cases that are plain values."
        case .invalidToolName(let name):
            "Tool name '\(name)' must match ^[A-Za-z0-9_-]{1,64}$."
        case .defaultNotInSchema(let name):
            "Property '\(name)' has a Swift default the schema cannot show, so agents would treat it as required. Add @SchemaOptions(.default(<JSON value>)) with the same value."
        case .readOnlyDestructive:
            "A read-only tool cannot be destructive; set destructive: false or readOnly: false."
        case .emptyTitle:
            "The tool title must not be empty."
        }
    }

    var diagnosticID: MessageID { MessageID(domain: "MCPHost", id: "\(self)") }
    var severity: DiagnosticSeverity { .error }
}


extension SyntaxProtocol {
    /// The `///` or `/** */` comment attached to this declaration, or nil when absent or blank.
    var docComment: String? {
        var lines: [String] = []
        for piece in leadingTrivia {
            switch piece {
            case .docLineComment(let text):
                lines.append(String(text.dropFirst(3)).trimmingCharacters(in: .whitespaces))
            case .docBlockComment(let text):
                lines.append(contentsOf: text.dropFirst(3).dropLast(2).split(separator: "\n").map {
                    $0.trimmingCharacters(in: .whitespaces).trimmingPrefix("*").trimmingCharacters(in: .whitespaces)
                })
            default:
                continue
            }
        }
        let text = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }
}

extension String {
    func trimmingCharacters(in set: Set<Character>) -> String {
        var slice = Substring(self)
        while let first = slice.first, set.contains(first) { slice = slice.dropFirst() }
        while let last = slice.last, set.contains(last) { slice = slice.dropLast() }
        return String(slice)
    }
}

extension Substring {
    func trimmingCharacters(in set: Set<Character>) -> String { String(self).trimmingCharacters(in: set) }
}

extension Set where Element == Character {
    static let whitespaces: Set<Character> = [" ", "\t"]
    static let whitespacesAndNewlines: Set<Character> = [" ", "\t", "\n", "\r"]
}

extension AttributeListSyntax {
    func attribute(named name: String) -> AttributeSyntax? {
        for element in self {
            if case .attribute(let attribute) = element,
               attribute.attributeName.trimmedDescription == name
            {
                return attribute
            }
        }
        return nil
    }
}

/// A stored instance property the schema will contain.
struct StoredProperty {
    let name: String
    let type: TypeSyntax?
    let declaration: VariableDeclSyntax
    let hasInitializer: Bool
}

/// Types whose Swift default swift-json-schema writes into the schema.
let primitiveTypeNames: Set<String> = [
    "String", "Bool", "Double", "Float", "Int", "Int8", "Int16", "Int32", "Int64",
    "UInt", "UInt8", "UInt16", "UInt32", "UInt64",
]

extension MemberBlockSyntax {
    var storedProperties: [StoredProperty] {
        members.compactMap { $0.decl.as(VariableDeclSyntax.self) }.flatMap { variable -> [StoredProperty] in
            let isStatic = variable.modifiers.contains { ["static", "class"].contains($0.name.text) }
            if isStatic || variable.attributes.attribute(named: "ExcludeFromSchema") != nil { return [] }
            return variable.bindings.compactMap { binding in
                guard binding.accessorBlock == nil || binding.hasOnlyObservers,
                      let name = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text
                else { return nil }
                return StoredProperty(
                    name: name, type: binding.typeAnnotation?.type, declaration: variable,
                    hasInitializer: binding.initializer != nil)
            }
        }
    }
}

extension PatternBindingSyntax {
    var hasOnlyObservers: Bool {
        guard case .accessors(let accessors)? = accessorBlock?.accessors else { return false }
        return accessors.allSatisfy { ["willSet", "didSet"].contains($0.accessorSpecifier.text) }
    }
}

extension TypeSyntax {
    /// The element type after removing `?`, `Optional<>` and `[ ]`, used to find nested
    /// schema types and enums at runtime.
    var schemaElementType: TypeSyntax {
        if let optional = self.as(OptionalTypeSyntax.self) { return optional.wrappedType.schemaElementType }
        if let optional = self.as(ImplicitlyUnwrappedOptionalTypeSyntax.self) { return optional.wrappedType.schemaElementType }
        if let array = self.as(ArrayTypeSyntax.self) { return array.element.schemaElementType }
        if let identifier = self.as(IdentifierTypeSyntax.self),
           ["Optional", "Array"].contains(identifier.name.text),
           let argument = identifier.genericArgumentClause?.arguments.first
        {
            #if canImport(SwiftSyntax602)
            if case .type(let type) = argument.argument { return type.schemaElementType }
            return self
            #else
            return argument.argument.schemaElementType
            #endif
        }
        return self
    }
}

/// Shared checks for any struct whose schema agents will read.
enum StructChecks {
    static func check(
        _ structDecl: StructDeclSyntax,
        macro: String,
        in context: some MacroExpansionContext
    ) -> (properties: [StoredProperty], ok: Bool) {
        var ok = true
        func fail(_ node: some SyntaxProtocol, _ diagnostic: AuthoringDiagnostic) {
            context.diagnose(Diagnostic(node: node, message: diagnostic))
            ok = false
        }
        if structDecl.docComment == nil { fail(structDecl.name, .missingTypeDoc(macro: macro)) }
        if let schemable = structDecl.attributes.attribute(named: "Schemable") {
            for argument in schemable.arguments?.as(LabeledExprListSyntax.self) ?? [] {
                if let label = argument.label?.text { fail(argument, .unsupportedSchemableArgument(label)) }
            }
        } else {
            fail(structDecl.name, .missingSchemable(macro))
        }
        let properties = structDecl.memberBlock.storedProperties
        for property in properties {
            if property.declaration.docComment == nil {
                fail(property.declaration, .missingPropertyDoc(property.name))
            }
            let options = property.declaration.attributes.attribute(named: "SchemaOptions")?.arguments?.trimmedDescription ?? ""
            if options.contains(".key(") {
                fail(property.declaration, .unsupportedKeyOption(property.name))
            }
            if property.hasInitializer, let type = property.type?.trimmedDescription,
               !primitiveTypeNames.contains(type), !options.contains(".default(")
            {
                fail(property.declaration, .defaultNotInSchema(property.name))
            }
        }
        return (properties, ok)
    }

    /// `static var describedFields` listing each property's element type for the runtime schema walk.
    static func describedFields(_ properties: [StoredProperty]) -> DeclSyntax {
        let entries = properties.compactMap { property -> String? in
            guard let type = property.type else { return nil }
            return "MCPHostCore.DescribedField(name: \(StringLiteralExprSyntax(content: property.name)), type: (\(type.schemaElementType.trimmed)).self)"
        }
        return "public static var describedFields: [MCPHostCore.DescribedField] { [\(raw: entries.joined(separator: ", "))] }"
    }
}
