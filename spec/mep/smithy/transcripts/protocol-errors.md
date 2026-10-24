---
version: "2.0"
complete: true
---
# JSON-RPC protocol errors

Constructed negative cases in a ready session: an unknown method, bad
params, a reply with the wrong id and an unsolicited reply. The expected
findings are at the end.

```jsonrpc host -> extension
{"jsonrpc": "2.0", "id": 0, "method": "morphir.initialize", "params": {"protocolVersions": ["0.1"], "host": {"name": "morphir-cli", "version": "0.4.0"}}}
```

```jsonrpc extension -> host
{"jsonrpc": "2.0", "id": 0, "result": {"protocolVersion": "0.1", "extension": {"id": "org.finos.morphir.example", "name": "Morphir example extension", "version": "1.0.0", "types": ["frontend"]}, "capabilities": {"frontend": {"languages": [{"id": "elm", "fileExtensions": [".elm"]}], "irVersions": ["3"], "compile": true, "incremental": false, "fragments": false}}}}
```

```jsonrpc host -> extension
{"jsonrpc": "2.0", "method": "morphir.initialized"}
```

Entry 3, a method that MEP does not have. The extension answers -32601, which is correct:

```jsonrpc host -> extension
{"jsonrpc": "2.0", "id": 1, "method": "morphir.frontend.snippet", "params": {}}
```

```jsonrpc extension -> host
{"jsonrpc": "2.0", "id": 1, "error": {"code": -32601, "message": "Method not found"}}
```

Entry 5, a compile request with no `sources` and a string `typesOnly`. Entry 6, the extension answers with a result instead of -32602:

```jsonrpc host -> extension
{"jsonrpc": "2.0", "id": 2, "method": "morphir.frontend.compile", "params": {"languageId": "elm", "package": {"name": "local/example"}, "options": {"typesOnly": "no", "irVersion": "3"}}}
```

```jsonrpc extension -> host
{"jsonrpc": "2.0", "id": 2, "result": {"success": true}}
```

Entries 7 and 8, a ping and a reply with the wrong id. Entry 9, a reply that answers no request:

```jsonrpc host -> extension
{"jsonrpc": "2.0", "id": 3, "method": "morphir.ping"}
```

```jsonrpc extension -> host
{"jsonrpc": "2.0", "id": 30, "result": {"ok": true}}
```

```jsonrpc extension -> host
{"jsonrpc": "2.0", "id": 99, "result": {"ok": true}}
```

Entries 10 and 11, the late reply to the ping, then exit:

```jsonrpc extension -> host
{"jsonrpc": "2.0", "id": 3, "result": {"ok": true}}
```

```jsonrpc host -> extension
{"jsonrpc": "2.0", "method": "morphir.exit"}
```

Expected findings:

```jsonrpc-expect
[
  {
    "code": "UnknownMethod",
    "entry": 3
  },
  {
    "code": "RequiredMember",
    "entry": 5
  },
  {
    "code": "TypeMismatch",
    "entry": 5
  },
  {
    "code": "InvalidContext",
    "entry": 6
  },
  {
    "code": "UnsolicitedResponse",
    "entry": 8
  },
  {
    "code": "UnsolicitedResponse",
    "entry": 9
  }
]
```
