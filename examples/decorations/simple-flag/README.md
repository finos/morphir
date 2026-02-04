# Simple Flag Decoration Example

This is a minimal example of a decoration schema that provides a simple boolean flag.

## Schema Definition

The decoration type is defined in `src/Types.elm`:

```elm
type alias Flag = Bool
```

## Usage

1. **Generate the IR:**
   ```bash
   cd examples/decorations/simple-flag
   morphir-elm make -o morphir-ir.json
   ```

2. **Register the decoration type:**
   ```bash
   morphir decoration type register simpleFlag \
     -i morphir-ir.json \
     -e "Simple.Flag.Decoration:Types:Flag" \
     --display-name "Simple Flag" \
     --description "A simple boolean flag decoration"
   ```

3. **Set up in your project:**
   ```bash
   morphir decoration setup myFlag --type simpleFlag
   ```

4. **Add decoration values:**
   Edit the generated `myFlag-values.json` file:
   ```json
   {
     "My.Package:Foo:bar": true,
     "My.Package:Foo:baz": false
   }
   ```

## Example Value File

See `example-values.json` for an example decoration values file.
