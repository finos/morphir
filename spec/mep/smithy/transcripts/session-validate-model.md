---
version: "2.0"
complete: true
---
# A MEP 0.2.0-draft.1 model validation session

The host reads the claims, then offers two validateModel tuples. It prefers
Ion. The extension reads only JSON, so the session agrees on the JSON tuple.
The validateModel request and result are MCK case model-0036. The model is
the plain IR fixture `fixtures/plain-ir.json`. Every other message is
constructed.

```jsonrpc host -> extension
{"jsonrpc": "2.0", "id": "describe-1", "method": "morphir.extension.describe", "params": {"protocolVersions": ["0.2.0-draft.1"]}}
```

```jsonrpc extension -> host
{"jsonrpc": "2.0", "id": "describe-1", "result": {"claimsVersion": "0.1.0-draft.2", "protocolVersions": ["0.2.0-draft.1"], "extension": {"id": "org.finos.morphir.example", "name": "Morphir example validator", "version": "1.0.0", "types": ["validator"]}, "capabilities": {"validator": {"irVersions": ["4.0.0"]}, "modelTransport": {"tuples": [{"operation": "morphir.validator.validateModel", "profile": "morphir-ir", "codec": "morphir-json", "envelopeVersion": "0.1.0-draft.1", "irVersion": "4.0.0"}], "limits": {"maxEncodedBytes": 8192, "maxDecodedBytes": 4096, "maxDepth": 64, "maxNodes": 256}}, "streaming": false, "incremental": false, "cancellation": false, "progress": false}}}
```

```jsonrpc host -> extension
{"jsonrpc": "2.0", "id": 0, "method": "morphir.initialize", "params": {"protocolVersions": ["0.2.0-draft.1"], "host": {"kind": "cli", "name": "morphir-cli", "version": "0.4.0"}, "modelTransport": {"tuples": [{"operation": "morphir.validator.validateModel", "profile": "morphir-model", "codec": "ion-binary", "envelopeVersion": "0.1.0-draft.1", "irVersion": "4.0.0"}, {"operation": "morphir.validator.validateModel", "profile": "morphir-ir", "codec": "morphir-json", "envelopeVersion": "0.1.0-draft.1", "irVersion": "4.0.0"}], "limits": {"maxEncodedBytes": 8192, "maxDecodedBytes": 4096, "maxDepth": 64, "maxNodes": 256}, "guarantees": []}}}
```

```jsonrpc extension -> host
{"jsonrpc": "2.0", "id": 0, "result": {"protocolVersion": "0.2.0-draft.1", "extension": {"id": "org.finos.morphir.example", "name": "Morphir example validator", "version": "1.0.0", "types": ["validator"]}, "capabilities": {"validator": {"irVersions": ["4.0.0"]}, "modelTransport": {"tuples": [{"operation": "morphir.validator.validateModel", "profile": "morphir-ir", "codec": "morphir-json", "envelopeVersion": "0.1.0-draft.1", "irVersion": "4.0.0"}], "limits": {"maxEncodedBytes": 8192, "maxDecodedBytes": 4096, "maxDepth": 64, "maxNodes": 256}, "guarantees": []}, "streaming": false, "incremental": false, "cancellation": false, "progress": false}}}
```

```jsonrpc host -> extension
{"jsonrpc": "2.0", "method": "morphir.initialized"}
```

MCK case model-0036, the request and its result with one warning:

```jsonrpc host -> extension
{"jsonrpc": "2.0", "id": 1, "method": "morphir.validator.validateModel", "params": {"model": {"envelopeVersion": "0.1.0-draft.1", "modelId": "urn:morphir:mep:fixture:model", "revision": "fixture-revision-1", "irVersion": "4.0.0", "profile": "morphir-ir", "payload": {"codec": "morphir-json", "layout": "single-document", "decodedByteLength": 130, "sha256": "fd49ad8b0cab49216323beb969c08f91a888925dbb995838c57a05b48a80bb2f", "content": "eyJmb3JtYXRWZXJzaW9uIjoiNC4wLjAiLCJkaXN0cmlidXRpb24iOnsiTGlicmFyeSI6eyJwYWNrYWdlTmFtZSI6ImV4YW1wbGUvbWVwLWZpeHR1cmUiLCJkZXBlbmRlbmNpZXMiOnt9LCJkZWYiOnsibW9kdWxlcyI6e319fX19Cg=="}, "evidence": [], "critical": []}, "options": {}}}
```

```jsonrpc extension -> host
{"jsonrpc": "2.0", "id": 1, "result": {"diagnostics": [{"severity": "warning", "code": "example.empty-package", "message": "Package example/mep-fixture has no module."}]}}
```

```jsonrpc host -> extension
{"jsonrpc": "2.0", "id": "shutdown-1", "method": "morphir.shutdown"}
```

```jsonrpc extension -> host
{"jsonrpc": "2.0", "id": "shutdown-1", "result": {}}
```

```jsonrpc host -> extension
{"jsonrpc": "2.0", "method": "morphir.exit"}
```
