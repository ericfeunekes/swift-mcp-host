import Foundation
import JSONSchema
import MCPHostCore
import MCPHostTesting
import Testing

/// Proves the vendored MCP schemas and the validator used by every contract test are sound:
/// the official examples pass, a broken message fails, and each supported revision is present.
@Suite struct OfficialSchemaTests {
    static let directory = Bundle.module.url(forResource: "mcp-schema", withExtension: nil)!

    @Test func vendoredRevisionsMatchSupportedRevisions() throws {
        let vendored = try FileManager.default.contentsOfDirectory(atPath: Self.directory.path)
            .filter { !$0.hasPrefix(".") && $0 != "LICENSE" && $0 != "SOURCE.md" }
        #expect(Set(vendored) == Set(ProtocolRevision.allCases.map(\.rawValue)))
    }

    @Test(arguments: [ProtocolRevision.v2025_03_26, .v2025_06_18])
    func draftSevenSchemaIsSafeToEvaluateAs2020_12(_ revision: ProtocolRevision) throws {
        let schema = try OfficialSchema(revision: revision, directory: Self.directory)
        #expect(schema.draftSevenOnlyKeywords.isEmpty)
    }

    @Test(arguments: Self.officialExamples())
    func officialExampleValidates(_ example: Example) throws {
        let schema = try OfficialSchema(revision: .v2026_07_28, directory: Self.directory)
        let result = try schema.validate(example.json, as: example.definition)
        #expect(result.isValid, "\(example)")
    }

    @Test func messageViolatingTheSchemaFails() throws {
        let schema = try OfficialSchema(revision: .v2026_07_28, directory: Self.directory)
        let broken = try JSONValue.parse(#"{"content": "not an array", "resultType": "complete"}"#)
        #expect(try !schema.validate(broken, as: "CallToolResult").isValid)
    }

    struct Example: CustomTestStringConvertible, Sendable {
        let definition: String
        let file: String
        let json: JSONValue
        var testDescription: String { "\(definition)/\(file)" }
    }

    static func officialExamples() -> [Example] {
        let root = directory.appending(path: "2026-07-28/examples")
        let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension == "json" } ?? []
        return files.sorted { $0.path < $1.path }.map { url in
            Example(
                definition: url.deletingLastPathComponent().lastPathComponent,
                file: url.lastPathComponent,
                json: try! JSONValue.parse(Data(contentsOf: url))
            )
        }
    }
}
