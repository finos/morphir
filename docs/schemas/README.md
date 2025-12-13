# Morphir IR JSON Schemas

This directory contains formal JSON schema specifications for all supported format versions of the Morphir IR (Intermediate Representation).

## Schema Files

- **morphir-ir-v3.yaml**: Current format version (v3)
- **morphir-ir-v2.yaml**: Format version 2
- **morphir-ir-v1.yaml**: Format version 1

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
pip install jsonschema pyyaml

python3 << 'EOF'
import json
import yaml
from jsonschema import validate

# Load schema
with open('morphir-ir-v3.yaml', 'r') as f:
    schema = yaml.safe_load(f)

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

# Convert YAML to JSON first
python3 -c "import yaml, json; \
  json.dump(yaml.safe_load(open('morphir-ir-v3.yaml')), open('morphir-ir-v3.json', 'w'))"

# Validate
ajv validate -s morphir-ir-v3.json -d morphir-ir.json
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

1. Update the appropriate schema file(s)
2. Update the `currentFormatVersion` in `src/Morphir/IR/FormatVersion.elm`
3. Add migration logic in the codec files if needed
4. Update this README with the changes
5. Test the schema against example IR files

## References

- [Morphir IR Specification](../morphir-ir-specification.md)
- [JSON Schema Specification](https://json-schema.org/)
- [YAML Format](https://yaml.org/)
