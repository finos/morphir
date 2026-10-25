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
    }
  }
}
```

Verbatim from protocol.md line 167, the initialize result:

```jsonrpc extension -> host
{
  "jsonrpc": "2.0",
  "id": 1,
  "result": {
    "protocolVersion": "0.1",
    "extension": {
      "id": "org.finos.morphir.frontend.elm",
      "name": "Morphir Elm frontend",
      "version": "2.100.0",
      "types": ["frontend"]
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

