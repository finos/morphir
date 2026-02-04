# Documentation Decoration Example

This example demonstrates a structured decoration schema for adding documentation to IR nodes.

## Schema Definition

The decoration type is defined in `src/Types.elm`:

```elm
type alias Documentation =
    { description : String
    , tags : List String
    , links : List Link
    }

type alias Link =
    { label : String
    , url : String
    }
```

## Usage

1. **Generate the IR:**
   ```bash
   cd examples/decorations/documentation
   morphir-elm make -o morphir-ir.json
   ```

2. **Register the decoration type:**
   ```bash
   morphir decoration type register documentation \
     -i morphir-ir.json \
     -e "Documentation.Decoration:Types:Documentation" \
     --display-name "Documentation" \
     --description "Structured documentation decoration"
   ```

3. **Set up in your project:**
   ```bash
   morphir decoration setup docs --type documentation
   ```

4. **Add decoration values:**
   Edit the generated `docs-values.json` file (see `example-values.json` for format).

## Example Value File

See `example-values.json` for an example decoration values file with structured data.
