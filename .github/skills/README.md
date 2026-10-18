# Agent Skills

This directory contains AI agent skills following the [Agent Skills specification](https://agentskills.io/specification).

## Available Skills

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

### code-reviewer

Comprehensive code review capabilities for the Morphir Moonbit monorepo.

**Location**: `code-reviewer/SKILL.md`

**Purpose**: Reviews code changes for quality, security, and adherence to project standards.

**Key Capabilities**:
- Moonbit code quality checks
- Package structure validation
- Test coverage verification
- Build configuration review
- Documentation updates check
- Security issue identification
- Mise task and CI workflow validation

## Skill Format

Each skill follows the Agent Skills specification:

```
skill-name/
└── SKILL.md          # Required: metadata (YAML) + instructions (Markdown)
```

### SKILL.md Structure

```yaml
---
name: skill-name
description: Brief description of what the skill does
license: Apache-2.0
compatibility:
  - claude
  - copilot
  - codex
  - cursor
  - windsurf
  - google-antigravity
---

# Skill documentation in Markdown
```

## Using Skills with AI Agents

Different AI agents may access skills through different mechanisms:

### Symbolic Links

To avoid duplicating skill definitions, symbolic links are created for agent-specific locations:

- `.github/copilot/` → GitHub Copilot
- `.cursorrules-*` → Cursor (root level)
- `.windsurfrules-*` → Windsurf (root level)
- `.claude/` → Claude
- `.codex/` → OpenAI Codex
- `.antigravity/` → Google Antigravity

All these link back to the canonical definitions in `.github/skills/`.

### Direct Reference

Agents can also reference skills directly:

```
Please use the code-reviewer skill from .github/skills/code-reviewer/
```

## Adding New Skills

To add a new skill:

1. Create a new directory: `.github/skills/<skill-name>/`
2. Add `SKILL.md` with proper YAML frontmatter and instructions
3. Keep the skill focused on a single capability
4. Test with multiple AI agents
5. Update `.github/AGENTS.md` to document the new skill
6. Create symbolic links for agent-specific locations:

```bash
# From repository root
cd .github/copilot && ln -sf ../skills/<skill-name> <skill-name>
cd ../../.claude && ln -sf ../skills/<skill-name> <skill-name>
cd ../.codex && ln -sf ../skills/<skill-name> <skill-name>
cd ../.antigravity && ln -sf ../skills/<skill-name> <skill-name>
cd .. && ln -sf .github/skills/<skill-name> .cursorrules-<skill-name>
cd .. && ln -sf .github/skills/<skill-name> .windsurfrules-<skill-name>
```

## Best Practices

### Skill Design

- **Focused**: Each skill should have a clear, single purpose
- **Portable**: Follow the Agent Skills spec for maximum compatibility
- **Documented**: Include clear instructions and examples
- **Testable**: Provide ways to verify the skill works correctly

### Skill Size

- Keep SKILL.md under 5,000 tokens for efficiency
- Break large capabilities into multiple focused skills
- Use references for detailed documentation

### Compatibility

- List compatible agents in the YAML frontmatter
- Test with multiple agents when possible
- Document agent-specific quirks if needed

## References

- [Agent Skills Specification](https://agentskills.io/specification)
- [Project Agents Documentation](../.github/AGENTS.md)
- [Contributing Guide](../../CONTRIBUTING_DEV.md)

## Support

For questions or issues with skills:
- Open an issue on GitHub
- Reference the specific skill in your issue
- Include which AI agent you're using
