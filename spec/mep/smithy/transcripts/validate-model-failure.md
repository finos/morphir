---
version: "2.0"
complete: true
---
# A validator that cannot run

The extension admits the model, but the validator cannot run. It answers
with -32003 (ValidationError), not with a result. The session stays ready,
so the host can shut it down. Every message is constructed.

```jsonrpc host -> extension
{"jsonrpc": "2.0", "id": 0, "method": "morphir.initialize", "params": {"protocolVersions": ["0.2.0-draft.1"], "host": {"kind": "cli", "name": "morphir-cli", "version": "0.4.0"}, "modelTransport": {"tuples": [{"operation": "morphir.validator.validateModel", "profile": "morphir-ir", "codec": "morphir-json", "envelopeVersion": "0.1.0-draft.1", "irVersion": "4.0.0"}], "limits": {"maxEncodedBytes": 8192, "maxDecodedBytes": 4096, "maxDepth": 64, "maxNodes": 256}}}}
```

```jsonrpc extension -> host
{"jsonrpc": "2.0", "id": 0, "result": {"protocolVersion": "0.2.0-draft.1", "extension": {"id": "org.finos.morphir.example", "name": "Morphir example validator", "version": "1.0.0", "types": ["validator"]}, "capabilities": {"validator": {"irVersions": ["4.0.0"]}, "modelTransport": {"tuples": [{"operation": "morphir.validator.validateModel", "profile": "morphir-ir", "codec": "morphir-json", "envelopeVersion": "0.1.0-draft.1", "irVersion": "4.0.0"}], "limits": {"maxEncodedBytes": 8192, "maxDecodedBytes": 4096, "maxDepth": 64, "maxNodes": 256}, "guarantees": []}, "streaming": false, "incremental": false, "cancellation": false, "progress": false}}}
```

```jsonrpc host -> extension
{"jsonrpc": "2.0", "method": "morphir.initialized"}
```

```jsonrpc host -> extension
{"jsonrpc": "2.0", "id": 1, "method": "morphir.validator.validateModel", "params": {"model": {"envelopeVersion": "0.1.0-draft.1", "modelId": "urn:morphir:mep:fixture:model", "revision": "fixture-revision-1", "irVersion": "4.0.0", "profile": "morphir-ir", "payload": {"codec": "morphir-json", "layout": "single-document", "decodedByteLength": 130, "sha256": "fd49ad8b0cab49216323beb969c08f91a888925dbb995838c57a05b48a80bb2f", "content": "eyJmb3JtYXRWZXJzaW9uIjoiNC4wLjAiLCJkaXN0cmlidXRpb24iOnsiTGlicmFyeSI6eyJwYWNrYWdlTmFtZSI6ImV4YW1wbGUvbWVwLWZpeHR1cmUiLCJkZXBlbmRlbmNpZXMiOnt9LCJkZWYiOnsibW9kdWxlcyI6e319fX19Cg=="}}}}
```

```jsonrpc extension -> host
{"jsonrpc": "2.0", "id": 1, "error": {"code": -32003, "message": "Validation could not run."}}
```

```jsonrpc host -> extension
{"jsonrpc": "2.0", "id": 2, "method": "morphir.shutdown"}
```

```jsonrpc extension -> host
{"jsonrpc": "2.0", "id": 2, "result": {}}
```

```jsonrpc host -> extension
{"jsonrpc": "2.0", "method": "morphir.exit"}
```
