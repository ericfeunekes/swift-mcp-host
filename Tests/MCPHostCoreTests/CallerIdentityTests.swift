import MCPHostCore
import Testing

@Suite struct CallerIdentityTests {
    @Test(arguments: ["claude-code", "codex", "chatgpt-tunnel", "muse", "a", String(repeating: "x", count: 32)])
    func acceptsConfiguredLabels(_ label: String) {
        #expect(CallerIdentity(label)?.value == label)
    }

    @Test(arguments: ["", "Claude", "claude code", "muse/", "müse", "tab\t", String(repeating: "x", count: 33)])
    func rejectsLabelsOutsideThePattern(_ label: String) {
        #expect(CallerIdentity(label) == nil)
    }
}
