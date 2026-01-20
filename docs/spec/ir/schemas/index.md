---
title: "JSON Schemas"
linkTitle: "Schemas"
weight: 2
description: "JSON schema definitions for Morphir IR format versions"
---

# Morphir IR JSON Schemas

This directory contains formal JSON schema specifications for all supported format versions of the Morphir IR (Intermediate Representation).

## Schema Files

The schemas are available in both YAML and JSON formats at SEO-friendly URLs:

| Version | YAML | JSON |
|---------|------|------|
| v4 (Draft) | [morphir-ir-v4.yaml](/schemas/morphir-ir-v4.yaml) | [morphir-ir-v4.json](/schemas/morphir-ir-v4.json) |
| v3 (Current) | [morphir-ir-v3.yaml](/schemas/morphir-ir-v3.yaml) | [morphir-ir-v3.json](/schemas/morphir-ir-v3.json) |
| v2 | [morphir-ir-v2.yaml](/schemas/morphir-ir-v2.yaml) | [morphir-ir-v2.json](/schemas/morphir-ir-v2.json) |
| v1 | [morphir-ir-v1.yaml](/schemas/morphir-ir-v1.yaml) | [morphir-ir-v1.json](/schemas/morphir-ir-v1.json) |

Use YAML for better readability or JSON for maximum tool compatibility.

## Format Version Differences

### Version 1 → Version 2

**Tag Capitalization:**
- Distribution: `"library"` → `"Library"`
- Access control: `"public"/"private"` → `"Public"/"Private"`
- Type tags: `"variable"` → `"Variable"`, `"reference"` → `"Reference"`, etc.

**Structure Changes:**
- Modules changed from `{"name": ..., "def": ...}` objects to `[modulePath, accessControlled]` arrays

### Version 2 → Version 3

**Tag Capitalization:**
- Value expression tags: `"apply"` → `"Apply"`, `"lambda"` → `"Lambda"`, etc.
- Pattern tags: `"as_pattern"` → `"AsPattern"`, `"wildcard_pattern"` → `"WildcardPattern"`, etc.
- Literal tags: `"bool_literal"` → `"BoolLiteral"`, `"string_literal"` → `"StringLiteral"`, etc.

## Usage

### Validation

The schemas can be used to validate Morphir IR JSON files. Note that due to the complexity and recursive nature of these schemas, validation can be slow with some validators.

#### Using Python jsonschema

```bash
pip install jsonschema pyyaml requests

python3 << 'EOF'
import json
import yaml
import requests
from jsonschema import validate

# Load schema from URL
schema = yaml.safe_load(
    requests.get('https://morphir.finos.org/schemas/morphir-ir-v3.yaml').text
)

# Load Morphir IR JSON
with open('morphir-ir.json', 'r') as f:
    data = json.load(f)

# Validate
validate(instance=data, schema=schema)
print("✓ Valid Morphir IR")
EOF
```

#### Using Node.js ajv

```bash
npm install -g ajv-cli ajv-formats

# Download JSON schema directly (no conversion needed)
curl -o morphir-ir-v3.json https://morphir.finos.org/schemas/morphir-ir-v3.json

# Validate
ajv validate -s morphir-ir-v3.json -d morphir-ir.json
```

#### Using sourcemeta jsonschema CLI

The [sourcemeta/jsonschema](https://github.com/sourcemeta/jsonschema) CLI is a fast, cross-platform JSON Schema validator written in C++. It supports all JSON Schema versions and provides excellent error messages.

**Installation:**

```bash
# Using npm
npm install -g @sourcemeta/jsonschema

# Using pip
pip install jsonschema-cli

# Using Homebrew (macOS/Linux)
brew install sourcemeta/apps/jsonschema

# Using Docker
docker pull sourcemeta/jsonschema
```

**Basic validation:**

```bash
# Download the schema
curl -o morphir-ir-v3.json https://morphir.finos.org/schemas/morphir-ir-v3.json

# Validate a Morphir IR file
jsonschema validate morphir-ir-v3.json morphir-ir.json
```

**Validate with detailed output:**

```bash
# Verbose mode shows validation progress
jsonschema validate morphir-ir-v3.json morphir-ir.json --verbose

# JSON output for programmatic processing
jsonschema validate morphir-ir-v3.json morphir-ir.json --json
```

**Validate multiple files or directories:**

```bash
# Validate all JSON files in a directory
jsonschema validate morphir-ir-v3.json ./output/

# Validate specific files
jsonschema validate morphir-ir-v3.json file1.json file2.json file3.json
```

**Fast mode (for large files):**

```bash
# Prioritize speed over detailed error messages
jsonschema validate morphir-ir-v3.json morphir-ir.json --fast
```

**Using Docker:**

```bash
# Mount current directory and validate
docker run --rm -v "$PWD:/data" sourcemeta/jsonschema \
  validate /data/morphir-ir-v3.json /data/morphir-ir.json
```

### Quick Structural Check

For a quick check without full validation, you can verify basic structure:

```python
import json

def check_morphir_ir(filepath):
    with open(filepath) as f:
        data = json.load(f)
    
    # Check format version
    version = data.get('formatVersion')
    assert version in [1, 2, 3], f"Unknown format version: {version}"
    
    # Check distribution structure
    dist = data['distribution']
    assert isinstance(dist, list) and len(dist) == 4
    assert dist[0] in ["library", "Library"], f"Unknown distribution type: {dist[0]}"
    
    # Check package definition
    pkg_def = dist[3]
    assert 'modules' in pkg_def
    
    print(f"✓ Basic structure valid: Format v{version}, {len(pkg_def['modules'])} modules")

check_morphir_ir('morphir-ir.json')
```

## Integration with Tools

These schemas can be used to:

1. **Generate Code**: Create type definitions and parsers for various programming languages
2. **IDE Support**: Provide autocomplete and validation in JSON editors
3. **Testing**: Validate generated IR in test suites
4. **Documentation**: Generate human-readable documentation from schema definitions

## Schema Format

The schemas are written in YAML format for better readability and include:

- Comprehensive inline documentation
- Type constraints and patterns
- Required vs. optional fields
- Recursive type definitions
- Enum values for tagged unions

## Contributing

When updating the IR format:

1. Update the appropriate schema file(s) to match the upstream schemas from the [main Morphir repository](https://github.com/finos/morphir/tree/main/docs/schemas)
2. Update the format version handling in the .NET codec implementation if needed
3. Add migration logic in the codec files if needed
4. Update this README with the changes
5. Test the schema against example IR files

## References

- [Morphir Project](https://morphir.finos.org/)
- [Morphir Repository](https://github.com/finos/morphir)
- [JSON Schema Specification](https://json-schema.org/)
- [YAML Format](https://yaml.org/)

