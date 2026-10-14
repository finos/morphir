# Morphir MoonBit site

Generates the project site at <https://finos.github.io/morphir-moonbit/> from `docs/`, `site/` and the package
READMEs listed in `site/site.json`.

## Build and preview

From the repository root:

    mise run setup:site
    mise run build:site
    mise run dev:site

Open <http://127.0.0.1:4173/morphir-moonbit/>. `mise run check:site` checks links in the built site, and
`mise run test:site` runs the unit tests and the browser smoke test.

## Packages

- `model`: problems, routes, configuration, search entries. All targets.
- `content`: front matter, Markdown, heading anchors, Mermaid, URL mapping. Native.
- `views`: Rabbita components for every page. Native.
- `site`: turns source files into output files, and checks a built site. Native.
- `generate`: the program that reads the repository and writes `_site/`. Native.
- `check`: the program that checks a built `_site/`. Native.
- `islands`: search box, theme toggle and mobile menu. JS.
