---
version: "2.0"
complete: true
---
# An older session refuses bounded generation

The extension selects the prior draft and does not admit the bounded capability. The host deliberately sends a bounded advance anyway.

```jsonrpc host -> extension
{"jsonrpc":"2.0","id":1,"method":"morphir.initialize","params":{"protocolVersions":["0.2.0-draft.1"],"host":{"name":"morphir-cli","version":"0.5.0"}}}
```

```jsonrpc extension -> host
{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":"0.2.0-draft.1","extension":{"id":"org.finos.morphir.orders","name":"Orders generator","version":"0.1.0","types":["backend"]},"capabilities":{"backend":{"targets":["text"],"irVersions":["4.0.0"],"generate":true}}}}
```

```jsonrpc host -> extension
{"jsonrpc":"2.0","method":"morphir.initialized"}
```

```jsonrpc host -> extension
{"jsonrpc":"2.0","id":2,"method":"morphir.backend.generateModel.advance","params":{"sessionId":"orders-generation","round":1,"deliveries":[]}}
```

```jsonrpc extension -> host
{"jsonrpc":"2.0","id":2,"error":{"code":-32013,"message":"Bounded generation was not negotiated"}}
```

```jsonrpc host -> extension
{"jsonrpc":"2.0","id":3,"method":"morphir.shutdown"}
```

```jsonrpc extension -> host
{"jsonrpc":"2.0","id":3,"result":{}}
```

```jsonrpc host -> extension
{"jsonrpc":"2.0","method":"morphir.exit"}
```

```jsonrpc-expect
[
  {
    "code": "CapabilityNotAdvertised",
    "entry": 3
  }
]
```
