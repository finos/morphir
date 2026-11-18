---
version: "2.0"
complete: true
---
# A bounded-generation session

The host and guest agree on the exact bounded-access tuple. The guest first requests the root inventory, then walks both member pages of the admitted domain view. The delivery bytes come from the v4 orders fixture.

```jsonrpc host -> extension
{"jsonrpc":"2.0","id":1,"method":"morphir.initialize","params":{"protocolVersions":["0.2.0-draft.2","0.2.0-draft.1"],"host":{"kind":"cli","name":"morphir-cli","version":"0.5.0"},"modelAccess":{"tuples":[{"protocolVersion":"0.2.0-draft.2","accessVersion":"0.1.0-draft.1","operation":"morphir.backend.generateModel","irVersion":"4.0.0","profile":"morphir-ir","codec":"morphir-json","layout":"document-tree","contextualEncoding":"plain"}],"limits":{"maxFrameBytes":32768,"maxEncodedBytesPerExchange":8192,"maxDecodedBytesPerExchange":6144,"maxDocumentsPerBatch":8,"maxDepth":64,"maxNodes":256,"maxDiagnosticsPerExchange":16,"maxOutstandingRequests":8,"maxGuestStateBytes":1048576,"maxHostCacheBytes":1048576,"maxArtifactChunkBytes":4096,"maxArtifactBytes":4294967296,"maxTotalArtifactBytes":4294967296,"maxSessionDiskBytes":8589934592,"maxSessionWorkUnits":4096,"maxRounds":16,"maxCallMilliseconds":500,"maxSessionMilliseconds":2500}}}}
```

```jsonrpc extension -> host
{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":"0.2.0-draft.2","extension":{"id":"org.finos.morphir.orders","name":"Orders generator","version":"0.1.0","types":["backend"]},"capabilities":{"backend":{"targets":["text"],"irVersions":["4.0.0"],"generate":false},"modelAccess":{"tuples":[{"protocolVersion":"0.2.0-draft.2","accessVersion":"0.1.0-draft.1","operation":"morphir.backend.generateModel","irVersion":"4.0.0","profile":"morphir-ir","codec":"morphir-json","layout":"document-tree","contextualEncoding":"plain"}],"limits":{"maxFrameBytes":32768,"maxEncodedBytesPerExchange":8192,"maxDecodedBytesPerExchange":6144,"maxDocumentsPerBatch":8,"maxDepth":64,"maxNodes":256,"maxDiagnosticsPerExchange":16,"maxOutstandingRequests":8,"maxGuestStateBytes":1048576,"maxHostCacheBytes":1048576,"maxArtifactChunkBytes":4096,"maxArtifactBytes":4294967296,"maxTotalArtifactBytes":4294967296,"maxSessionDiskBytes":8589934592,"maxSessionWorkUnits":4096,"maxRounds":16,"maxCallMilliseconds":500,"maxSessionMilliseconds":2500}}}}}
```

```jsonrpc host -> extension
{"jsonrpc":"2.0","method":"morphir.initialized"}
```

```jsonrpc host -> extension
{"jsonrpc":"2.0","id":2,"method":"morphir.backend.generateModel.start","params":{"sessionId":"orders-generation","snapshot":{"snapshotId":"orders-snapshot","modelId":"acme/orders","revision":"orders-r1","contextDigest":"1111111111111111111111111111111111111111111111111111111111111111","scope":"orders-generation-view"},"input":{"protocolVersion":"0.2.0-draft.2","accessVersion":"0.1.0-draft.1","operation":"morphir.backend.generateModel","irVersion":"4.0.0","profile":"morphir-ir","codec":"morphir-json","layout":"document-tree","contextualEncoding":"plain"},"target":"text","options":{},"requiredGuarantees":[],"limits":{"maxFrameBytes":32768,"maxEncodedBytesPerExchange":8192,"maxDecodedBytesPerExchange":6144,"maxDocumentsPerBatch":8,"maxDepth":64,"maxNodes":256,"maxDiagnosticsPerExchange":16,"maxOutstandingRequests":8,"maxGuestStateBytes":1048576,"maxHostCacheBytes":1048576,"maxArtifactChunkBytes":4096,"maxArtifactBytes":4294967296,"maxTotalArtifactBytes":4294967296,"maxSessionDiskBytes":8589934592,"maxSessionWorkUnits":4096,"maxRounds":16,"maxCallMilliseconds":500,"maxSessionMilliseconds":2500}}}
```

```jsonrpc extension -> host
{"jsonrpc":"2.0","id":2,"result":{"state":"continue","sessionId":"orders-generation","round":1,"requests":[{"requestId":"root-modules","kind":"inventory","selection":"root","pageSize":1}],"artifacts":[],"diagnostics":[]}}
```

```jsonrpc host -> extension
{"jsonrpc":"2.0","id":3,"method":"morphir.backend.generateModel.advance","params":{"sessionId":"orders-generation","round":1,"deliveries":[{"requestId":"root-modules","kind":"inventory","snapshotId":"orders-snapshot","entries":[{"documentId":"pkg/acme/orders/domain/module","packageName":"acme/orders","modulePath":"domain","kind":"module","role":"definition","memberSelection":"orders-domain-members"}]}]}}
```

```jsonrpc extension -> host
{"jsonrpc":"2.0","id":3,"result":{"state":"continue","sessionId":"orders-generation","round":2,"requests":[{"requestId":"domain-first","kind":"inventory","selection":"orders-domain-members","pageSize":2}],"artifacts":[],"diagnostics":[]}}
```

The guest refuses a replay of round 1. The outstanding round remains 2 and no artifact is appended.

```jsonrpc host -> extension
{"jsonrpc":"2.0","id":4,"method":"morphir.backend.generateModel.advance","params":{"sessionId":"orders-generation","round":1,"deliveries":[]}}
```

```jsonrpc extension -> host
{"jsonrpc":"2.0","id":4,"error":{"code":-32602,"message":"Expected round 2"}}
```

The guest walks both pages of the selected module before asking for a value body.

```jsonrpc host -> extension
{"jsonrpc":"2.0","id":5,"method":"morphir.backend.generateModel.advance","params":{"sessionId":"orders-generation","round":2,"deliveries":[{"requestId":"domain-first","kind":"inventory","snapshotId":"orders-snapshot","entries":[{"documentId":"pkg/acme/orders/domain/order.type","packageName":"acme/orders","modulePath":"domain","kind":"type","role":"definition","name":"order"},{"documentId":"pkg/acme/orders/domain/order.value","packageName":"acme/orders","modulePath":"domain","kind":"value","role":"definition","name":"order"}],"nextCursor":"domain-page-two"}]}}
```

```jsonrpc extension -> host
{"jsonrpc":"2.0","id":5,"result":{"state":"continue","sessionId":"orders-generation","round":3,"requests":[{"requestId":"domain-second","kind":"inventory","selection":"orders-domain-members","pageSize":2,"cursor":"domain-page-two"}],"artifacts":[],"diagnostics":[]}}
```

```jsonrpc host -> extension
{"jsonrpc":"2.0","id":6,"method":"morphir.backend.generateModel.advance","params":{"sessionId":"orders-generation","round":3,"deliveries":[{"requestId":"domain-second","kind":"inventory","snapshotId":"orders-snapshot","entries":[{"documentId":"pkg/acme/orders/domain/total-in-_usd.value","packageName":"acme/orders","modulePath":"domain","kind":"value","role":"definition","name":"total-in-USD"}]}]}}
```

```jsonrpc extension -> host
{"jsonrpc":"2.0","id":6,"result":{"state":"continue","sessionId":"orders-generation","round":4,"requests":[{"requestId":"final-value","kind":"document","documentId":"pkg/acme/orders/domain/total-in-_usd.value"}],"artifacts":[],"diagnostics":[]}}
```

```jsonrpc host -> extension
{"jsonrpc":"2.0","id":7,"method":"morphir.backend.generateModel.advance","params":{"sessionId":"orders-generation","round":4,"deliveries":[{"requestId":"final-value","kind":"document","snapshotId":"orders-snapshot","documentId":"pkg/acme/orders/domain/total-in-_usd.value","decodedByteLength":257,"sha256":"f4e5dcae87eb9b022bf446711b4173cd04839da7cf4e2f122ca1600143acf9d4","content":"ewogICJmb3JtYXRWZXJzaW9uIjogNCwKICAibmFtZSI6ICJ0b3RhbC1pbi1VU0QiLAogICJkZWYiOiB7CiAgICAiUHVibGljIjogewogICAgICAiRXhwcmVzc2lvbkJvZHkiOiB7CiAgICAgICAgImlucHV0VHlwZXMiOiB7fSwKICAgICAgICAib3V0cHV0VHlwZSI6ICJtb3JwaGlyL1NESzpiYXNpY3MjaW50IiwKICAgICAgICAiYm9keSI6IHsgIlJlZmVyZW5jZSI6ICJhY21lL29yZGVyczpkb21haW4jb3JkZXIiIH0KICAgICAgfQogICAgfQogIH0KfQo="}]}}
```

```jsonrpc extension -> host
{"jsonrpc":"2.0","id":7,"result":{"state":"continue","sessionId":"orders-generation","round":5,"requests":[{"requestId":"order-value","kind":"document","documentId":"pkg/acme/orders/domain/order.value"}],"artifacts":[],"diagnostics":[]}}
```

```jsonrpc host -> extension
{"jsonrpc":"2.0","id":8,"method":"morphir.backend.generateModel.advance","params":{"sessionId":"orders-generation","round":5,"deliveries":[{"requestId":"order-value","kind":"document","snapshotId":"orders-snapshot","documentId":"pkg/acme/orders/domain/order.value","decodedByteLength":246,"sha256":"23b1c85f2ee470a468e335098619d394fd23d7a70ee592d39a28612dc5e98fa0","content":"ewogICJmb3JtYXRWZXJzaW9uIjogNCwKICAibmFtZSI6ICJvcmRlciIsCiAgImRlZiI6IHsKICAgICJQdWJsaWMiOiB7CiAgICAgICJFeHByZXNzaW9uQm9keSI6IHsKICAgICAgICAiaW5wdXRUeXBlcyI6IHt9LAogICAgICAgICJvdXRwdXRUeXBlIjogIm1vcnBoaXIvU0RLOmJhc2ljcyNpbnQiLAogICAgICAgICJib2R5IjogeyAiTGl0ZXJhbCI6IHsgIkludGVnZXJMaXRlcmFsIjogNzMgfSB9CiAgICAgIH0KICAgIH0KICB9Cn0K"}]}}
```

```jsonrpc extension -> host
{"jsonrpc":"2.0","id":8,"result":{"state":"complete","sessionId":"orders-generation","artifacts":[{"path":"order.txt","offset":0,"decodedByteLength":3,"sha256":"c6ebc76be5dc1f8b433f8d6fd9bd85cd9325086038442db8614bb799fec6fd85","content":"NzMK","end":true}],"diagnostics":[]}}
```

The next operation has a work limit of one unit. It reports a terminal failure without producing an artifact.

```jsonrpc host -> extension
{"jsonrpc":"2.0","id":9,"method":"morphir.backend.generateModel.start","params":{"sessionId":"orders-limited","snapshot":{"snapshotId":"orders-snapshot","modelId":"acme/orders","revision":"orders-r1","contextDigest":"1111111111111111111111111111111111111111111111111111111111111111","scope":"orders-generation-view"},"input":{"protocolVersion":"0.2.0-draft.2","accessVersion":"0.1.0-draft.1","operation":"morphir.backend.generateModel","irVersion":"4.0.0","profile":"morphir-ir","codec":"morphir-json","layout":"document-tree","contextualEncoding":"plain"},"target":"text","options":{},"requiredGuarantees":[],"limits":{"maxFrameBytes":32768,"maxEncodedBytesPerExchange":8192,"maxDecodedBytesPerExchange":6144,"maxDocumentsPerBatch":8,"maxDepth":64,"maxNodes":256,"maxDiagnosticsPerExchange":16,"maxOutstandingRequests":8,"maxGuestStateBytes":1048576,"maxHostCacheBytes":1048576,"maxArtifactChunkBytes":4096,"maxArtifactBytes":4294967296,"maxTotalArtifactBytes":4294967296,"maxSessionDiskBytes":8589934592,"maxSessionWorkUnits":1,"maxRounds":16,"maxCallMilliseconds":500,"maxSessionMilliseconds":2500}}}
```

```jsonrpc extension -> host
{"jsonrpc":"2.0","id":9,"result":{"state":"failed","sessionId":"orders-limited","diagnostics":[{"severity":"error","message":"The session work limit was exhausted.","code":"model_access.limit_exceeded","data":{"limit":"maxSessionWorkUnits"}}]}}
```

The host cancels a third operation before delivering any more input.

```jsonrpc host -> extension
{"jsonrpc":"2.0","id":10,"method":"morphir.backend.generateModel.start","params":{"sessionId":"orders-cancelled","snapshot":{"snapshotId":"orders-snapshot","modelId":"acme/orders","revision":"orders-r1","contextDigest":"1111111111111111111111111111111111111111111111111111111111111111","scope":"orders-generation-view"},"input":{"protocolVersion":"0.2.0-draft.2","accessVersion":"0.1.0-draft.1","operation":"morphir.backend.generateModel","irVersion":"4.0.0","profile":"morphir-ir","codec":"morphir-json","layout":"document-tree","contextualEncoding":"plain"},"target":"text","options":{},"requiredGuarantees":[],"limits":{"maxFrameBytes":32768,"maxEncodedBytesPerExchange":8192,"maxDecodedBytesPerExchange":6144,"maxDocumentsPerBatch":8,"maxDepth":64,"maxNodes":256,"maxDiagnosticsPerExchange":16,"maxOutstandingRequests":8,"maxGuestStateBytes":1048576,"maxHostCacheBytes":1048576,"maxArtifactChunkBytes":4096,"maxArtifactBytes":4294967296,"maxTotalArtifactBytes":4294967296,"maxSessionDiskBytes":8589934592,"maxSessionWorkUnits":4096,"maxRounds":16,"maxCallMilliseconds":500,"maxSessionMilliseconds":2500}}}
```

```jsonrpc extension -> host
{"jsonrpc":"2.0","id":10,"result":{"state":"continue","sessionId":"orders-cancelled","round":1,"requests":[],"artifacts":[],"diagnostics":[]}}
```

```jsonrpc host -> extension
{"jsonrpc":"2.0","id":11,"method":"morphir.backend.generateModel.cancel","params":{"sessionId":"orders-cancelled"}}
```

```jsonrpc extension -> host
{"jsonrpc":"2.0","id":11,"result":{"sessionId":"orders-cancelled"}}
```

```jsonrpc host -> extension
{"jsonrpc":"2.0","id":12,"method":"morphir.shutdown"}
```

```jsonrpc extension -> host
{"jsonrpc":"2.0","id":12,"result":{}}
```

```jsonrpc host -> extension
{"jsonrpc":"2.0","method":"morphir.exit"}
```
