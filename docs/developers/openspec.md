---
id: openspec-workflow
title: OpenSpec change proposals
---

The umbrella repository uses the shared `html-design` bundle from
[Mission Control](https://github.com/moonrockz/mission-control/tree/main/apps/openspec-ext).
A new change produces a proposal, capability specs, a standalone `design.html`
with inline CSS and SVG, and implementation tasks. Existing changes retain
their recorded schema. Beads remains the task tracker, and the repository's
contribution and approval rules apply.

## Setup

Review and trust `.config/mise/config.toml`, then follow the checkout setup in
[CONTRIBUTING.md](https://github.com/finos/morphir/blob/main/CONTRIBUTING.md).
The repository already pins Node and MoonBit. Install the OpenSpec dependencies:

```sh
mise install node bun http:moonbit npm:@fission-ai/openspec
mise run openspec:verify
```

OpenSpec is pinned to 1.14.3. The existing MoonBit 0.10.16+b1a0e846e toolchain
runs the shared checker. Mise's existing postinstall completes that SDK on
Linux, macOS Apple Silicon and Windows x64. Verification initializes its
package registry with `moon update`, then checks the ownership lock, validates
the schema and changes, and runs the checker's Gherkin and setup-isolation tests.
An empty spec/change tree reports no items to validate. The same task runs in
`mise run check` and the docs CI job.

## Start a change

```sh
mise exec -- openspec new change <change-name>
mise exec -- openspec instructions design --change <change-name>
```

No schema override is needed. The design instructions target `design.html`.
Use the generated core skills to propose, explore, apply, update, sync specs and
archive changes. Skills are checked in for portable/Codex agents, Claude,
Copilot, Cursor, Grok, Gemini and OpenCode. To regenerate them, run:

```sh
mise run openspec:setup
```

Setup uses an isolated core profile and preserves personal OpenSpec settings
and other agent skills. Keep repository context and policy in
`openspec/config.yaml` and AGENTS.md. Link the OpenSpec change path and the
GitHub issue from the owning bead. Language implementation changes belong in
their owning repositories; adoption does not update ecosystem submodule pins.

## Update the shared bundle

`openspec/extensions.lock.json` records openspec-ext 0.1.0 and the SHA-256 of
nine managed files. Keep the schema, templates, licenses, checker and its
feature file identical to Mission Control. Git's existing LF attributes keep
those hashes stable on Windows. Do not patch the managed files locally.

The module is not published yet. From a reviewed Mission Control checkout, run:

```sh
mise exec -- moon run apps/openspec-ext/cmd -- install /absolute/path/to/morphir
mise exec -- moon run apps/openspec-ext/cmd -- check /absolute/path/to/morphir
```

Review the source revision and diff, then run `mise run openspec:verify` here.
The installer refuses unmanaged conflicts and local changes to owned files,
and writes the lock last. Fresh clones use the checked-in bundle without a
sibling checkout or an unpublished registry package.

The Apache-2.0 schema license and upstream OpenSpec MIT notice are retained in
`openspec/schemas/html-design/LICENSE` and `NOTICE`.
