---
version: "2.0"
complete: true
---
# A legacy MEP 0.1 session

A complete, conformant session. Every message is constructed. The host reads
the claim set before initialization, opens a session, compiles two documents
and generates from the IR, then stops the extension. The describe result is
the capability claim set example from protocol.md, line 271.

```jsonrpc host -> extension
{"jsonrpc": "2.0", "id": 1, "method": "morphir.extension.describe", "params": {"protocolVersions": ["0.1"]}}
```

```jsonrpc extension -> host
{"jsonrpc": "2.0", "id": 1, "result": {"claimsVersion": "0.1.0-draft.2", "protocolVersions": ["0.1"], "extension": {"id": "morphir-elm", "name": "Morphir Elm frontend", "version": "0.3.0", "types": ["frontend", "workspace"]}, "capabilities": {"frontend": {"languages": [{"id": "elm", "fileExtensions": [".elm"]}], "irVersions": ["3"], "compile": true, "incremental": false}, "workspace": {"protocolVersions": ["0.1.0-draft.1"], "discover": true}}, "requires": {"host": [">=0.4.0-alpha.7"]}, "critical": ["requires.host"]}}
```

```jsonrpc host -> extension
{"jsonrpc": "2.0", "id": 2, "method": "morphir.initialize", "params": {"protocolVersions": ["0.1"], "host": {"kind": "cli", "name": "morphir-cli", "version": "0.4.0"}}}
```

```jsonrpc extension -> host
{"jsonrpc": "2.0", "id": 2, "result": {"protocolVersion": "0.1", "extension": {"id": "org.finos.morphir.example", "name": "Morphir example extension", "version": "1.0.0", "types": ["frontend", "backend"], "license": "Apache-2.0", "min_sdk_version": "0.4.0"}, "capabilities": {"frontend": {"languages": [{"id": "elm", "fileExtensions": [".elm"]}], "irVersions": ["3"], "compile": true, "incremental": false, "fragments": false, "multiDocument": true}, "backend": {"targets": ["avro"], "irVersions": ["3"], "generate": true}, "streaming": false, "incremental": false, "cancellation": false, "progress": false}}}
```

Information requests are allowed after the initialize result, before the initialized notification.

```jsonrpc host -> extension
{"jsonrpc": "2.0", "id": 3, "method": "morphir.extension.info"}
```

```jsonrpc extension -> host
{"jsonrpc": "2.0", "id": 3, "result": {"id": "org.finos.morphir.example", "name": "Morphir example extension", "version": "1.0.0", "types": ["frontend", "backend"], "license": "Apache-2.0", "min_sdk_version": "0.4.0"}}
```

```jsonrpc host -> extension
{"jsonrpc": "2.0", "method": "morphir.initialized"}
```

```jsonrpc host -> extension
{"jsonrpc": "2.0", "id": 4, "method": "morphir.extension.capabilities", "params": {}}
```

```jsonrpc extension -> host
{"jsonrpc": "2.0", "id": 4, "result": {"frontend": {"languages": [{"id": "elm", "fileExtensions": [".elm"]}], "irVersions": ["3"], "compile": true, "incremental": false, "fragments": false, "multiDocument": true}, "backend": {"targets": ["avro"], "irVersions": ["3"], "generate": true}, "streaming": false, "incremental": false, "cancellation": false, "progress": false}}
```

```jsonrpc host -> extension
{"jsonrpc": "2.0", "id": "compile-2", "method": "morphir.frontend.compile", "params": {"languageId": "elm", "sources": {"root": "file:///work", "documents": [{"uri": "file:///work/src/Example.elm", "languageId": "elm", "version": 1, "text": "module Example exposing (add)\n\nimport Other\n\nadd : Int -> Int -> Int\nadd a b = a + b\n"}, {"uri": "file:///work/src/Other.elm", "languageId": "elm", "version": 3, "text": "module Other exposing (one)\n\none = 1\n"}]}, "package": {"name": "local/example"}, "dependencies": [{"packageName": "morphir/sdk", "irVersion": "3", "distribution": {}}], "options": {"typesOnly": true, "irVersion": "3"}}}
```

```jsonrpc extension -> host
{"jsonrpc": "2.0", "id": "compile-2", "result": {"success": true, "irVersion": "3", "ir": {}, "diagnostics": [{"severity": "warning", "code": "elm.unused", "message": "This import is not used.", "location": {"uri": "src/Example.elm", "range": {"start": {"line": 0, "character": 0}, "end": {"line": 0, "character": 6}}}, "related": [{"location": {"uri": "src/Other.elm", "range": {"start": {"line": 2, "character": 0}, "end": {"line": 2, "character": 4}}}, "message": "Declared here."}]}], "modules": ["Example", "Other"]}}
```

```jsonrpc host -> extension
{"jsonrpc": "2.0", "id": 5, "method": "morphir.backend.generate", "params": {"ir": {}, "target": "avro"}}
```

```jsonrpc extension -> host
{"jsonrpc": "2.0", "id": 5, "result": {"success": true, "artifacts": [{"path": "schemas/example.avsc", "content": "{}"}, {"path": "schemas/example.bin", "content": "AAE=", "binary": true}]}}
```

```jsonrpc host -> extension
{"jsonrpc": "2.0", "id": 6, "method": "morphir.ping"}
```

```jsonrpc extension -> host
{"jsonrpc": "2.0", "id": 6, "result": {"ok": true}}
```

```jsonrpc host -> extension
{"jsonrpc": "2.0", "id": 7, "method": "morphir.shutdown"}
```

```jsonrpc extension -> host
{"jsonrpc": "2.0", "id": 7, "result": {}}
```

```jsonrpc host -> extension
{"jsonrpc": "2.0", "method": "morphir.exit"}
```
