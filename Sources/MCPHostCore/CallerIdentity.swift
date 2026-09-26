/// The configured client connection a request arrived through, such as `claude-code` or `muse`.
///
/// A label for attribution and per-caller behavior, not authentication: anyone who can
/// reach an endpoint can present any label. Adapters resolve it from configuration the
/// model cannot change. See docs/requirements.md#caller-identity.
public struct CallerIdentity: Hashable, Sendable, CustomStringConvertible {
    public let value: String

    /// Returns `nil` unless `value` matches `^[a-z0-9-]{1,32}$`.
    public init?(_ value: String) {
        guard (1...32).contains(value.utf8.count),
              value.utf8.allSatisfy({ ($0 >= 0x61 && $0 <= 0x7A) || ($0 >= 0x30 && $0 <= 0x39) || $0 == 0x2D })
        else { return nil }
        self.value = value
    }

    public var description: String { value }
}
