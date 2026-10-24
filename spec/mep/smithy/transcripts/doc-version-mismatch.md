---
version: "2.0"
complete: true
---
# protocol.md: protocol version mismatch

The initialize request and the -32011 error example from the Errors section,
verbatim. A failed initialize opens no session, so the host can only exit.

Verbatim from protocol.md line 138, the initialize request:

```jsonrpc host -> extension
{
  "jsonrpc": "2.0",
  "id": 1,
  "method": "morphir.initialize",
  "params": {
    "protocolVersions": ["0.1"],
    "host": {
      "kind": "cli",
      "name": "morphir-cli",
      "version": "0.1.0"
    },
    "workspace": {
      "rootUri": "file:///work/acme-orders"
    },
    "capabilities": {
      "cancellation": true,
      "progress": true
    },
    "permissions": {
      "workspaceRead": false,
      "workspaceWrite": false,
      "network": false,
      "environment": []
    }
  }
}
```

Verbatim from protocol.md line 825, the protocol version mismatch error:

```jsonrpc extension -> host
{
  "jsonrpc": "2.0",
  "id": 1,
  "error": {
    "code": -32011,
    "message": "No compatible Morphir Extension Protocol version.",
    "data": {
      "hostVersions": ["0.1"],
      "extensionVersions": ["0.2"]
    }
  }
}
```

Constructed, exit:

```jsonrpc host -> extension
{"jsonrpc": "2.0", "method": "morphir.exit"}
```


## Expected findings

The initialize request example sends `workspace`, `capabilities` and
`permissions`. The Gleam contract does not have them. MEP receivers ignore
unknown members, but the validator refuses them (smithy-2qe.34.17). Because
the request is not valid, the checker also expects the reply to be -32602
(`InvalidContext`).

```jsonrpc-expect
[
  {"code": "UnknownMember", "entry": 0},
  {"code": "UnknownMember", "entry": 0},
  {"code": "UnknownMember", "entry": 0},
  {"code": "InvalidContext", "entry": 1}
]
```
