---
id: openspec-workflow
title: OpenSpec change proposals
---

The umbrella repository uses the shared `html-design` bundle from
[Mission Control](https://github.com/moonrockz/mission-control/tree/main/apps/tools).
A new change produces a proposal, capability specs, a standalone `design.html`
with inline CSS and SVG, and implementation tasks. Existing changes retain
their recorded schema. Beads remains the task tracker, and the repository's
contribution and approval rules apply.

## Setup

Review and trust `.config/mise/config.toml`, then follow the checkout setup in
[CONTRIBUTING.md](https://github.com/finos/morphir/blob/main/CONTRIBUTING.md).
The repository already pins Node and the `mission-control-tools` binary. Install
the OpenSpec dependencies:

```sh
mise install node bun github:moonrockz/mission-control npm:@fission-ai/openspec
mise run openspec:verify
```

OpenSpec is pinned to 1.14.3. The pinned
[`mission-control-tools` 0.1.2](https://github.com/moonrockz/mission-control/releases/tag/tools-v0.1.2)
binary checks the shared bundle and includes narrative authoring guidance.
It is a released binary, so a MoonBit toolchain change in this repository
cannot break the OpenSpec commands.
Verification runs `mission-control-tools openspec check --bundle`, which checks
the ownership lock and compares each managed file with the file in the binary,
then validates the schema and changes. An empty spec/change tree reports no
items to validate. The same task runs in `mise run check`, and the docs CI job
runs the same check and validation.

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

## Narrative designs

Write a design so a reader can follow one concrete user or system journey and
understand why each decision is needed. The project's authoring rules live in
`openspec/config.yaml`; they apply without changing the managed shared bundle.

Start with an observable problem and outcome. Carry a worked example through
the relevant stages, introducing constraints when they affect a decision.
Explain the chosen approach, its reason and the alternatives considered at
that point. Include failure and recovery paths where they change the design.
Organize this around the behavior being designed, rather than the order in
which the author investigated it.

For example, a proposed acquisition design can follow a developer who installs
Morphir without .NET, adds an F# frontend, compiles a model and generates F#. That
journey explains why the host and frontend need separate runtime arrangements.
A diagram can show the process boundary, while a failed frontend probe explains
why setup activates a complete toolchain only after readiness checks pass.

Use diagrams and examples where they clarify a boundary, state transition or
data flow. Label proposed commands and synthetic data. Distinguish behavior
observed in the code from a proposed addition. Keep decision identifiers,
requirements and testable scenarios precise. Narrative explains the contract;
it does not replace it. Put durable explanatory context for a new capability
under its spec's `Purpose` section so it survives archive.

Scale this to the change. One paragraph and an example can be enough for a
small change. Avoid invented personas, decorative diagrams and repeating the
same story in the proposal, specs and design.

The shared schema instructions and templates include narrative guidance in
[`tools-v0.1.2`](https://github.com/moonrockz/mission-control/releases/tag/tools-v0.1.2).
Morphir adopts that release through the installer and adds its project rules in
`openspec/config.yaml`. The shared extension source is
[`apps/openspec-ext/bundle.mbt`](https://github.com/moonrockz/mission-control/blob/tools-v0.1.2/apps/openspec-ext/bundle.mbt).
Further shared changes belong upstream, followed by a tools release and consumer
installation. Do not hand-edit the managed snapshot in this repository.

## Update the shared bundle

`openspec/extensions.lock.json` (format 2) records `mission-control-tools`
0.1.2 and the SHA-256 of the seven managed files: the schema, the templates,
`LICENSE` and `NOTICE`. Keep them identical to the bundle in the binary.
`.gitattributes` keeps LF line endings for `openspec/schemas/html-design/**`,
so the hashes stay stable on Windows. Do not patch the managed files locally.

To update the bundle, change the `github:moonrockz/mission-control` version in
`.config/mise/config.toml`, then run:

```sh
mise install github:moonrockz/mission-control
mise exec -- mission-control-tools openspec install
mise run openspec:verify
```

Review the diff before you commit it. The installer refuses local changes to
the managed files before it writes anything, and it writes the lock. After a
version change without `install`, `openspec:check` fails. See the
[mission-control-tools README](https://github.com/moonrockz/mission-control/blob/tools-v0.1.2/apps/tools/README.md).

The Apache-2.0 schema license and upstream OpenSpec MIT notice are retained in
`openspec/schemas/html-design/LICENSE` and `NOTICE`.
