@testable import MCPHostCore
import OrderedCollections
import Testing

@Suite struct ToolRegistryTests {
    let registry = try! ToolRegistry([ReadMessages.self, WhoAmI.self])
    let context = ToolContext(caller: CallerIdentity("codex")!, revision: .v2026_07_28)

    func object(_ value: JSONValue?) -> OrderedDictionary<String, JSONValue> {
        guard case .object(let object)? = value else { Issue.record("expected an object, got \(String(describing: value))"); return [:] }
        return object
    }

    func call(_ arguments: String) async throws -> ToolCallOutcome {
        await registry.tool(named: "read_messages")!.invoke(try JSONValue.parse(arguments), context)
    }

    @Test func toolsListInRegistrationOrder() {
        #expect(registry.tools.map(\.metadata.name) == ["read_messages", "who_am_i"])
    }

    @Test func inputSchemaFollowsThePortableProfile() throws {
        let schema = object(registry.tool(named: "read_messages")!.inputSchema)
        #expect(schema["additionalProperties"] == false)
        #expect(schema["required"] == ["chatID"], "properties with defaults and optionals are not required")
        let order = object(object(schema["properties"])["order"])
        #expect(order["description"] == .string("Reading order.\n\nAllowed values:\n- `newest`: Most recent message first.\n- `oldest`: Earliest message first."))
        let text = try JSONValue.object(schema).serialized()
        for keyword in SchemaPreparation.forbiddenKeywords { #expect(!text.contains("\"\(keyword)\"")) }
    }

    @Test func noInputToolUsesTheRecommendedEmptySchema() {
        #expect(registry.tool(named: "who_am_i")!.inputSchema == ["type": "object", "additionalProperties": false])
    }

    @Test func outputSchemaChecksNestedTypes() {
        let output = object(registry.tool(named: "read_messages")!.outputSchema)
        let items = object(object(object(output["properties"])["messages"])["items"])
        #expect(items["additionalProperties"] == false)
    }

    @Test func validCallAppliesDefaultsAndReturnsStructuredOutput() async throws {
        guard case .success(let structured) = try await call(#"{"chatID": "c1"}"#) else { Issue.record("expected success"); return }
        #expect(structured == ["chatID": "c1", "messages": [["fromMe": true, "text": "m0"], ["fromMe": false, "text": "m1"]]])
    }

    @Test func everyArgumentProblemIsReportedAtOnce() async throws {
        let outcome = try await call(#"{"limt": 5, "limit": 500, "order": "sideways", "contains": 3}"#)
        guard case .invalidArguments(let issues) = outcome else { Issue.record("expected argument errors, got \(outcome)"); return }
        let byPath = Dictionary(uniqueKeysWithValues: issues.map { ($0.path, $0) })
        #expect(Set(byPath.keys) == ["/chatID", "/limt", "/limit", "/order", "/contains"])

        #expect(byPath["/chatID"]?.type == "missing")
        #expect(byPath["/chatID"]?.input == nil)
        #expect(byPath["/chatID"]?.hint == "Add `chatID`. `chatID`: The chat to read, from find_chats.")

        #expect(byPath["/limt"]?.type == "unexpected_property")
        #expect(byPath["/limt"]?.hint?.contains("Did you mean `limit`?") == true)

        #expect(byPath["/limit"]?.type == "out_of_range")
        #expect(byPath["/limit"]?.message == "`limit` must be at most 100.")
        #expect(byPath["/limit"]?.input == 500)
        #expect(byPath["/limit"]?.context == ["maximum": 100.0])

        #expect(byPath["/order"]?.type == "not_in_enum")
        #expect(byPath["/order"]?.context == ["allowed": ["newest", "oldest"]])

        #expect(byPath["/contains"]?.type == "wrong_type")
        #expect(byPath["/contains"]?.message == "`contains` must be a string or null, not an integer.")
    }

    @Test func handlerErrorsCarryCodeMessageAndNextStep() async throws {
        guard case .toolError(let code, let message, let nextStep, _) = try await call(#"{"chatID": "missing"}"#) else {
            Issue.record("expected a tool error"); return
        }
        #expect(code == "chat_not_found")
        #expect(message == "No chat has the chatID `missing`.")
        #expect(nextStep == "Call find_chats and pass one of its chatID values.")
    }

    @Test func contextCarriesCallerAndRevision() async throws {
        let outcome = await registry.tool(named: "who_am_i")!.invoke(.object([:]), context)
        guard case .success(let structured) = outcome else { Issue.record("expected success"); return }
        #expect(structured == ["caller": "codex", "revision": "2026-07-28"])
    }

    @Test func registrationReportsEveryRuleViolation() {
        #expect {
            try ToolRegistry([BrokenTool.self, ShortDescription.self, WhoAmI.self, WhoAmI.self])
        } throws: { error in
            let problems = (error as! ToolRegistrationError).problems
            let expected = [
                "`broken_tool`: `choice` in the input has a fixed set of values; mark its Swift enum with @MCPEnum and document each case.",
                "`broken_tool`: `nested` in the input is an object whose Swift type is not marked @MCPSchema; add `@MCPSchema` so its fields are checked for descriptions.",
                "`broken_tool`: `nested.value` in the input has no description; add a /// comment to the property.",
                "`short_description`: The description is 10 characters; write at least 40 covering what the tool does, when to use it, when not to, and its limits.",
                "Two tools are named `who_am_i`; tool names must be unique.",
            ]
            for problem in expected where !problems.contains(problem) { Issue.record("missing problem: \(problem)\nall: \(problems)") }
            return true
        }
    }
}
