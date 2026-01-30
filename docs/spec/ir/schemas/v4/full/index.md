---
title: "Full Schema"
linkTitle: "Full Schema"
weight: 20
description: "Complete Morphir IR JSON Schema for format version 4 (draft)"
---

# Morphir IR Schema Version 4 - Complete Schema

This page contains the complete JSON schema definition for Morphir IR format version 4 (draft).

## Download

You can download the schema file directly:
- YAML: [morphir-ir-v4.yaml](/schemas/morphir-ir-v4.yaml)
- JSON: [morphir-ir-v4.json](/schemas/morphir-ir-v4.json)

## Interactive Viewer

For an interactive browsing experience, see the [Interactive Schema Viewer](./schema-viewer/).

## Usage

This schema can be used to validate Morphir IR JSON files in format version 4:

```bash
# Using Python jsonschema (recommended for YAML schemas)
pip install jsonschema pyyaml requests
python -c "import json, yaml, jsonschema, requests; \
  schema = yaml.safe_load(requests.get('https://morphir.finos.org/schemas/morphir-ir-v4.yaml').text); \
  data = json.load(open('your-morphir-ir.json')); \
  jsonschema.validate(data, schema); \
  print('✓ Valid Morphir IR')"
```

## References

- [Schema Version 4 Documentation](../)
- [What's New in V4](../whats-new/)
- [Document Tree Files](../document-tree-files/)
- [Migration Guide](../../migration-guide/)
- [Morphir IR Specification](../../../morphir-ir-specification/)
