/// An MCP protocol revision this library serves.
///
/// Legacy revisions are reached through `initialize`; the modern revision is
/// carried in every request's `_meta`. See docs/requirements.md#protocol-revisions.
public enum ProtocolRevision: String, CaseIterable, Comparable, Sendable {
    case v2025_03_26 = "2025-03-26"
    case v2025_06_18 = "2025-06-18"
    case v2025_11_25 = "2025-11-25"
    case v2026_07_28 = "2026-07-28"

    public enum Era: Sendable {
        /// Handshake-based: `initialize`, then requests under the negotiated revision.
        case legacy
        /// Stateless: every request names its revision and capabilities in `_meta`.
        case modern
    }

    public var era: Era {
        switch self {
        case .v2025_03_26, .v2025_06_18, .v2025_11_25: .legacy
        case .v2026_07_28: .modern
        }
    }

    /// The revision offered when a client's `initialize` names one this library does not serve.
    public static let latestLegacy: ProtocolRevision = .v2025_11_25

    public static func < (lhs: ProtocolRevision, rhs: ProtocolRevision) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}
