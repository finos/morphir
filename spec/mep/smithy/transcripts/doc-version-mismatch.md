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
    }
  }
}
```

Verbatim from protocol.md line 819, the protocol version mismatch error:

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

