import MCPHostCore

/// Read recent messages from one conversation, newest first. Use after find_chats and pass its
/// chatID; do not pass a person's name.
@Schemable
@MCPTool(title: "Read messages", readOnly: true, destructive: false, idempotent: true, openWorld: false)
struct ReadMessages {
    /// The chat to read, from find_chats.
    let chatID: String
    /// How many messages to return.
    @NumberOptions(.minimum(1), .maximum(100))
    var limit: Int = 25
    /// Reading order.
    @SchemaOptions(.default("newest"))
    var order: Order = .newest
    /// Only messages containing this text.
    let contains: String?

    func call(context: ToolContext) async throws(ReadError) -> MessagePage {
        guard chatID != "missing" else { throw .chatNotFound(chatID) }
        return MessagePage(chatID: chatID, messages: (0..<min(limit, 2)).map { Message(text: "m\($0)", fromMe: $0 == 0) })
    }
}

@Schemable
@MCPEnum
enum Order: String {
    /// Most recent message first.
    case newest
    /// Earliest message first.
    case oldest
}

/// One page of messages.
@Schemable
@MCPSchema
struct MessagePage: Encodable {
    /// The chat that was read.
    let chatID: String
    /// The messages, in the requested order.
    let messages: [Message]
}

/// A message.
@Schemable
@MCPSchema
struct Message: Encodable {
    /// The message text.
    let text: String
    /// Whether the user sent it.
    let fromMe: Bool
}

enum ReadError: ToolError {
    case chatNotFound(String)

    var code: String { "chat_not_found" }
    var message: String {
        switch self { case .chatNotFound(let id): "No chat has the chatID `\(id)`." }
    }
    var nextStep: String { "Call find_chats and pass one of its chatID values." }
}

/// Returns the configured caller identity and revision, so callers can check attribution.
@Schemable
@MCPTool(title: "Who am I", readOnly: true, destructive: false, idempotent: true, openWorld: false)
struct WhoAmI {
    func call(context: ToolContext) async -> Caller {
        Caller(caller: context.caller.value, revision: context.revision.rawValue)
    }
}

/// The caller as the server sees it.
@Schemable
@MCPSchema
struct Caller: Encodable {
    /// The configured caller identity.
    let caller: String
    /// The protocol revision of the request.
    let revision: String
}

// Tools that break runtime rules, used to prove registration rejects them.

@Schemable
enum Undocumented: String { case a, b }

/// Uses an enum without case descriptions and a nested type without @MCPSchema.
@Schemable
@MCPTool(title: "Broken", readOnly: true, destructive: false, idempotent: true, openWorld: false)
struct BrokenTool {
    /// A value from a set nobody described.
    let choice: Undocumented
    /// A nested object that was not checked.
    let nested: Unchecked

    func call(context: ToolContext) async -> Caller { Caller(caller: "", revision: "") }
}

@Schemable
struct Unchecked: Encodable {
    let value: String
}

/// Too short.
@Schemable
@MCPTool(title: "Short", readOnly: true, destructive: false, idempotent: true, openWorld: false)
struct ShortDescription {
    func call(context: ToolContext) async -> Caller { Caller(caller: "", revision: "") }
}
