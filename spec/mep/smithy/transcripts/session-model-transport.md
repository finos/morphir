---
version: "2.0"
complete: true
---
# A MEP 0.2.0-draft.1 model-transport session

The host offers both rich model tuples, and the extension selects both. The
`compileModel` request and result are MCK case model-0028, and the
`generateModel` request is MCK case model-0001, from
spec/mep/mck/model-transport.cases.json, unchanged. The handshake is
constructed from the `hostOffer` and `guestSupport` of those cases. The
legacy `compile` and `generate` flags are false: a rich-only provider.

```jsonrpc host -> extension
{"jsonrpc": "2.0", "id": 0, "method": "morphir.initialize", "params": {"protocolVersions": ["0.2.0-draft.1", "0.1"], "host": {"kind": "cli", "name": "morphir-cli", "version": "0.4.0"}, "modelTransport": {"tuples": [{"operation": "morphir.frontend.compileModel", "profile": "morphir-model", "codec": "ion-binary", "envelopeVersion": "0.1.0-draft.1", "irVersion": "4.0.0"}, {"operation": "morphir.backend.generateModel", "profile": "morphir-model", "codec": "ion-binary", "envelopeVersion": "0.1.0-draft.1", "irVersion": "4.0.0"}], "limits": {"maxEncodedBytes": 8192, "maxDecodedBytes": 4096, "maxDepth": 64, "maxNodes": 256}, "guarantees": ["urn:morphir:mep:fixture:checked"]}}}
```

```jsonrpc extension -> host
{"jsonrpc": "2.0", "id": 0, "result": {"protocolVersion": "0.2.0-draft.1", "extension": {"id": "org.finos.morphir.moonbit", "name": "Morphir MoonBit", "version": "0.1.0", "types": ["frontend", "backend"]}, "capabilities": {"frontend": {"languages": [{"id": "moonbit", "fileExtensions": [".mbt"]}], "irVersions": ["4.0.0"], "compile": false, "incremental": false, "fragments": false}, "backend": {"targets": ["moonbit"], "irVersions": ["4.0.0"], "generate": false}, "modelTransport": {"tuples": [{"operation": "morphir.frontend.compileModel", "profile": "morphir-model", "codec": "ion-binary", "envelopeVersion": "0.1.0-draft.1", "irVersion": "4.0.0"}, {"operation": "morphir.backend.generateModel", "profile": "morphir-model", "codec": "ion-binary", "envelopeVersion": "0.1.0-draft.1", "irVersion": "4.0.0"}], "limits": {"maxEncodedBytes": 8192, "maxDecodedBytes": 4096, "maxDepth": 64, "maxNodes": 256}, "guarantees": ["urn:morphir:mep:fixture:checked"]}, "streaming": false, "incremental": false, "cancellation": false, "progress": false}}}
```

```jsonrpc host -> extension
{"jsonrpc": "2.0", "method": "morphir.initialized"}
```

MCK case model-0028:

```jsonrpc host -> extension
{"jsonrpc": "2.0", "id": 1, "method": "morphir.frontend.compileModel", "params": {"languageId": "moonbit", "sources": {"documents": [{"uri": "file:///fixture/main.mbt", "languageId": "moonbit", "version": 1, "text": "pub fn is_ready() -> Bool { true }"}]}, "package": {"name": "example/mep-fixture"}, "dependencies": [], "options": {"typesOnly": true, "irVersion": "4.0.0"}, "contextDigest": "1111111111111111111111111111111111111111111111111111111111111111", "output": {"operation": "morphir.frontend.compileModel", "profile": "morphir-model", "codec": "ion-binary", "envelopeVersion": "0.1.0-draft.1", "irVersion": "4.0.0"}}}
```

```jsonrpc extension -> host
{"jsonrpc": "2.0", "id": 1, "result": {"success": true, "model": {"envelopeVersion": "0.1.0-draft.1", "modelId": "urn:morphir:mep:fixture:model", "revision": "fixture-revision-1", "irVersion": "4.0.0", "profile": "morphir-model", "payload": {"codec": "ion-binary", "layout": "single-document", "decodedByteLength": 499, "sha256": "49f87687c033a8ec39a7f42b93bb1c54b4856ceab0b05246d81ea0a8b27e10b1", "content": "4AEA6u4Co4GD3gKeh74Cmo1tb3JwaGlyX21vZGVsgmlyjWZvcm1hdFZlcnNpb26MZGlzdHJpYnV0aW9uh0xpYnJhcnmLcGFja2FnZU5hbWWMZGVwZW5kZW5jaWVzg2RlZodtb2R1bGVzi2VucmljaG1lbnRzhW93bmVyhGRhdGGLc291cmNlX25hbWWLdGFyZ2V0X25hbWWMb3JpZ2luYWxOYW1linRhcmdldE5hbWWOj3NvdXJjZVByZWNpc2lvboRraW5khWludDY0hWV4YWN0hmFtb3VudIpmdXR1cmVGYWN0jpFmdXR1cmVfdm9jYWJ1bGFyeYdlbmFibGVkinByb3ZlbmFuY2WOjmZpeHR1cmVfb3JpZ2luiHByb2R1Y2VyhnNvdXJjZe4BxoGK3gHBi96pjIU0LjAuMI3en47enI+Ok2V4YW1wbGUvbWVwLWZpeHR1cmWQ0JHSktCTvuXe45SOqnVybjptb3JwaGlyOm1lcDpmaXh0dXJlOnVua25vd24tZW5yaWNobWVudJXus4KWl96umIdpc1JlYWR5mYhpc19yZWFkeZrcm3EcnScgAAAAAAABnlTEEtZEn+WBoNKhEaK+qu6ogaPepKSOlG1lcC1yZWZlcmVuY2UtY29ycHVzpYtmaXh0dXJlLm1idA=="}, "evidence": [], "critical": []}, "diagnostics": [], "modules": []}}
```

MCK case model-0001, then a constructed generate result:

```jsonrpc host -> extension
{"jsonrpc": "2.0", "id": 1, "method": "morphir.backend.generateModel", "params": {"model": {"envelopeVersion": "0.1.0-draft.1", "modelId": "urn:morphir:mep:fixture:model", "revision": "fixture-revision-1", "irVersion": "4.0.0", "profile": "morphir-model", "payload": {"codec": "ion-binary", "layout": "single-document", "decodedByteLength": 499, "sha256": "49f87687c033a8ec39a7f42b93bb1c54b4856ceab0b05246d81ea0a8b27e10b1", "content": "4AEA6u4Co4GD3gKeh74Cmo1tb3JwaGlyX21vZGVsgmlyjWZvcm1hdFZlcnNpb26MZGlzdHJpYnV0aW9uh0xpYnJhcnmLcGFja2FnZU5hbWWMZGVwZW5kZW5jaWVzg2RlZodtb2R1bGVzi2VucmljaG1lbnRzhW93bmVyhGRhdGGLc291cmNlX25hbWWLdGFyZ2V0X25hbWWMb3JpZ2luYWxOYW1linRhcmdldE5hbWWOj3NvdXJjZVByZWNpc2lvboRraW5khWludDY0hWV4YWN0hmFtb3VudIpmdXR1cmVGYWN0jpFmdXR1cmVfdm9jYWJ1bGFyeYdlbmFibGVkinByb3ZlbmFuY2WOjmZpeHR1cmVfb3JpZ2luiHByb2R1Y2VyhnNvdXJjZe4BxoGK3gHBi96pjIU0LjAuMI3en47enI+Ok2V4YW1wbGUvbWVwLWZpeHR1cmWQ0JHSktCTvuXe45SOqnVybjptb3JwaGlyOm1lcDpmaXh0dXJlOnVua25vd24tZW5yaWNobWVudJXus4KWl96umIdpc1JlYWR5mYhpc19yZWFkeZrcm3EcnScgAAAAAAABnlTEEtZEn+WBoNKhEaK+qu6ogaPepKSOlG1lcC1yZWZlcmVuY2UtY29ycHVzpYtmaXh0dXJlLm1idA=="}, "evidence": [], "critical": []}, "input": {"operation": "morphir.backend.generateModel", "profile": "morphir-model", "codec": "ion-binary", "envelopeVersion": "0.1.0-draft.1", "irVersion": "4.0.0"}, "target": "moonbit", "contextDigest": "1111111111111111111111111111111111111111111111111111111111111111", "requiredGuarantees": [], "options": {}}}
```

```jsonrpc extension -> host
{"jsonrpc": "2.0", "id": 1, "result": {"success": true, "artifacts": [{"path": "library.mbt", "content": "///|\npub fn always() -> Bool { true }\n"}], "diagnostics": []}}
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
