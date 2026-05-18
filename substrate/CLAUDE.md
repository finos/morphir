# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Important Instructions

- When presenting multiple options for the user to choose between (e.g. during grilling sessions, design discussions, or any enumerated choice), label them with latin letters or short descriptive tags — never Greek letters.
- When implementing a new feature or changing an existing one always update the `specs/` folder to reflect the requirements and design.
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
