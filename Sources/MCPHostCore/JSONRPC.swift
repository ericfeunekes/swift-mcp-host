import Foundation
import OrderedCollections

/// A JSON-RPC request id. MCP allows strings and integers; `null` is not a valid request id.
public enum RequestID: Hashable, Sendable {
    case string(String)
    case number(JSONNumberLiteral)

    var jsonValue: JSONValue {
        switch self {
        case .string(let value): .string(value)
        case .number(let value): .numberLiteral(value)
        }
    }
}

/// One message a client sent, after envelope parsing and before revision selection.
enum ClientMessage: Sendable {
    case request(id: RequestID, method: String, params: JSONValue?)
    case notification(method: String, params: JSONValue?)
}

/// The body of a POST or a stream line: one message or, only under 2025-03-26, a batch.
enum ClientBody: Sendable {
    case single(ClientMessage)
    case batch([ClientMessage])
}

/// A JSON-RPC error the server returns. See docs/requirements.md#protocol-errors.
public struct ProtocolError: Error, Sendable, Equatable {
    public let code: Int
    public let message: String
    public let data: JSONValue?

    public init(code: Int, message: String, data: JSONValue? = nil) {
        self.code = code
        self.message = message
        self.data = data
    }

    public static let parseErrorCode = -32700
    public static let invalidRequestCode = -32600
    public static let methodNotFoundCode = -32601
    public static let invalidParamsCode = -32602
    public static let internalErrorCode = -32603
    public static let headerMismatchCode = -32020
    public static let unsupportedProtocolVersionCode = -32022

    public static func parseError(_ message: String) -> Self { .init(code: parseErrorCode, message: message) }
    public static func invalidRequest(_ message: String) -> Self { .init(code: invalidRequestCode, message: message) }
    public static func methodNotFound(_ method: String) -> Self {
        .init(code: methodNotFoundCode, message: "The method `\(method)` is not supported by this server.")
    }
    public static func invalidParams(_ message: String) -> Self { .init(code: invalidParamsCode, message: message) }
    public static func internalError(_ message: String) -> Self { .init(code: internalErrorCode, message: message) }
    public static func headerMismatch(_ message: String) -> Self { .init(code: headerMismatchCode, message: message) }

    var jsonValue: JSONValue {
        var object: OrderedDictionary<String, JSONValue> = ["code": .numberLiteral(JSONNumberLiteral(code)), "message": .string(message)]
        if let data { object["data"] = data }
        return .object(object)
    }
}

enum JSONRPC {
    /// Parses a body into one message or a batch. Client responses are rejected: this server
    /// never sends requests to clients.
    static func parse(_ data: [UInt8]) -> Result<ClientBody, ProtocolError> {
        guard !data.isEmpty else { return .failure(.parseError("The request body is empty; send one JSON-RPC message.")) }
        let value: JSONValue
        do {
            value = try JSONValue.parse(Data(data))
        } catch {
            return .failure(.parseError("The request body is not valid JSON."))
        }
        switch value {
        case .array(let items):
            guard !items.isEmpty else { return .failure(.invalidRequest("An empty batch is not a valid JSON-RPC message.")) }
            var messages: [ClientMessage] = []
            for item in items {
                switch message(item) {
                case .success(let message): messages.append(message)
                case .failure(let error): return .failure(error)
                }
            }
            return .success(.batch(messages))
        default:
            return message(value).map(ClientBody.single)
        }
    }

    private static func message(_ value: JSONValue) -> Result<ClientMessage, ProtocolError> {
        guard case .object(let object) = value else {
            return .failure(.invalidRequest("A JSON-RPC message must be an object."))
        }
        guard object["jsonrpc"] == .string("2.0") else {
            return .failure(.invalidRequest("A JSON-RPC message must have \"jsonrpc\": \"2.0\"."))
        }
        guard case .string(let method)? = object["method"] else {
            if object["result"] != nil || object["error"] != nil {
                return .failure(.invalidRequest("This server sends no requests, so it accepts no JSON-RPC responses."))
            }
            return .failure(.invalidRequest("A JSON-RPC request must have a string \"method\"."))
        }
        let params = object["params"]
        if let params {
            guard case .object = params else { return .failure(.invalidRequest("\"params\" must be an object.")) }
        }
        switch object["id"] {
        case nil:
            return .success(.notification(method: method, params: params))
        case .string(let id)?:
            return .success(.request(id: .string(id), method: method, params: params))
        case .numberLiteral(let id)? where id.isInteger:
            return .success(.request(id: .number(id), method: method, params: params))
        default:
            return .failure(.invalidRequest("A JSON-RPC request id must be a string or an integer."))
        }
    }

    static func response(id: RequestID?, result: JSONValue) -> JSONValue {
        ["jsonrpc": "2.0", "id": id?.jsonValue ?? .null, "result": result]
    }

    static func response(id: RequestID?, error: ProtocolError) -> JSONValue {
        var object: OrderedDictionary<String, JSONValue> = ["jsonrpc": "2.0"]
        // A JSON-RPC error for a message whose id is unknown carries no id (*2026-07-28 streamable-http*).
        if let id { object["id"] = id.jsonValue }
        object["error"] = error.jsonValue
        return .object(object)
    }
}

extension JSONValue {
    subscript(key: String) -> JSONValue? {
        guard case .object(let object) = self else { return nil }
        return object[key]
    }
}
