# Docs Site · UI Kit

Documentation / marketing surface for Substrate. Models the existing
material in `specs/` as a statically-rendered documentation site, plus a
landing hero and an interactive CLI demo drawn from `specs/tools/cli/commands.md`.

**What's mocked:**
- Landing hero with lattice background
- Side-nav over the specs corpus (Concepts / Expressions / Tools)
- Long-form reading view of a concept page (Decision Table)
- Embedded `substrate` CLI terminal demo
- Footer with FINOS / project attribution

**Files:**
- `index.html` — single-page click-through
- `DocsSite.jsx` — shell, routing stub
- `DocsNav.jsx` — corpus sidebar
- `DocsPage.jsx` — content pages (landing + decision-table)
- `CliDemo.jsx` — scripted terminal
