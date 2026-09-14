# Distributions

## distributions-0001: Format version spellings {node=FormatVersion}

Governed by `docs/spec/ir/format-version.md` and its generated corpus. Integer 4 is canonical for 4.0.0.

```yaml canonical
4
```

```json canonical
4
```

```json accepted
"4.0.0"
```

```json rejected diagnostic=invalid_format_version_syntax
"4.0.0-beta"
```

```json rejected diagnostic=unsupported_format_version_revision
"4.1.0"
```

## distributions-0002: Empty library {node=Distribution}

```yaml canonical
formatVersion: 4
distribution:
  Library:
    packageName: example
    dependencies: {}
    def:
      modules: {}
```

```json canonical
{ "formatVersion": 4, "distribution": { "Library": { "packageName": "example", "dependencies": {}, "def": { "modules": {} } } } }
```

```json accepted
{ "distribution": { "Library": { "packageName": "example", "dependencies": {}, "def": { "modules": {} } } }, "formatVersion": 4 }
```

## distributions-0003: A v3 tagged-array distribution is not a v4 document {node=Distribution}

`tests/bdd/fixtures/ir/v4/v4-library-distribution.json` carried this shape. Bead morphir-ir-v4-stabilize.11.

```json rejected diagnostic=invalid_distribution_shape
{ "formatVersion": 4, "distribution": ["Library", "example/v4-test", {}, { "modules": [] }] }
```

## distributions-0004: Complete library, JSON and YAML agree {node=Distribution}

The published complete example and its YAML rendering are the same distribution. Both write record fields under `fields` (decision 0004), the SDK as `morphir/SDK` (decision 0011), and the list function's `parameterType` (decision 0007).

`website/static/ir/examples/v4/complete-example.json` is the human-readable form the docs site publishes: it is pretty-printed and spells its format version `"4.0.0"`, both of which a reader accepts and a writer never emits, so it is an `accepted` spelling. The `json canonical` fence below is the writer's own output for the same distribution, on one line with the integer format version (distributions-0001). The YAML file stays canonical: it is the reference text form.

```text accepted
website/static/ir/examples/v4/complete-example.json
```

```json canonical
{ "formatVersion": 4, "distribution": { "Library": { "packageName": "regulation", "dependencies": { "morphir/SDK": { "modules": { "basics": { "types": { "int": { "OpaqueTypeSpecification": {} }, "float": { "OpaqueTypeSpecification": {} }, "bool": { "OpaqueTypeSpecification": {} } }, "values": { "add": { "inputs": { "a": "morphir/SDK:basics#int", "b": "morphir/SDK:basics#int" }, "output": "morphir/SDK:basics#int" } } }, "list": { "types": { "list": { "TypeAliasSpecification": { "typeParams": ["a"], "typeExp": { "Reference": ["morphir/SDK:list#list", "a"] } } } }, "values": { "map": { "inputs": { "f": { "Function": { "parameterType": "a", "returnType": "b" } }, "list": { "Reference": ["morphir/SDK:list#list", "a"] } }, "output": { "Reference": ["morphir/SDK:list#list", "b"] } } } } } } }, "def": { "modules": { "u-s/f-r-2052-a/data-tables": { "Public": { "types": { "data-tables": { "Public": { "TypeAliasDefinition": { "typeParams": [], "typeExp": { "Record": { "fields": { "inflows": "regulation:u-s/f-r-2052-a/data-tables#inflows", "outflows": "regulation:u-s/f-r-2052-a/data-tables#outflows", "supplemental": "regulation:u-s/f-r-2052-a/data-tables#supplemental" } } } } } }, "inflows": { "Public": { "TypeAliasDefinition": { "typeParams": [], "typeExp": { "Record": { "fields": { "assets": { "Reference": ["morphir/SDK:list#list", "regulation:u-s/f-r-2052-a/data-tables/inflows#assets"] } } } } } } } }, "values": { "calculate-total": { "Public": { "ExpressionBody": { "inputTypes": { "tables": "regulation:u-s/f-r-2052-a/data-tables#data-tables" }, "outputType": "morphir/SDK:basics#float", "body": { "Literal": { "FloatLiteral": 0.0 } } } } } }, "doc": "Data tables module for regulatory reporting" } } } } } } }
```

```text canonical
spec/ir/mck/documents/complete-example.yaml
```

## distributions-0005: The SDK dependency is keyed morphir/SDK {node=Distribution}

Decision 0011. `morphir/sdk` is a valid name for some other package, so it is not rejected; it is simply not the SDK.

```yaml canonical
formatVersion: 4
distribution:
  Library:
    packageName: example
    dependencies:
      morphir/SDK:
        modules: {}
    def:
      modules: {}
```

```json canonical
{ "formatVersion": 4, "distribution": { "Library": { "packageName": "example", "dependencies": { "morphir/SDK": { "modules": {} } }, "def": { "modules": {} } } } }
```
