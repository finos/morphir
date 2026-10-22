# Agent skills

Shared skills follow the [Agent Skills specification](https://agentskills.io/specification).
Their instructions use ordinary file access, terminal commands, and available tracker connectors.

## Available skills

| Skill | Purpose |
|---|---|
| [build-master](build-master/SKILL.md) | Fast correctness feedback, CI/CD execution planning, check placement, artifact reuse, and release assurance |
| [project-management](project-management/SKILL.md) | Initiative and open-work reports; priorities, dependencies, and task management across beads and GitHub Issues |
| [code-reviewer](code-reviewer/SKILL.md) | Review MoonBit changes, package structure, tests, builds, and project standards |

### rich-designs and frontend-design

- [rich-designs](rich-designs/SKILL.md): author, validate, preserve and land rich HTML designs.
- [frontend-design](frontend-design/SKILL.md): Anthropic's visual-design guidance, applied within the existing brief
  and repository conventions. [Pinned upstream source and license](frontend-design/UPSTREAM.md).

Canonical files live under `.agents/skills/`; `.github/skills/` and `.claude/skills/` expose the same definitions.

### Archify across agents

[Archify](archify/SKILL.md) creates validated architecture, workflow, sequence, data-flow and lifecycle diagrams.
The complete package is vendored in `.agents/skills/archify/`, including its renderers, schemas, references,
examples, viewer assets and licenses. [Pinned upstream source](archify/UPSTREAM.md) records version 3.2.0 and
the exact revision. No global skill or npm installation is needed to run the renderer.

Use [rich-designs](rich-designs/SKILL.md) to combine diagrams with explanatory prose and integrate them into
the existing docs site. Mermaid keeps small diagrams editable, SVG provides accessible rendered content, and
Archify supplies richer diagrams and verification. Follow the
[repository diagram workflow](rich-designs/references/repository.md#narrative-and-diagram-workflow), including
its `.dev/` output and beads recovery rules. The upstream standalone viewer does not replace the docs template.

| Agent | Project discovery path | Provider documentation |
|---|---|---|
| Codex | `.agents/skills/archify/` | [Skills](https://learn.chatgpt.com/docs/build-skills) |
| Claude Code | `.claude/skills/archify/` | [Skills](https://code.claude.com/docs/en/skills) |
| GitHub Copilot | `.github/skills/archify/` | [Skills](https://docs.github.com/en/copilot/how-tos/copilot-on-github/customize-copilot/customize-cloud-agent/add-skills) |
| Cursor | `.agents/skills/archify/` | [Skills](https://cursor.com/docs/skills) |
| Gemini CLI | `.gemini/skills/archify/` | [Skills](https://geminicli.com/docs/cli/using-agent-skills/) |
| Google Antigravity | `.agents/skills/archify/` | [Skills](https://www.antigravity.google/docs/skills) |
| Grok | `.grok/skills/archify/` | [Skills](https://docs.x.ai/build/features/skills-plugins-marketplaces) |
| Muse Code | `.agents/skills/archify/` | [Skills](https://meta-models.github.io/muse-code-sdk/next/guides/extend/skills/) |
| Devin CLI and Desktop | `.devin/skills/archify/` | [CLI skills](https://docs.devin.ai/cli/extensibility/skills/overview), [Desktop skills](https://docs.devin.ai/desktop/cascade/skills) |
| Windsurf | `.windsurf/skills/archify/` | [Skills](https://docs.devin.ai/desktop/cascade/skills) |

Every alias links to the whole canonical directory so the renderer and relative resources remain available.
Checkouts must preserve Git symlinks. Where symlinks or native skill discovery are unavailable, use:

```text
Read .agents/skills/archify/SKILL.md and .agents/skills/rich-designs/references/repository.md.
Use the installed Archify CLI to diagram the requested subject, retain source evidence,
and integrate accessible SVG with narrative prose in the approved docs layout.
```

Native invocation can use `$archify`, `/archify` or the client's skill picker. Discovery depends on the client
version, workspace trust and enabled skill support; reload skills or start a new session after checkout updates.
Resolved paths and CLI checks do not prove that every proprietary client has loaded the skill.

### beads-companion

Preserve rich HTML designs, capture reusable discoveries and handoff notes, and sync the shared Morphir tracker.
The canonical skill is in `.agents/skills/beads-companion/`; this catalog and `.claude/skills/` link to it.
Run its helpers with `moonx scripts/beads-companion.mbtx` or `mise run beads:companion -- ...`.

**Location**: [beads-companion/SKILL.md](beads-companion/SKILL.md)


## Build-master skill and agent

The skill is the reusable CI/CD practice. The [agent profile](../agents/build-master.agent.md) defines a
named specialist, its ownership, and its handoff to a coordinator or team lead. `agents/openai.yaml` inside
a skill supplies skill UI metadata; it does not register a custom agent.

The shared [decision rubric](build-master/references/decision-rubric.md) makes the agent's reasoning
reviewable. It classifies risk and execution obligations, checks hard requirements separately, and scores
coverage, feedback, release evidence, efficiency, ownership, and recovery. Handoffs show the criteria,
evidence, confidence, unknowns, and reasons for the recommendation. A score does not grant merge or release approval.

Canonical repository sources are `.github/skills/build-master/` and `.github/agents/build-master.agent.md`.
Edit those sources rather than the discovery links. Codex and OpenCode have small native adapters that load
the shared persona. No adapter pins a model or overrides the parent's permissions.

| Client | Skill discovery | Native build-master agent |
|---|---|---|
| Codex | `.agents/skills/build-master/` | `.codex/agents/build-master.toml` |
| Claude Code | `.claude/skills/build-master/` | `.claude/agents/build-master.md` |
| Cursor | `.agents/skills/build-master/` | `.cursor/agents/build-master.md` |
| GitHub Copilot | `.github/skills/build-master/` | `.github/agents/build-master.agent.md` |
| Grok Build | `.grok/skills/build-master/` | `.grok/agents/build-master.md` |
| OpenCode | `.agents/skills/build-master/` | `.opencode/agents/build-master.md` |

These entry points follow the provider formats for [Codex](https://learn.chatgpt.com/docs/agent-configuration/subagents),
[Claude Code](https://code.claude.com/docs/en/sub-agents), [Cursor](https://cursor.com/docs/subagents),
[Copilot](https://docs.github.com/en/copilot/how-tos/copilot-on-github/customize-copilot/customize-cloud-agent/create-custom-agents),
[Grok](https://docs.x.ai/build/features/subagents), and [OpenCode](https://opencode.ai/docs/agents/).
Discovery and team capabilities depend on the installed client, version, trust, and enabled features.
Existing sessions may need to reload their agent definitions. Symlink discovery needs a checkout that preserves
links; the canonical files also work through direct reads.

Ask a supporting client to use the `build-master` agent for a bounded task. For subagent workflows, team
members, SDK integrations, or clients without native discovery, pass this prompt to the assigned worker:

```text
Act as the build-master. Read .github/agents/build-master.agent.md and follow its
persona, including .github/skills/build-master/SKILL.md and the repository reference.
Assignment: review <candidate or diff> for <desired outcome>.
Constraints and available run evidence: <details>.
Mode: review only. File ownership: none.
Return the classification, requirement results, rubric scorecard with evidence and
confidence, decisive tradeoffs, validation, and owned follow-up to the coordinator.
```

For implementation, explicitly assign the allowed files and required validation instead of review-only mode.
The agent does not assume access to its parent's history or authority. This registration creates an available
role; it does not launch a persistent worker or run qualification workflows.

## Project management across agents

The canonical directory is `.github/skills/project-management/`. It contains:

```text
project-management/
├── SKILL.md
├── agents/openai.yaml
└── references/
    ├── reporting.md
    ├── trackers.md
    └── work-management.md
```

The three discovery links below point to the whole canonical directory, so supporting references stay available.
The paths are relative to the repository root. Edit the canonical files rather than maintaining agent-specific copies.

| Agent | Discovery path in this repository | Provider documentation |
|---|---|---|
| Codex | `.agents/skills/project-management/` | [Skills](https://learn.chatgpt.com/docs/build-skills) |
| Claude Code | `.claude/skills/project-management/` | [Skills](https://code.claude.com/docs/en/skills) |
| Grok | `.grok/skills/project-management/` | [Skills](https://docs.x.ai/build/features/skills-plugins-marketplaces) |
| Muse Code | `.agents/skills/project-management/` | [Skills](https://meta-models.github.io/muse-code-sdk/next/guides/extend/skills/) |
| Cursor | `.agents/skills/project-management/` | [Skills](https://cursor.com/docs/skills) |
| GitHub Copilot | `.github/skills/project-management/` | [Skills](https://docs.github.com/en/copilot/how-tos/copilot-on-github/customize-copilot/customize-cloud-agent/add-skills) |
| Devin CLI and Desktop | `.agents/skills/project-management/` | [CLI skills](https://docs.devin.ai/cli/extensibility/skills/overview), [Desktop skills](https://docs.devin.ai/desktop/cascade/skills) |

These paths follow the linked provider documentation. Availability still depends on the client's version,
workspace trust, and enabled skill support. The optional `agents/openai.yaml` supplies Codex UI metadata;
other agents can use the Markdown instructions without it. The skill does not pre-approve tools or require
a particular model, plugin, or personal installation.

For any coding agent with repository access, including clients without skill discovery, use:

```text
Read .github/skills/project-management/SKILL.md and follow its relevant references.
Report progress for campaign:conceptual-model with workstream completion, priorities,
blockers, and ready work. Use the repository's shared beads tracker instructions.
```

Native invocation can use `$project-management` in Codex, `/project-management` in clients with slash-command
skills, or the client's skill picker. The direct-file form above is the portable fallback, including for
hosted agents where local skill discovery is unavailable. Give the agent access to this checkout and the
intended trackers, or supply an export; the skill reports missing access and partial data explicitly.

## Reuse in another project

Copy the complete `.github/skills/project-management/` directory into a skill directory supported by the
target agent. Keep `references/` with `SKILL.md`. The workflow reads the target repository's tracker, scope,
authorization, and document conventions rather than assuming Morphir's configuration.

If that project serves multiple agents, keep one canonical directory and create relative directory links
in their discovery roots. In this repository, each link target is `../../.github/skills/project-management`:

```text
.agents/skills/project-management -> ../../.github/skills/project-management
.claude/skills/project-management -> ../../.github/skills/project-management
.grok/skills/project-management   -> ../../.github/skills/project-management
```

Checkouts must preserve Git symlinks for discovery through these aliases. On systems that materialize links
as text files, read the canonical path directly or copy the full skill directory into the client's supported
location. The canonical copy remains usable without symlink support.

## Adding and checking skills

Create `.github/skills/<name>/SKILL.md` with YAML `name` and `description`, followed by Markdown instructions.
Keep vendor-specific metadata optional and read supporting references only when needed. Document the skill
in this catalog and [agent instructions](../AGENTS.md), then add discovery links appropriate to its users.

Validate frontmatter, relative resource links, and discovery from a fresh checkout. Where installed, use
the client's read-only discovery tools, such as `muse skills list --source project --trust-workspace` or
`grok inspect`. A valid document or resolved link does not by itself prove every client loads the skill.
Behavioral checks should use fixture data before changing live trackers.
