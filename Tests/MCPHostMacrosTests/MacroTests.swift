import MCPHostMacrosPlugin
import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import XCTest

final class MCPToolMacroTests: XCTestCase {
    let macros: [String: any Macro.Type] = ["MCPTool": MCPToolMacro.self, "MCPSchema": MCPSchemaMacro.self, "MCPEnum": MCPEnumMacro.self]

    func testDocumentedToolExpandsToMetadata() {
        assertMacroExpansion(
            """
            /// Read recent messages.
            @Schemable
            @MCPTool(title: "Read messages", readOnly: true, destructive: false, idempotent: true, openWorld: false)
            struct ReadMessages {
                /// The chat to read.
                let chatID: String
                /// Filter.
                let tags: [Tag]?
            }
            """,
            expandedSource: """
            /// Read recent messages.
            @Schemable
            struct ReadMessages {
                /// The chat to read.
                let chatID: String
                /// Filter.
                let tags: [Tag]?
            }

            extension ReadMessages: MCPHostCore.MCPTool {
                public static var metadata: MCPHostCore.ToolMetadata {
                    MCPHostCore.ToolMetadata(
                        name: "read_messages",
                        title: "Read messages",
                        description: "Read recent messages.",
                        annotations: MCPHostCore.ToolAnnotations(
                            readOnly: true,
                            destructive: false,
                            idempotent: true,
                            openWorld: false
                        )
                    )
                }
                public static var describedFields: [MCPHostCore.DescribedField] {
                    [MCPHostCore.DescribedField(name: "chatID", type: (String).self), MCPHostCore.DescribedField(name: "tags", type: (Tag).self)]
                }
            }
            """,
            macros: macros
        )
    }

    func testMissingDocsAndSchemableAreAllReported() {
        assertMacroExpansion(
            """
            @MCPTool(title: "Read", readOnly: true, destructive: false, idempotent: true, openWorld: false)
            struct ReadMessages {
                let chatID: String
            }
            """,
            expandedSource: """
            struct ReadMessages {
                let chatID: String
            }
            """,
            diagnostics: [
                DiagnosticSpec(message: "A tool needs a /// doc comment: what it does, when to use it, when not to, and its limits. It becomes the tool description agents read.", line: 2, column: 8),
                DiagnosticSpec(message: "@MCPTool also needs @Schemable on the same declaration; it generates the schema this macro checks.", line: 2, column: 8),
                DiagnosticSpec(message: "Property 'chatID' needs a /// doc comment. It becomes the field description agents read.", line: 3, column: 5),
            ],
            macros: macros
        )
    }

    func testReadOnlyDestructiveAndBadNameAreRejected() {
        assertMacroExpansion(
            """
            /// Does things.
            @Schemable
            @MCPTool(title: "X", readOnly: true, destructive: true, idempotent: true, openWorld: false, name: "bad name")
            struct Thing {}
            """,
            expandedSource: """
            /// Does things.
            @Schemable
            struct Thing {}
            """,
            diagnostics: [
                DiagnosticSpec(message: "A read-only tool cannot be destructive; set destructive: false or readOnly: false.", line: 3, column: 1),
                DiagnosticSpec(message: "Tool name 'bad name' must match ^[A-Za-z0-9_-]{1,64}$.", line: 3, column: 1),
            ],
            macros: macros
        )
    }

    func testNonPrimitiveDefaultMustBeStatedInTheSchema() {
        assertMacroExpansion(
            """
            /// Nested.
            @Schemable
            @MCPSchema
            struct Query {
                /// Order.
                var order: Order = .newest
                /// Stated.
                @SchemaOptions(.default("oldest"))
                var other: Order = .oldest
                /// Primitive.
                var limit: Int = 5
            }
            """,
            expandedSource: """
            /// Nested.
            @Schemable
            struct Query {
                /// Order.
                var order: Order = .newest
                /// Stated.
                @SchemaOptions(.default("oldest"))
                var other: Order = .oldest
                /// Primitive.
                var limit: Int = 5
            }
            """,
            diagnostics: [
                DiagnosticSpec(message: "Property 'order' has a Swift default the schema cannot show, so agents would treat it as required. Add @SchemaOptions(.default(<JSON value>)) with the same value.", line: 6, column: 5),
            ],
            macros: macros
        )
    }

    func testSchemableKeyStrategyIsRejected() {
        assertMacroExpansion(
            """
            /// Nested.
            @Schemable(keyStrategy: .snakeCase)
            @MCPSchema
            struct Page {
                /// Items.
                let items: [String]
            }
            """,
            expandedSource: """
            /// Nested.
            @Schemable(keyStrategy: .snakeCase)
            struct Page {
                /// Items.
                let items: [String]
            }
            """,
            diagnostics: [
                DiagnosticSpec(message: "@Schemable(keyStrategy:) is not supported with this library; property names are the JSON field names and enums are plain value lists.", line: 2, column: 12),
            ],
            macros: macros
        )
    }

    func testEnumCasesNeedDocsAndPlainValues() {
        assertMacroExpansion(
            """
            @Schemable
            @MCPEnum
            enum Order {
                /// Newest first.
                case newest = "newest-first"
                case oldest
                /// Custom.
                case custom(String)
            }
            """,
            expandedSource: """
            @Schemable
            enum Order {
                /// Newest first.
                case newest = "newest-first"
                case oldest
                /// Custom.
                case custom(String)
            }
            """,
            diagnostics: [
                DiagnosticSpec(message: "Case 'oldest' needs a /// doc comment. Agents see it next to the allowed value.", line: 6, column: 10),
                DiagnosticSpec(message: "Case 'custom' has associated values; @MCPEnum supports cases that are plain values.", line: 8, column: 10),
            ],
            macros: macros
        )
    }

    func testDocumentedEnumListsRawValues() {
        assertMacroExpansion(
            """
            @Schemable
            @MCPEnum
            enum Order: String {
                /// Newest first.
                case newest = "newest-first"
                /// Oldest first.
                case oldest
            }
            """,
            expandedSource: """
            @Schemable
            enum Order: String {
                /// Newest first.
                case newest = "newest-first"
                /// Oldest first.
                case oldest
            }

            extension Order: MCPHostCore.MCPDescribedEnum {
                public static var caseDescriptions: [(value: String, description: String)] {
                    [(value: "newest-first", description: "Newest first."), (value: "oldest", description: "Oldest first.")]
                }
            }
            """,
            macros: macros
        )
    }
}
