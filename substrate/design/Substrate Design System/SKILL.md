---
name: substrate-design
description: Use this skill to generate well-branded interfaces and assets for Substrate, either for production or throwaway prototypes/mocks/etc. Contains essential design guidelines, colors, type, fonts, assets, and UI kit components for prototyping.
user-invocable: true
---

Read the README.md file within this skill, and explore the other available files.

If creating visual artifacts (slides, mocks, throwaway prototypes, etc), copy assets out and create static HTML files for the user to view. If working on production code, you can copy assets and read the rules here to become an expert in designing with this brand.

If the user invokes this skill without any other guidance, ask them what they want to build or design, ask some questions, and act as an expert designer who outputs HTML artifacts _or_ production code, depending on the need.

## Quick orientation for Substrate

- Substrate is an **LLM-native executable specification language**. Specs *are* the program — markdown documents rendered as both documentation and dataflow graphs.
- The brand grammar is **three things**: the triangular A₂ lattice pattern, two rounded polylines (blue `#16A2DC` + orange `#F26A21`) tracing partial hexagons, and a desaturated pine-green surface system on paper.
- **Voice:** third-person, declarative, RFC-like. No marketing copy, no emoji, no exclamation marks, no "you/we". Concepts are Title Cased as entities (Decision Table, Provenance, If-Then-Else).
- **Type:** Fraunces (display), Inter (body), JetBrains Mono (code). All three are Google Fonts substitutions — flag this if the user cares.
- **Icons:** Lucide (CDN) as a substitution; no icons in the source material.

## Files to look at

- `README.md` — full context, CONTENT / VISUAL / ICONOGRAPHY sections
- `colors_and_type.css` — tokens. Import this and use the CSS variables.
- `assets/logo.svg`, `assets/logo-mono-ink.svg`, `assets/logo-lockup.svg`
- `assets/lattice-background.js` — drop-in triangular-lattice canvas
- `ui_kits/spec-editor/` — markdown-native debugger + impact-analysis surface
- `ui_kits/docs-site/` — landing + documentation + CLI demo
- `reference/` — the author's original style reference (verbatim)

## Do

- Start from the tokens in `colors_and_type.css` — do not introduce new colours without reason.
- Use the lattice as the *one* recurring motif for landing / cover surfaces.
- Keep UI surfaces mostly paper-on-paper; use blue/orange as signal accents, never decoration.
- Link liberally — in Substrate prose, every type and operation is a markdown link.

## Don't

- Don't introduce emoji, stock photos, gradient hero backgrounds, or bluish-purple washes.
- Don't add benefit-oriented marketing copy ("Supercharge…", "Unlock…").
- Don't use scale transforms on text for animation; fade + small translate only.
- Don't put coloured left-borders on cards, or drop shadows heavier than `--shadow-3`.
