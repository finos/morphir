---
version: "2.0"
complete: true
---
# protocol.md: compilation failure

The compile request and the partial failure result, verbatim. A compilation
failure is a normal result with `success: false`, not a JSON-RPC error.

Constructed, a conformant initialize request:

```jsonrpc host -> extension
{"jsonrpc": "2.0", "id": 0, "method": "morphir.initialize", "params": {"protocolVersions": ["0.1"], "host": {"kind": "cli", "name": "morphir-cli", "version": "0.4.0"}}}
```

Constructed, an initialize result that advertises the capabilities this transcript uses:

```jsonrpc extension -> host
{"jsonrpc": "2.0", "id": 0, "result": {"protocolVersion": "0.1", "extension": {"id": "org.finos.morphir.example", "name": "Morphir example extension", "version": "1.0.0", "types": ["frontend"]}, "capabilities": {"frontend": {"languages": [{"id": "elm", "fileExtensions": [".elm"]}], "irVersions": ["3"], "compile": true, "incremental": true, "fragments": false}, "cancellation": false, "progress": false}}}
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

Verbatim from protocol.md line 636, the compilation failure result:

```jsonrpc extension -> host
{
  "jsonrpc": "2.0",
  "id": "compile-1",
  "result": {
    "success": false,
    "irVersion": "3",
    "ir": {},
    "diagnostics": [
      {
        "severity": "error",
        "code": "elm.type-mismatch",
        "message": "This expression does not match the declared type.",
        "location": {
          "uri": "file:///work/Example/Broken.elm",
          "range": {
            "start": { "line": 3, "character": 10 },
            "end": { "line": 3, "character": 15 }
          }
        }
      }
    ],
    "modules": ["Example.Ok"],
    "moduleResults": [
      {
        "name": "Example.Broken",
        "uri": "file:///work/Example/Broken.elm",
        "status": "failed",
        "sourceDigest": "sha256:ee",
        "dependsOn": [],
        "diagnostics": [
          {
            "severity": "error",
            "code": "elm.type-mismatch",
            "message": "This expression does not match the declared type.",
            "location": {
              "uri": "file:///work/Example/Broken.elm",
              "range": {
                "start": { "line": 3, "character": 10 },
                "end": { "line": 3, "character": 15 }
              }
            }
          }
        ]
      },
      {
        "name": "Example.Ok",
        "uri": "file:///work/Example/Ok.elm",
        "status": "compiled",
        "sourceDigest": "sha256:ff",
        "interfaceDigest": "sha256:gg",
        "dependsOn": [],
        "ir": {},
        "diagnostics": []
      }
    ]
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

