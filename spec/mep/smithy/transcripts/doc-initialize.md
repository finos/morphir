---
version: "2.0"
complete: true
---
# protocol.md: initialization

The initialize request and result examples from the Initialization section,
verbatim. Then a ping from the Content-Length framing example.

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

Verbatim from protocol.md line 174, the initialize result:

```jsonrpc extension -> host
{
  "jsonrpc": "2.0",
  "id": 1,
  "result": {
    "protocolVersion": "0.1",
    "extension": {
      "id": "org.finos.morphir.frontend.elm",
      "name": "Morphir Elm frontend",
      "version": "2.100.0"
    },
    "capabilities": {
      "frontend": {
        "languages": [
          {
            "id": "elm",
            "fileExtensions": [".elm"]
          }
        ],
        "irVersions": ["3"],
        "compile": true,
        "incremental": false,
        "fragments": false
      },
      "cancellation": false,
      "progress": false
    }
  }
}
```

Constructed, the initialized notification:

```jsonrpc host -> extension
{"jsonrpc": "2.0", "method": "morphir.initialized"}
```

Verbatim from protocol.md line 74, the JSON body of the framing example:

```jsonrpc host -> extension
{"jsonrpc":"2.0","id":1,"method":"morphir.ping","params":{}}
```

Constructed, the ping result that the Rust SDK sends:

```jsonrpc extension -> host
{"jsonrpc": "2.0", "id": 1, "result": {"ok": true}}
```

Constructed, shutdown:

```jsonrpc host -> extension
{"jsonrpc": "2.0", "id": "shutdown-1", "method": "morphir.shutdown"}
```

Constructed, the shutdown result:

```jsonrpc extension -> host
{"jsonrpc": "2.0", "id": "shutdown-1", "result": {}}
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

The initialize result example has no `extension.types`. The Gleam contract
requires it (`RequiredMember`). This is drift between protocol.md and the
contract, not a validator gap.

```jsonrpc-expect
[
  {"code": "UnknownMember", "entry": 0},
  {"code": "UnknownMember", "entry": 0},
  {"code": "UnknownMember", "entry": 0},
  {"code": "RequiredMember", "entry": 1},
  {"code": "InvalidContext", "entry": 1}
]
```
