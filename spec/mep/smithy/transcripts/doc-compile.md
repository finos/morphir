---
version: "2.0"
complete: true
---
# protocol.md: frontend compilation

The compile request, the progress notification and the successful compile
result, verbatim. A constructed handshake comes first, because the compile
request needs a ready session with an incremental frontend and progress.

Constructed, a conformant initialize request:

```jsonrpc host -> extension
{"jsonrpc": "2.0", "id": 0, "method": "morphir.initialize", "params": {"protocolVersions": ["0.1"], "host": {"kind": "cli", "name": "morphir-cli", "version": "0.4.0"}}}
```

Constructed, an initialize result that advertises the capabilities this transcript uses:

```jsonrpc extension -> host
{"jsonrpc": "2.0", "id": 0, "result": {"protocolVersion": "0.1", "extension": {"id": "org.finos.morphir.example", "name": "Morphir example extension", "version": "1.0.0", "types": ["frontend"]}, "capabilities": {"frontend": {"languages": [{"id": "elm", "fileExtensions": [".elm"]}], "irVersions": ["3"], "compile": true, "incremental": true, "fragments": false}, "cancellation": false, "progress": true}}}
```

Constructed, the initialized notification:

```jsonrpc host -> extension
{"jsonrpc": "2.0", "method": "morphir.initialized"}
```

Verbatim from protocol.md line 466, the compile request:

```jsonrpc host -> extension
{
  "jsonrpc": "2.0",
  "id": "compile-1",
  "method": "morphir.frontend.compile",
  "params": {
    "languageId": "elm",
    "sources": {
      "root": "file:///work",
      "documents": [
        {
          "uri": "file:///work/Example.elm",
          "languageId": "elm",
          "version": 1,
          "text": "module Example exposing (add)\n\nadd : Int -> Int -> Int\nadd a b = a + b\n"
        }
      ]
    },
    "package": {
      "name": "local/example",
      "exposedModules": ["Example"]
    },
    "dependencies": [],
    "options": {
      "typesOnly": false,
      "irVersion": "3"
    },
    "baseline": {
      "modules": [
        {
          "name": "My.Types",
          "uri": "file:///work/My/Types.elm",
          "sourceDigest": "sha256:aa",
          "interfaceDigest": "sha256:bb",
          "dependsOn": ["My.Other"],
          "ir": {}
        }
      ]
    }
  }
}
```

Verbatim from protocol.md line 793, the progress notification:

```jsonrpc extension -> host
{
  "jsonrpc": "2.0",
  "method": "morphir.progress",
  "params": {
    "requestId": "compile-1",
    "kind": "report",
    "message": "Type checking Example",
    "percentage": 60
  }
}
```

Verbatim from protocol.md line 568, the successful compile result:

```jsonrpc extension -> host
{
  "jsonrpc": "2.0",
  "id": "compile-1",
  "result": {
    "success": true,
    "irVersion": "3",
    "ir": {},
    "diagnostics": [],
    "modules": ["Example"],
    "moduleResults": [
      {
        "name": "Example",
        "uri": "file:///work/Example.elm",
        "status": "compiled",
        "sourceDigest": "sha256:cc",
        "interfaceDigest": "sha256:dd",
        "dependsOn": [],
        "ir": {},
        "diagnostics": []
      }
    ],
    "contextDigest": "sha256:ff"
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

