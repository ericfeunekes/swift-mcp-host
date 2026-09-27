# Client handshake fixtures

Requests real clients sent to a synthetic capture server on 2026-09-27, reduced to the JSON-RPC body and the protocol-relevant headers. Local paths, host names and build hashes were removed; tool names and arguments are synthetic.

File names give the client and version, the transport, what the capture server offered (`dual` answered `server/discover` and 2026-07-28 requests; `legacy` answered only `initialize`-based revisions), and the request's order.

The server must accept every request here and answer it according to [requirements](../../../../docs/requirements.md#selecting-the-revision). Add a fixture when a new client or client version is surveyed; keep values synthetic.
