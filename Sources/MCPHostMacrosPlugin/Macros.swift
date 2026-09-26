import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

/// `@MCPTool(title:readOnly:destructive:idempotent:openWorld:name:)` on a `@Schemable` struct.
///
/// Checks the authoring rules and generates the `MCPTool` conformance's metadata.
public struct MCPToolMacro: ExtensionMacro {
    public static func expansion(
        of node: AttributeSyntax,
        attachedTo declaration: some DeclGroupSyntax,
        providingExtensionsOf type: some TypeSyntaxProtocol,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [ExtensionDeclSyntax] {
        guard let structDecl = declaration.as(StructDeclSyntax.self) else {
            context.diagnose(Diagnostic(node: node, message: AuthoringDiagnostic.notAStruct(macro: "MCPTool")))
            return []
        }
        let checked = StructChecks.check(structDecl, macro: "MCPTool", in: context)
        var ok = checked.ok

        let arguments = node.arguments?.as(LabeledExprListSyntax.self) ?? []
        func argument(_ label: String) -> ExprSyntax? { arguments.first { $0.label?.text == label }?.expression }
        func literalBool(_ label: String) -> Bool? { argument(label)?.as(BooleanLiteralExprSyntax.self).map { $0.literal.text == "true" } }
        func literalString(_ label: String) -> String? {
            argument(label)?.as(StringLiteralExprSyntax.self)?.representedLiteralValue
        }

        if literalBool("readOnly") == true, literalBool("destructive") == true {
            context.diagnose(Diagnostic(node: node, message: AuthoringDiagnostic.readOnlyDestructive))
            ok = false
        }
        if let title = literalString("title"), title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            context.diagnose(Diagnostic(node: node, message: AuthoringDiagnostic.emptyTitle))
            ok = false
        }
        let name = literalString("name") ?? snakeCase(structDecl.name.text)
        if !isValidToolName(name) {
            context.diagnose(Diagnostic(node: node, message: AuthoringDiagnostic.invalidToolName(name)))
            ok = false
        }
        guard ok, let description = structDecl.docComment, let title = argument("title") else { return [] }

        let metadata: DeclSyntax = """
            public static var metadata: MCPHostCore.ToolMetadata {
                MCPHostCore.ToolMetadata(
                    name: \(StringLiteralExprSyntax(content: name)),
                    title: \(title),
                    description: \(StringLiteralExprSyntax(content: description)),
                    annotations: MCPHostCore.ToolAnnotations(
                        readOnly: \(argument("readOnly")!),
                        destructive: \(argument("destructive")!),
                        idempotent: \(argument("idempotent")!),
                        openWorld: \(argument("openWorld")!)
                    )
                )
            }
            """
        let extensionDecl = try ExtensionDeclSyntax("extension \(type.trimmed): MCPHostCore.MCPTool") {
            metadata
            StructChecks.describedFields(checked.properties)
        }
        return [extensionDecl]
    }

    static func snakeCase(_ name: String) -> String {
        var result = ""
        let characters = Array(name)
        for (index, character) in characters.enumerated() {
            if character.isUppercase {
                let previous = index > 0 ? characters[index - 1] : nil
                let next = index + 1 < characters.count ? characters[index + 1] : nil
                if let previous, previous.isLowercase || previous.isNumber || (previous.isUppercase && next?.isLowercase == true) {
                    result.append("_")
                }
                result.append(contentsOf: character.lowercased())
            } else {
                result.append(character)
            }
        }
        return result
    }

    static func isValidToolName(_ name: String) -> Bool {
        (1...64).contains(name.utf8.count)
            && name.utf8.allSatisfy { ($0 >= 0x30 && $0 <= 0x39) || ($0 >= 0x41 && $0 <= 0x5A) || ($0 >= 0x61 && $0 <= 0x7A) || $0 == 0x5F || $0 == 0x2D }
    }
}

/// `@MCPSchema` on a `@Schemable` struct used inside tool inputs or outputs.
public struct MCPSchemaMacro: ExtensionMacro {
    public static func expansion(
        of node: AttributeSyntax,
        attachedTo declaration: some DeclGroupSyntax,
        providingExtensionsOf type: some TypeSyntaxProtocol,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [ExtensionDeclSyntax] {
        guard let structDecl = declaration.as(StructDeclSyntax.self) else {
            context.diagnose(Diagnostic(node: node, message: AuthoringDiagnostic.notAStruct(macro: "MCPSchema")))
            return []
        }
        let (properties, ok) = StructChecks.check(structDecl, macro: "MCPSchema", in: context)
        guard ok else { return [] }
        return [try ExtensionDeclSyntax("extension \(type.trimmed): MCPHostCore.MCPDescribedFields") {
            StructChecks.describedFields(properties)
        }]
    }
}

/// `@MCPEnum` on a `@Schemable` enum of plain values: every case needs a description.
public struct MCPEnumMacro: ExtensionMacro {
    public static func expansion(
        of node: AttributeSyntax,
        attachedTo declaration: some DeclGroupSyntax,
        providingExtensionsOf type: some TypeSyntaxProtocol,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [ExtensionDeclSyntax] {
        guard let enumDecl = declaration.as(EnumDeclSyntax.self) else {
            context.diagnose(Diagnostic(node: node, message: AuthoringDiagnostic.notAnEnum))
            return []
        }
        var ok = true
        if enumDecl.attributes.attribute(named: "Schemable") == nil {
            context.diagnose(Diagnostic(node: enumDecl.name, message: AuthoringDiagnostic.missingSchemable("MCPEnum")))
            ok = false
        }
        var entries: [String] = []
        for caseDecl in enumDecl.memberBlock.members.compactMap({ $0.decl.as(EnumCaseDeclSyntax.self) }) {
            for element in caseDecl.elements {
                let name = element.name.text
                if element.parameterClause != nil {
                    context.diagnose(Diagnostic(node: element, message: AuthoringDiagnostic.caseWithAssociatedValues(name)))
                    ok = false
                    continue
                }
                guard let doc = caseDecl.docComment else {
                    context.diagnose(Diagnostic(node: element, message: AuthoringDiagnostic.missingCaseDoc(name)))
                    ok = false
                    continue
                }
                let value = element.rawValue?.value.as(StringLiteralExprSyntax.self)?.representedLiteralValue ?? name
                entries.append("(value: \(StringLiteralExprSyntax(content: value)), description: \(StringLiteralExprSyntax(content: doc)))")
            }
        }
        guard ok else { return [] }
        let decl: DeclSyntax = "public static var caseDescriptions: [(value: String, description: String)] { [\(raw: entries.joined(separator: ", "))] }"
        return [try ExtensionDeclSyntax("extension \(type.trimmed): MCPHostCore.MCPDescribedEnum") { decl }]
    }
}
