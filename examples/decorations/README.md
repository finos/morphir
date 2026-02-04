# Decoration Examples

This directory contains example decoration schemas and value files to help you understand how to use Morphir decorations.

## Structure

- `schemas/` - Example decoration schema IR files
- `values/` - Example decoration value files
- `simple-flag/` - Complete example: Simple boolean flag decoration
- `documentation/` - Complete example: Documentation decoration with structured metadata

## Quick Start

1. **Create a decoration schema** (see `schemas/` for examples)
2. **Generate the IR** using `morphir make`
3. **Register the type** using `morphir decoration type register`
4. **Set up in your project** using `morphir decoration setup --type <type-id>`
5. **Add values** by editing the decoration values JSON file

## Example: Simple Flag Decoration

See `simple-flag/` for a complete working example of a boolean flag decoration.

## Example: Documentation Decoration

See `documentation/` for a complete example of a structured documentation decoration.
