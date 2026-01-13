# Decoration Test Fixtures

This directory contains test fixtures for decoration functionality.

## Structure

- `schemas/` - Decoration schema IR files for testing
- `values/` - Decoration value files for testing
- `configs/` - Project configuration files with decoration configs

## Test Fixtures

### Simple Flag Schema

- `schemas/simple-flag-ir.json` - IR for a simple boolean flag decoration
- `values/simple-flag-values.json` - Example values for simple flag decoration

### Documentation Schema

- `schemas/documentation-ir.json` - IR for a documentation decoration
- `values/documentation-values.json` - Example values for documentation decoration

### Edge Cases

- `values/empty.json` - Empty decoration values file
- `values/invalid-fqname.json` - Invalid FQName format (for error testing)
- `values/multiple-types.json` - Multiple decoration types in one file

## Usage in Tests

These fixtures are used by BDD tests to verify decoration functionality:

- Loading decoration IR files
- Validating decoration values
- Querying decorations
- CLI command testing
