---
name: rich-designs
description: Create, revise, validate, preserve and land rich HTML specifications, plans and technical reports. Use when a design needs diagrams, a readable review artifact, durable beads storage, a documentation-site home, or a PR that carries the reviewed design forward.
---

# Rich designs

Turn a design into an artifact people can read, review and recover on another machine.
Read [repository guidance](references/repository.md) and the repository's `AGENTS.md` first. They determine
where documents belong, which template to use, the tracker, and the checks and authorization for landing.

## Establish the story

Lead with the problem, intended behavior and the decisions a reviewer needs to make. Use real domain terms
and concrete examples. Distinguish proposed behavior, implemented behavior and behavior actually demonstrated
by a probe or test. Identify unresolved questions without presenting them as settled architecture.

Inspect the relevant code and existing specifications before drawing code-backed diagrams. Cite source paths,
revisions and primary references where they support a claim. A passing scalar example does not prove a whole
library pipeline, a portable artifact does not qualify every host, and successful execution does not establish
MEP or MCK compatibility. Apply those distinctions to the subject actually being designed.

Write connected narrative prose for both users and contributors. Start with what the reader wants to do and a
concrete example, then explain how the parts cooperate and why their boundaries matter. Introduce each diagram
with the question it answers and follow it with the consequence for the reader. Add contributor details after
the user journey, with links to the code and contracts. A diagram, table or task checklist does not replace prose.

## Build the document

- Start with the existing template or documentation site. Preserve its approved head, CSS, theme and navigation.
- Give sections stable IDs and a table of contents. Use descriptive headings and progressive disclosure for
  supporting evidence. Keep the main argument readable without opening every detail.
- Use tables for genuine comparisons, code blocks for concrete contracts/examples, and diagrams where they
  explain relationships or sequence better than prose. Avoid repeated card grids and walls of dependency text.
- Use Mermaid for concise flow and sequence sources, accessible SVG for portable rendered diagrams, and
  [Archify](../archify/SKILL.md) for richer diagrams with schema, source-evidence and rendering checks. Choose
  complementary views when one diagram cannot explain the subject. Include sequence diagrams when call order,
  callbacks, ownership or failure handling matters. Retain Mermaid source when used and provide an actual
  rendered diagram; Mermaid source alone is not a rendered result.
- Follow [repository diagram guidance](references/repository.md) for the installed Archify CLI, output and storage.
  Validate Archify candidates and their artifacts through its delivery gates. Give SVG a responsive viewBox,
  readable labels, an accessible title/description and a prose equivalent. Do not introduce a client-side renderer
  dependency or replace the document template to display a diagram.
- Use [frontend-design](../frontend-design/SKILL.md) for intentional visual choices within the brief. Repository
  templates, design tokens and accessibility requirements take precedence over introducing a new visual identity.
- Keep the document usable without optional scripts. Follow the repository's external-resource policy. A linked
  local diagram, image or stylesheet does not become portable merely because its parent HTML is stored in beads.

For automation, use MoonBit `.mbtx` scripts through `moonx`. Reuse existing tooling before adding another
exporter, renderer or validator. Direct invocations of existing tools remain appropriate.

## Review the rendered result

Open the actual HTML or documentation route in a browser. Inspect representative wide and narrow layouts,
tables, long identifiers, diagrams and collapsed sections. Check keyboard access for interactive controls.
Use the repository's existing browser tooling and applicable link/HTML checks; avoid downloading a new browser
stack when one is already available.

Check unique IDs, working table-of-contents anchors, relevant internal links, readable SVG labels, and unintended
horizontal overflow. Check the offline form when portability is promised. Treat console/network failures according
to whether they affect the document's required content. Do not equate a successful file write with visual review.

## Preserve the whole design

When beads owns the design, store the complete HTML in the owning bead's `design` field. Keep local copies in
the repository's designated ignored directory. Follow the repository's beads skill/guard before opening a tracker;
do not create an empty worktree-local database to make a command succeed.

Use the exact setup/export commands in [repository guidance](references/repository.md). Prefer an installed
rich-design helper that checks the issue ID and preserves text exactly. A JSON extraction fallback must reject
missing/non-text designs and avoid adding a newline. Confirm the requested issue and create its ignored working
directory first. Run each command separately and check its exit status. Never export over unmerged local edits.
Pull and recover the latest design before revising it; a field replacement is not concurrent-edit protection.
Do not assume a `moonx` executable belongs to MoonBit: moonrepo also ships a command with that name. Select the
repository's pinned launcher and runtime explicitly, and verify the command on a clean setup.

Verify the stored text against the source and recover/render it again. Embed assets needed for cross-machine
review, or explicitly inventory dependencies that must travel separately. Preserve external source links as citations.
Append a short note with the subject/revision, owning bead, retrieval command and next step. Link related tasks to
that owner. Keep reusable workflow guidance in this skill; keep campaign-specific facts in the owning bead.

When the repository owns the published design, commit it at the prescribed path and connect it to the existing
site/navigation. Record its source path and revision in beads. State which record is canonical; avoid two silently
diverging copies. Keep `docs/superpowers/` artifacts local and out of commits, as directed by the working preferences.

## Land the reviewed result

1. Inspect current work and base a focused branch on the latest default branch. Preserve unrelated work.
2. Run the checks required by the actual change. Review the diff for generated/local artifacts, source evidence,
   links, third-party provenance and template constraints.
3. Persist the design and handoff notes. Sync the correct tracker and verify success. A local update alone does
   not make the artifact available on another machine.
4. Commit only the intended tracked files with the repository's authorship/sign-off rules. Open a PR describing
   the problem, resulting behavior, review location and validation. Use the existing documentation deployment
   preview when available; do not invent a public link to a local `.dev` file.
5. Monitor checks and comments against the current PR head. Address findings within the authorized scope, rerun
   relevant checks, and update the design when the implementation changes its meaning.
6. Merge when the user has authorized landing and required gates permit it. Follow the repository's merge policy;
   do not infer administrative bypass permission from a request to land a PR. Confirm the merged state and record
   the PR, commit range and test results in the owning bead before closing completed work.

For a beads-only document, landing the design means a verified tracker push. Open a Git PR for actual tracked
changes such as a published design, site integration, skill or implementation. Do not create an empty PR for an
ignored artifact. Return a usable artifact link or bead/retrieval command, and distinguish created, pushed,
reviewable and merged states.
