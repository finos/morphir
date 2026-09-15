# Versions

## versions-0001: Reading a v3 literal into the model {node=Value version=3}

A v3 tagged array with capitalized tags decodes to the same value the v4 spelling does.

```json canonical
["Literal", {}, ["WholeNumberLiteral", 42]]
```

## versions-0002: Writing a Hole to v3 is refused {node=Value version=3 status=pending}

The CLI refuses a v4 to v3 downgrade with `unsupported_v4_downgrade`. The kit grammar has no role for a write refusal yet; plan 2 adds one, and bead morphir-diwy specifies the rules. Until then this case is prose only.

## versions-0003: One YAML document {node=FormatVersion}

The YAML profile admits exactly one document. A second document after `---`, or content after `...`, is refused rather than silently reading the first. Spec S4.

```yaml canonical
4
```

```yaml rejected diagnostic=invalid_yaml
4
---
4
```

## versions-0004: No anchors, tags, merge keys or directives {node=Distribution}

Anchors, aliases, explicit tags, merge keys, and directives are presentation and schema machinery the profile does not carry: an IR document means the same thing wherever it is read, so nothing in it may be resolved against something else. Each is refused with `unsupported_yaml_feature`. Spec S4.

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

```yaml rejected diagnostic=unsupported_yaml_feature
formatVersion: 4
distribution:
  Library:
    packageName: example
    dependencies: &empty {}
    def:
      modules: *empty
```

```yaml rejected diagnostic=unsupported_yaml_feature
formatVersion: 4
distribution:
  Library:
    packageName: example
    dependencies: !!map {}
    def:
      modules: {}
```

```yaml rejected diagnostic=unsupported_yaml_feature
formatVersion: 4
distribution:
  Library:
    packageName: example
    dependencies: {}
    def:
      <<: {}
      modules: {}
```

```yaml rejected diagnostic=unsupported_yaml_feature
%YAML 1.2
---
formatVersion: 4
distribution:
  Library:
    packageName: example
    dependencies: {}
    def:
      modules: {}
```

## versions-0005: Duplicate keys {node=Distribution}

A repeated mapping key is refused with `duplicate_member`, the same diagnostic the JSON profile reports for a repeated object member: last-one-wins would make the same bytes mean different things in different readers. Spec S4.

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

```yaml rejected diagnostic=duplicate_member
formatVersion: 4
formatVersion: 4
distribution:
  Library:
    packageName: example
    dependencies: {}
    def:
      modules: {}
```
