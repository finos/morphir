---
applyTo: "horizontals/typescript/**,src/language/expressions/**"
---

# TypeScript Horizontal Regeneration

The files under `src/language/expressions/` are **generated** from the horizontal
package at `horizontals/typescript/`. Do not edit them directly.

To regenerate after changing a horizontal lambda or adding a new operation:

1. `node dist/cli.js context specs/language/expressions/<type>.md --horizontal horizontals/typescript/`
2. Read the composed output; extract each operation's anchor, arity, and TypeScript lambda.
3. Rewrite `src/language/expressions/<type>.ts` using the template in
   `assets/ai-instructions/claude/ts-horizontal-regen/SKILL.md`.
4. `npm run build && node dist/cli.js verify specs/language/expressions/ --quiet`
5. If any test-stage errors appear, fix the lambda or the spec before committing.

The horizontal file format: each `## [OperationName](spec-anchor)` section contains
a fenced `ts` block with a typed arrow function whose parameters match the spec's
`#### Inputs` parameter names exactly.
