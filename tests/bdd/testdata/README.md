# Test Fixtures

This directory contains morphir IR test fixtures for BDD testing.

## Sources

### morphir-elm/cli-test-ir/
Pre-built IR test files from [finos/morphir-elm](https://github.com/finos/morphir-elm)
`tests-integration/cli/test-ir-files`. These include various IR structures for testing:
- `base-ir.json` - Basic IR structure
- `listType-ir.json` - List type handling
- `multilevelModules-ir.json` - Nested module structures
- `simpleTypeTree-ir.json` - Simple type trees
- `simpleValueTree-ir.json` - Simple value trees
- `tupleType-ir.json` - Tuple type handling

### morphir-elm/reference-model/
(Optional) Full reference model IR generated from morphir-elm using `morphir-elm make`.
Only fetched when using `--with-reference-model` flag.

### v1/, v2/, v3/
Hand-crafted minimal fixtures for testing format version compatibility:
- **v1**: Legacy format with snake_case tags (e.g., "unit", "variable")
- **v2**: Transitional format
- **v3**: Current format with PascalCase tags (e.g., "Unit", "Variable")

## Regenerating Fixtures

Run the fetch script to regenerate fixtures:
```bash
# Fetch pre-built IR test files (recommended, no npm required)
./scripts/fetch-fixtures.sh

# Also build reference model (requires npm and morphir-elm CLI)
./scripts/fetch-fixtures.sh --with-reference-model

# Skip all morphir-elm fetching (minimal fixtures only)
./scripts/fetch-fixtures.sh --skip-elm
```

## License

These fixtures are used for testing purposes only.
The morphir-elm fixtures are subject to the Apache 2.0 license from finos/morphir-elm.
