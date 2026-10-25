---
version: "2.0"
complete: true
---
# Lifecycle and capability violations

A host that breaks the lifecycle, and an extension that sends progress it did
not advertise. Every message is constructed. The expected findings are at the
end. The extension refuses each request in the wrong state with -32014, but
the checker cannot check the refusal code yet (smithy-2qe.34.19).

Entry 0, compile before initialize:

```jsonrpc host -> extension
{"jsonrpc": "2.0", "id": 1, "method": "morphir.frontend.compile", "params": {"languageId": "elm", "sources": {"documents": []}, "package": {"name": "local/example"}, "options": {"typesOnly": false, "irVersion": "3"}}}
```

```jsonrpc extension -> host
{"jsonrpc": "2.0", "id": 1, "error": {"code": -32014, "message": "Request is not allowed before initialization or after shutdown"}}
```

Entry 2, info before initialize:

```jsonrpc host -> extension
{"jsonrpc": "2.0", "id": 2, "method": "morphir.extension.info"}
```

```jsonrpc extension -> host
{"jsonrpc": "2.0", "id": 2, "error": {"code": -32014, "message": "Request is not allowed before initialization or after shutdown"}}
```

Entries 4 and 5, a session with no cancellation and no progress:

```jsonrpc host -> extension
{"jsonrpc": "2.0", "id": 3, "method": "morphir.initialize", "params": {"protocolVersions": ["0.1"], "host": {"name": "morphir-cli", "version": "0.4.0"}}}
```

```jsonrpc extension -> host
{"jsonrpc": "2.0", "id": 3, "result": {"protocolVersion": "0.1", "extension": {"id": "org.finos.morphir.example", "name": "Morphir example extension", "version": "1.0.0", "types": ["frontend"]}, "capabilities": {"frontend": {"languages": [{"id": "elm", "fileExtensions": [".elm"]}], "irVersions": ["3"], "compile": true, "incremental": false, "fragments": false}, "cancellation": false, "progress": false}}}
```

Entry 6, the extension reports progress that it did not advertise:

```jsonrpc extension -> host
{"jsonrpc": "2.0", "method": "morphir.progress", "params": {"requestId": 1, "kind": "begin", "message": "Starting"}}
```

Entry 7, the host cancels without the cancellation capability:

```jsonrpc host -> extension
{"jsonrpc": "2.0", "method": "$/cancelRequest", "params": {"id": 1}}
```

Entry 8 is the initialized notification. Entry 9, generate with no backend capability:

```jsonrpc host -> extension
{"jsonrpc": "2.0", "method": "morphir.initialized"}
```

```jsonrpc host -> extension
{"jsonrpc": "2.0", "id": 4, "method": "morphir.backend.generate", "params": {"ir": {}, "target": "avro"}}
```

```jsonrpc extension -> host
{"jsonrpc": "2.0", "id": 4, "error": {"code": -32013, "message": "The extension did not advertise backend generation."}}
```

Entry 13, ping after shutdown:

```jsonrpc host -> extension
{"jsonrpc": "2.0", "id": 5, "method": "morphir.shutdown"}
```

```jsonrpc extension -> host
{"jsonrpc": "2.0", "id": 5, "result": {}}
```

```jsonrpc host -> extension
{"jsonrpc": "2.0", "id": 6, "method": "morphir.ping"}
```

```jsonrpc extension -> host
{"jsonrpc": "2.0", "id": 6, "error": {"code": -32014, "message": "Request is not allowed before initialization or after shutdown"}}
```

```jsonrpc host -> extension
{"jsonrpc": "2.0", "method": "morphir.exit"}
```

Expected findings:

```jsonrpc-expect
[
  {
    "code": "StateViolation",
    "entry": 0
  },
  {
    "code": "CapabilityNotAdvertised",
    "entry": 0
  },
  {
    "code": "StateViolation",
    "entry": 2
  },
  {
    "code": "CapabilityNotAdvertised",
    "entry": 6
  },
  {
    "code": "CapabilityNotAdvertised",
    "entry": 7
  },
  {
    "code": "CapabilityNotAdvertised",
    "entry": 9
  },
  {
    "code": "StateViolation",
    "entry": 13
  }
]
```
