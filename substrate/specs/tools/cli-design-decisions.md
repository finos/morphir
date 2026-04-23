# CLI Design Decisions

Design decisions for the `substrate verify` CLI tool.

## Source Structure Mirrors Spec Structure

The TypeScript source tree under `src/` mirrors the layout of
`specs/language/`:

| Spec path | Source path | Responsibility |
| --- | --- | --- |
| `language/concepts/` | `src/language/concepts/` | Parse and validate each concept kind |
| `language/expressions/` | `src/language/expressions/` | Operation evaluators and type metadata |
| `tools/cli.md` | `src/cli.ts` | Commander entry point |

Each concept module (e.g., `src/language/concepts/operation.ts`) exports
functions to **detect** a concept from an MDAST heading, **parse** it
into a typed AST node, and supply **lint rules** specific to that
concept. Each expression module (e.g., `src/language/expressions/number.ts`)
registers operations by their spec anchor name and provides an evaluator.

## Verification Pipeline

The `verify` command runs six stages in order. Each stage produces
diagnostics without halting the pipeline (unless parsing fails fatally).

1. **Parse** — read the entry markdown file and convert it to an MDAST
   tree via unified / remark-parse / remark-gfm.
2. **Include** — resolve document-inclusion headings recursively,
   embedding linked files and adjusting heading depths.
3. **Lint** — check structural rules: heading hierarchy, required
   sections per concept kind, table structure.
4. **References** — verify that every internal link resolves to an
   existing file and anchor.
5. **Typecheck** — validate operation arities, return types, and
   derived-operation dependencies.
6. **Test** — execute test-case tables against the built-in operation
   evaluators and report pass/fail.

State flows forward through the pipeline: parse produces a `Root`,
include expands it, and later stages read the expanded tree. Each stage
function is pure (or async-pure for I/O) and returns diagnostics plus
any data needed downstream.

## Strict TypeScript Configuration

The `tsconfig.json` enables:

- `strict` with `noUncheckedIndexedAccess` and
  `exactOptionalPropertyTypes` for maximum type safety.
- `verbatimModuleSyntax` to enforce explicit `import type` for
  type-only imports.
- `module: "NodeNext"` for correct Node.js ESM resolution with `.js`
  extensions in imports.
- `noImplicitReturns`, `noFallthroughCasesInSwitch`,
  `noPropertyAccessFromIndexSignature` for defensive coding.

## Pure Functions and No Side-Effects

All language modules, concept parsers, and stage functions are pure.
Side-effects (file I/O, console output) are isolated at the CLI
boundary in `src/cli.ts` and `src/progress.ts`. This makes every module
independently testable without mocking.

## Operation Registry

Expression modules register operations by spec anchor name. The
registry key is `{directory}/{file}#{anchor}`, e.g.,
`expressions/number.md#addition-operation`. User-module links are
resolved to this canonical form by extracting the last two path
segments and the anchor from the URL.

## Test Strategy

Tests target real-world edge cases rather than synthetic coverage:

- Parse actual spec files and verify the extracted structure.
- Feed malformed markdown to the linter and check diagnostics.
- Break links and confirm the reference checker reports them.
- Run the Boolean and Number truth tables through the evaluators.
- Verify the full pipeline against the `examples/order-total.md` user
  module.
