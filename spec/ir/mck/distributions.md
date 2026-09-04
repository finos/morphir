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

## distributions-0004: Complete library, JSON and YAML agree {node=Distribution status=pending}

The complete example writes record fields under a fields member, which types-0005 leaves to bead morphir-ir-v4-stabilize.1. Until that decision lands, this whole-document case is pending and its two renderings are illustrations only.

```text
website/static/ir/examples/v4/complete-example.json
```

```text
spec/ir/mck/documents/complete-example.yaml
```
