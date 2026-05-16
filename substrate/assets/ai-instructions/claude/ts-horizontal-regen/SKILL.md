---
name: ts-horizontal-regen
description: Regenerate src/language/expressions/*.ts from the TypeScript horizontal package at horizontals/typescript/. Run when a spec operation is added, renamed, or its signature changes. Trigger on "regenerate the TypeScript evaluators", "regen from horizontal", or any mention of re-running the TS horizontal.
---

# TypeScript Horizontal Regeneration

This skill regenerates the TypeScript evaluator modules under
`src/language/expressions/` from the horizontal package at
`horizontals/typescript/`. Every generated file is gated by
`substrate verify` — if verification fails, the skill stops and
surfaces the failures for you to resolve.

## When to use

- A new operation has been added to a spec file and a corresponding
  lambda has been added to `horizontals/typescript/expressions/<type>.md`.
- An existing lambda has been corrected in the horizontal.
- You want to cut `src/language/expressions/` over to generated output
  for the first time.

Do **not** edit `src/language/expressions/*.ts` by hand after cutover —
those files are generated artifacts. Edit the horizontal instead, then
re-run this skill.

## Workflow

### 1. Compose the spec + horizontal for each module

For each expression module that has a horizontal counterpart, run:

```bash
node dist/cli.js context specs/language/expressions/<type>.md \
    --horizontal horizontals/typescript/
```

This produces a self-contained markdown document that interleaves the
spec's operation signatures with the horizontal's TypeScript snippets,
with all cross-file links rewritten as in-document anchors.

### 2. Extract operations and lambdas

Read the composed output. For each operation:

- **Anchor** (registry key): derived from the spec heading slug,
  e.g. `not-operation`, `and-operation`.
- **Inputs**: the parameter names and count from the `#### Inputs` list
  in the spec — these determine `arity` and the lambda's argument names.
- **Lambda**: the TypeScript snippet from the horizontal, a typed
  arrow function whose parameters match the spec's input names exactly.

### 3. Regenerate the TypeScript module

Write `src/language/expressions/<type>.ts` with this shape:

```typescript
/**
 * <Type> expressions — generated from horizontals/typescript/expressions/<type>.md
 * DO NOT EDIT — regenerate with the ts-horizontal-regen skill.
 */
import type { Value } from "../ast.js";
import type { OperationEvaluator } from "./index.js";

export const modulePath = "expressions/<type>.md";

export const operations: ReadonlyMap<string, OperationEvaluator> = new Map<string, OperationEvaluator>([
    [
        "<anchor>",
        {
            arity: <N>,
            evaluate: (args) => {
                const lambda = <paste lambda here>;
                return lambda(args[0] as <T0>, args[1] as <T1>, ...) as Value;
            },
        },
    ],
    // … one entry per operation
]);
```

Keep the lambda on a single line when it fits; use a block body when the
lambda spans multiple lines (e.g. the `date` module).

Also regenerate `src/language/expressions/index.ts` to import every
module that exposes `operations` and call `registerModule` for each.

### 4. Verify

```bash
npm run build && node dist/cli.js verify specs/language/expressions/ --quiet
```

If any file reports errors in the `test` stage, the regenerated lambdas
do not match the spec's truth tables. Stop, report the failures, and do
not commit. The developer must correct either the horizontal lambda or
the spec test case before proceeding.

If all files pass, the regeneration is complete.

### 5. Per-operation targeting (optional)

To regenerate a single operation during horizontal development:

```bash
node dist/cli.js context \
    specs/language/expressions/boolean.md#not-operation \
    --horizontal horizontals/typescript/
```

Read the composed output for just that operation and update only its
entry in the corresponding `.ts` file, then re-verify.

## Files involved

| Path | Role |
| ---- | ---- |
| `horizontals/typescript/substrate.json` | Horizontal package manifest |
| `horizontals/typescript/expressions/*.md` | One file per expression module; carries TypeScript lambdas |
| `specs/language/expressions/*.md` | Spec source of truth; carries signatures and test cases |
| `src/language/expressions/*.ts` | Generated output — do not edit by hand |
| `src/language/expressions/index.ts` | Generated registry assembly — do not edit by hand |

## Failure handling

When `substrate verify` rejects the regenerated output:

1. Show the failing test diagnostics to the developer.
2. Ask whether to correct the **horizontal** (wrong lambda) or the
   **spec** (wrong test case).
3. After the correction, re-run from step 1 of this workflow.
4. Do not auto-retry — each attempt is a deliberate act.
