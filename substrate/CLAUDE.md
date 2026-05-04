# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Important Instruction

- When implementing a new feature or changing an existing one always update the `specs/` folder to reflect the requirements and design.

## Commands

```bash
npm run build        # Compile TypeScript → dist/
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

## Important Notes

- TypeScript strict mode, ES modules (`"type": "module"` in package.json)
- Tests live in `test/**/*.test.ts` with 10-second timeout (vitest)
- Compiled output goes to `dist/`; the CLI binary is `dist/cli.js`
- No AI co-authors in commits (see root `CLAUDE.md` at the parent repo level for EasyCLA requirements)
