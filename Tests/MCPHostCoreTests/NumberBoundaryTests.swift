@testable import MCPHostCore
import Testing

/// Echoes an integer and a decimal, so tests can see what survives the argument boundary.
@Schemable
@MCPTool(title: "Echo numbers", readOnly: true, destructive: false, idempotent: true, openWorld: false)
struct EchoNumbers {
    /// An integer to echo back unchanged.
    let count: Int
    /// A decimal number to echo back unchanged.
    let ratio: Double

    func call(context: ToolContext) async -> EchoedNumbers {
        EchoedNumbers(count: count, ratio: ratio)
    }
}

/// The numbers as the tool received them.
@Schemable
@MCPSchema
struct EchoedNumbers: Encodable {
    /// The integer received.
    let count: Int
    /// The decimal received.
    let ratio: Double
}

@Suite struct NumberBoundaryTests {
    let tool = try! ToolRegistry([EchoNumbers.self]).tool(named: "echo_numbers")!
    let context = ToolContext(caller: CallerIdentity("codex")!, revision: .v2026_07_28)

    func call(_ arguments: String) async throws -> ToolCallOutcome {
        await tool.invoke(try JSONValue.parse(arguments), context)
    }

    @Test(arguments: ["9007199254740993", "9223372036854775807", "-9223372036854775808"])
    func integersBeyondDoublePrecisionRoundTripExactly(_ literal: String) async throws {
        guard case .success(let structured) = try await call(#"{"count": \#(literal), "ratio": 0.5}"#) else {
            Issue.record("expected success"); return
        }
        #expect(try structured.serialized().contains("\"count\":\(literal)"))
    }

    @Test func integralDecimalIsAcceptedAsInteger() async throws {
        // JSON Schema treats 3.0 as an integer; the tool should receive 3.
        guard case .success(let structured) = try await call(#"{"count": 3.0, "ratio": 1}"#) else {
            Issue.record("expected success"); return
        }
        #expect(try structured.serialized().contains("\"count\":3"))
    }
}
