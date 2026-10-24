---
version: "2.0"
complete: true
---
# protocol.md: backend generation

The generate request and result, verbatim. The constructed initialize result
contains the backend capability example from the Capability methods section.

Constructed, a conformant initialize request:

```jsonrpc host -> extension
{"jsonrpc": "2.0", "id": 0, "method": "morphir.initialize", "params": {"protocolVersions": ["0.1"], "host": {"kind": "cli", "name": "morphir-cli", "version": "0.4.0"}}}
```

Constructed, an initialize result that advertises the capabilities this transcript uses:

```jsonrpc extension -> host
{"jsonrpc": "2.0", "id": 0, "result": {"protocolVersion": "0.1", "extension": {"id": "org.finos.morphir.example", "name": "Morphir example extension", "version": "1.0.0", "types": ["backend"]}, "capabilities": {"backend": {"targets": ["avro"], "irVersions": ["3", "4"], "generate": true}, "cancellation": false, "progress": false}}}
```

Constructed, the initialized notification:

```jsonrpc host -> extension
{"jsonrpc": "2.0", "method": "morphir.initialized"}
```

Verbatim from protocol.md line 716, the generate request:

```jsonrpc host -> extension
{
  "jsonrpc": "2.0",
  "id": "generate-1",
  "method": "morphir.backend.generate",
  "params": {
    "ir": {},
    "target": "avro",
    "options": {}
  }
}
```

Verbatim from protocol.md line 729, the generate result:

```jsonrpc extension -> host
{
  "jsonrpc": "2.0",
  "id": "generate-1",
  "result": {
    "success": true,
    "artifacts": [
      {
        "path": "generated/Example.scala",
        "content": "package example\n",
        "binary": false
      }
    ],
    "diagnostics": []
  }
}
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

