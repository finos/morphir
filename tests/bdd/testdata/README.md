# Test Fixtures

This directory contains morphir IR test fixtures for BDD testing.

## Sources

### morphir-elm/
Fixtures generated from the [finos/morphir-elm](https://github.com/finos/morphir-elm)
reference model using `morphir-elm make`.

### v1/, v2/, v3/
Hand-crafted minimal fixtures for testing format version compatibility:
- **v1**: Legacy format with snake_case tags (e.g., "unit", "variable")
- **v2**: Transitional format
- **v3**: Current format with PascalCase tags (e.g., "Unit", "Variable")

## Regenerating Fixtures

Run the fetch script to regenerate fixtures:
```bash
./scripts/fetch-fixtures.sh
```

## License

These fixtures are used for testing purposes only.
The morphir-elm fixtures are subject to the Apache 2.0 license from finos/morphir-elm.
