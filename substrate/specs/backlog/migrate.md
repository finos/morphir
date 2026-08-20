# Migrate

The `substrate migrate` command group converts specification modules between
substrate's native markdown format and external representation formats.
Currently the only supported target is **Morphir IR**, with additional formats
planned for the future.

## `migrate from morphir`

```
substrate migrate from morphir <ir-file> [--output <dir>]
```

Reads a Morphir IR JSON file and writes one markdown module file per Morphir
module found in the IR.

### Arguments

| Argument    | Description                            |
| ----------- | -------------------------------------- |
| `<ir-file>` | Path to the `morphir-ir.json` file     |

### Options

| Option                 | Default                  | Description                                           |
| ---------------------- | ------------------------ | ----------------------------------------------------- |
| `-o, --output <dir>`   | `specs/`                 | Directory to write the generated markdown files into  |
| `--overwrite`          | false                    | Overwrite existing files; errors by default           |
| `--dry-run`            | false                    | Print what would be written without touching the disk |

### Output layout

Each Morphir module is written to a single markdown file. The file path is
derived from the fully-qualified module name by converting each path segment to
kebab-case and nesting them as subdirectories under `--output`:

```
Morphir.Finance.LCR.Outflow  →  specs/morphir/finance/lcr/outflow.md
```

For further details look at [this mapping document](migrate/morphir-mapping.md).

---

## `migrate to morphir`

TODO