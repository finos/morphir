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

## Package pages

A package listed in `site/site.json` is a page from its `README.md` or `README.mbt.md`. Each README below the
package directory is a page below it, for example `pkgs/morphir-scheme/spec/README.mbt.md`. A directory with both
README kinds fails the build. READMEs in `fixtures`, `_build`, `.mooncakes`, `node_modules` and `target` are skipped.
`chapters` in `site/site.json` orders a package's sub-package pages; a page it does not list sorts by its `order`
front matter, or as 1000 without one, then by title.
[Writing for the site](../../docs/WRITING_FOR_THE_SITE.md#package-chapters) describes the chapters and their checked
Scheme examples.

## Packages

- `model`: problems, routes, configuration, search entries. All targets.
- `content`: front matter, Markdown, heading anchors, Mermaid, URL mapping. Native.
- `views`: Rabbita components for every page. Native.
- `site`: turns source files into output files, and checks a built site. Native.
- `generate`: the program that reads the repository and writes `_site/`. Native.
- `check`: the program that checks a built `_site/`. Native.
- `islands`: search box, theme toggle, mobile menu, code-block copy buttons and the current-heading marker of the "On this page" rail. JS.

## Workbench at /try/

The build copies `apps/morphir-workbench/dist` to `_site/try/` and adds `<meta name="morphir-site-home" content="../">`
to its `index.html`. With that tag, the workbench breadcrumb and logo link back to the site home.
