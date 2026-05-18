# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Important Instructions

- When presenting multiple options for the user to choose between (e.g. during grilling sessions, design discussions, or any enumerated choice), label them with latin letters or short descriptive tags — never Greek letters.
- When implementing a new feature or changing an existing one always update the `specs/` folder to reflect the requirements and design.
- **Minimum 7-day package age (transitive too).** Never add or upgrade an
  npm dependency — direct *or transitive* — to a version published less
  than seven days ago. Brand-new releases get yanked or get
  supply-chain-compromised; the seven-day soak is our line of defence.
  Workflow when adding/bumping a dep:
  1. Before installing, check `npm view <pkg> time --json` for the
     candidate version; pick an older patch or wait if it's too young.
  2. After installing, run **`node scripts/check-ages-deep.mjs`** — it
     walks every package in `node_modules/` and `web/node_modules/`
     (730+ entries) and exits non-zero if anything is younger than 7 days.
     This is the script that matters; it catches transitive deps that
     direct-only audits miss (e.g. `rollup` arriving via `vite`).
  3. If a direct dep's `^` / `~` range would resolve to a too-young
     version, pin it to an exact version (no caret/tilde).
  4. If a *transitive* dep is too young, pin it via the `overrides` field
     in the relevant `package.json` (`web/package.json` for the SPA tree,
     root `package.json` for the CLI tree). Document the rationale in a
     `comment_overrides` sibling so the next person knows why and when to
     revisit. Re-run the deep audit after `npm install`.

  `scripts/check-ages.mjs` (direct-only) and
  `scripts/check-range-risk.mjs` (latest-satisfying probe) exist as
  faster sanity checks but **are not sufficient on their own**;
  `check-ages-deep.mjs` is the source of truth.
- **Keep the bundled AI-assistant instructions in sync with the CLI.** Whenever you add, rename, remove, or change the behavior of a `substrate` command (especially the `refactor` subcommands), update *both* of these files in the same change so users who consume substrate via `substrate install` get an accurate skill:
  - `assets/ai-instructions/claude/substrate-cli/SKILL.md` — the Claude skill.
  - `assets/ai-instructions/copilot/substrate-cli.instructions.md` — the GitHub Copilot path-scoped instructions.
  These are shipped with the npm package and copied into the consumer's project by `substrate init` and `substrate install`. If the spec under `specs/tools/cli/` changes but these files do not, the change is incomplete.

## Commands

```bash
npm run build        # Build CLI (tsc → dist/) and web UI (vite → assets/web/)
npm run build:cli    # CLI only
npm run build:web    # Web UI only (Vite production build)
npm run dev:web      # Live dev: substrate dev :5173 + Vite HMR on :5174
npm run web:install  # Install web/ dependencies
npm run test         # Run all tests (vitest)
npm run test:watch   # Watch mode
npm run lint         # Markdown lint + link validation
npm run lint:md      # Markdown structure only
npm run lint:links   # Internal link resolution only
```

Run a single test file:
```bash
npx vitest run test/stages/typecheck.test.ts
```

## Project Overview

This is **substrate**: an LLM-native executable specification language. The project is part of an umbrella
project called Morphir so it's sometimes referred to as **morphir-substrate**. The project lives under the 
morphir repo, but it should treated as a standalne project.

### Specs (`specs/`)

The language specification itself lives in `specs/language/concepts/` and `specs/language/expressions/` as markdown files — they are both the source of truth and test input for the pipeline.

### Web UI (`web/`)

The `substrate dev` development UI is a Vite + React + TypeScript SPA
under `web/`. `vite build` emits a self-contained bundle into
`assets/web/`, which `src/commands/dev.ts` serves as static files in
production.

Layout and conventions (one folder per component, CSS modules, brand
tokens via `branding/tokens.css`) are documented in `web/README.md`.
Keep `web/src/types.ts` in sync with the JSON shapes served by
`src/commands/dev.ts`.

## Important Notes

- TypeScript strict mode, ES modules (`"type": "module"` in package.json)
- Tests live in `test/**/*.test.ts` with 10-second timeout (vitest)
- Compiled output goes to `dist/`; the CLI binary is `dist/cli.js`
- No AI co-authors in commits (see root `CLAUDE.md` at the parent repo level for EasyCLA requirements)
