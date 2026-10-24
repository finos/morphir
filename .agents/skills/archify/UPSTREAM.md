# Upstream source

Vendored from [tt-a1i/archify](https://github.com/tt-a1i/archify/tree/25cf37080fc8b1dbe758a4efc3935b55f3327083/archify).

- Repository: `tt-a1i/archify`
- Revision: `25cf37080fc8b1dbe758a4efc3935b55f3327083`
- Path: `archify`
- Package version: `3.2.0`
- The 203 upstream package files form the vendored baseline. Local dependency refreshes
  update the package manifest, lockfile and generated brand marks; this provenance file
  records that distinction.
- License: MIT, retained in `LICENSE`. Bundled asset notices and licenses are retained in
  `THIRD_PARTY_NOTICES.md` and their original package locations.

The full package includes the skill, renderers, schemas, references, examples, viewer assets and generated
validators. Runtime rendering does not require an npm install; development-only package scripts can refer to
the upstream repository outside this vendored directory. Use the installed CLI through the project's Node tool.
The handwritten-source inventory in `tools/typecheck-test.ts` excludes this pinned vendor directory. Keep new
project code outside the vendor package so the repository's TypeScript coverage rules continue to apply to it.

Repository instructions govern the document template, accessibility, output locations, tracker storage and
publication. Follow [repository diagram guidance](../rich-designs/references/repository.md). Keep draft output
under `.dev/`, integrate static SVG into the docs layout, and preserve editable sources and evidence. Do not
replace the approved template with a standalone viewer or modify global agent settings through this skill.

Updates are deliberate repository changes. Inspect a pinned revision, replace the complete upstream package,
preserve licenses and local provenance, compare its files with upstream, and repeat CLI/discovery checks.
Never update this copy merely because an Archify receipt advertises a newer version.
