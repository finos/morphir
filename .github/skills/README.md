# Agent skills

Shared skills follow the [Agent Skills specification](https://agentskills.io/specification).
Their instructions use ordinary file access, terminal commands, and available tracker connectors.

## Available skills

| Skill | Purpose |
|---|---|
| [project-management](project-management/SKILL.md) | Initiative and open-work reports; priorities, dependencies, and task management across beads and GitHub Issues |
| [code-reviewer](code-reviewer/SKILL.md) | Review MoonBit changes, package structure, tests, builds, and project standards |

### rich-designs and frontend-design

- [rich-designs](rich-designs/SKILL.md): author, validate, preserve and land rich HTML designs.
- [frontend-design](frontend-design/SKILL.md): Anthropic's visual-design guidance, applied within the existing brief
  and repository conventions. [Pinned upstream source and license](frontend-design/UPSTREAM.md).

Canonical files live under `.agents/skills/`; `.github/skills/` and `.claude/skills/` expose the same definitions.

### beads-companion

Preserve rich HTML designs, capture reusable discoveries and handoff notes, and sync the shared Morphir tracker.
The canonical skill is in `.agents/skills/beads-companion/`; this catalog and `.claude/skills/` link to it.
Run its helpers with `moonx scripts/beads-companion.mbtx` or `mise run beads:companion -- ...`.

**Location**: [beads-companion/SKILL.md](beads-companion/SKILL.md)


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
