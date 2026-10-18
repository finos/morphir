# AI Agent Configuration

This repository includes AI agent skills to enhance development workflows. The skills are compatible with multiple AI coding assistants.

## Supported Agents

- **Claude** (Anthropic)
- **GitHub Copilot**
- **OpenAI Codex**
- **Cursor**
- **Windsurf**
- **Google Antigravity**

## Available Skills

### Code Reviewer

**Location**: `.github/skills/code-reviewer/`

**Purpose**: Comprehensive code review for pull requests and code changes in the Morphir Moonbit monorepo.

**Usage**: Reference this skill when you need to review code changes before merging.

**Key Features**:
- Checks Moonbit code quality and formatting
- Validates package structure and dependencies
- Ensures test coverage and quality
- Verifies build configuration
- Reviews documentation updates
- Identifies security issues
- Validates mise tasks and CI workflows

## How to Use

### For Developers

When working with an AI coding assistant, you can reference the skills:

```
Please review my code changes using the code-reviewer skill.
```

### For AI Agents

Skills are located in `.github/skills/` and follow the Agent Skills specification (agentskills.io).

Each skill includes:
- `SKILL.md`: Skill definition with metadata and instructions
- Additional resources as needed

## Agent-Specific Instructions

Different AI agents may load skills differently. Check your agent's documentation for specific instructions on loading skills from this repository.

### Agent Instruction Files

For agents that support configuration files in specific locations, symbolic links are provided:

- `.github/copilot/` - GitHub Copilot
- `.cursorrules` - Cursor
- `.windsurfrules` - Windsurf  
- `.claude/` - Claude
- `.codex/` - OpenAI Codex
- `.antigravity/` - Google Antigravity

These files are symbolic links pointing to the shared skill definitions to avoid duplication.

## Adding New Skills

To add a new skill:

1. Create a new directory in `.github/skills/<skill-name>/`
2. Add a `SKILL.md` file following the Agent Skills specification
3. Update this AGENTS.md file to document the new skill
4. Create symbolic links for agent-specific locations if needed

## Domain modeling and architecture

- Use the vocabulary in `CONTEXT.md`. Runtime support and checks use **capabilities**,
  **capability verification** and **capability validation**. Historical `admission`
  protocol keys, identifiers and source-compatible aliases belong at compatibility
  boundaries; do not propagate that name into new domain types or user-facing text.
- Model domain concepts with closed enums, discriminated unions and validated value
  types. Avoid unrestricted strings, sentinel values and independent booleans for
  states with distinct meanings or invalid combinations. A type alias for `String`
  alone does not establish an invariant. Use smart constructors when values need
  validation, and reuse existing domain types instead of introducing parallel ones.
- Follow functional domain modeling and **functional core, imperative shell**.
  Keep validation, decisions and state transitions pure. Decode external strings
  and JSON into domain values at the boundary, and encode only when crossing back.
  Keep filesystem, network, worker and host effects in adapters that execute those
  decisions. Capability claims and UI descriptions do not grant execution authority.
- Review changes for domain meaning and invalid states as well as tool results.
  Tests should establish behavior and boundary invariants; compilers and static
  analyzers should check exhaustiveness and type safety.

## Task Scripts

Use standalone MoonBit `.mbtx` scripts for scripting and automation, especially mise tasks and CI orchestration.
One script then works on every platform with the pinned toolchain that mise already installs. Do not add Bash,
PowerShell, Python or JavaScript orchestration scripts, or move that logic into inline workflow shell blocks.
Direct invocations of existing compilers, package tools and application tests can remain declarative workflow
steps. Keep the bootstrap needed to install MoonBit small and separate from task logic.

- Put the script in `scripts/` and run it with `moonx scripts/<name>.mbtx` (Wasm) or `moon run scripts/<name>.mbtx`.
- Declare its mise task in `.config/mise/config.toml`, for example `run = "moonx scripts/beads-check.mbtx"`.
  `scripts/beads-check.mbtx` (`mise run beads:check`) is the reference example.
- Pin the version of each import: `"moonbitlang/async@0.22.1/process"`. Use `moonbitlang/async` for processes
  (`collect_output`, `run`), files (`fs`) and `stdio`, and `moonbitlang/x/sys` for `exit`.
- The older tasks in `.config/mise/tasks/` are still bash and PowerShell pairs. When you change one, move it to a
  MoonBit script, declare its task in `.config/mise/config.toml`, and remove both old wrappers. Track remaining
  legacy migrations in beads; do not introduce another platform-specific variant.
- CI rejects added/modified legacy mise wrappers and non-MoonBit automation in `scripts/`.
  Deletions remain allowed during migration. Existing application-language tests and build tools under `apps/`
  and `pkgs/` are separate from this automation policy.
- CI selection and aggregate checks live in `scripts/ci-changes.mbtx` and `scripts/ci-gate.mbtx`. Run
  `mise run test:ci` after editing CI policy. Full installation/platform qualification lives in
  `.github/workflows/qualification.yml`; routine PR checks use the tested component dependency rules.

The `cli/*` modules on mooncakes.io are POSIX-style commands for `moonx`: `cli/sh`, `cli/jq`, `cli/grep`,
`cli/find`, `cli/curl`, `cli/make` and more (`moon view cli` lists them). Use them as portable commands, for example
`moonx cli/jq@0.2.0 .count` or `moonx cli/sh@0.2.0 -c '...'`, instead of tools that are not on every machine. Their
shared library, `cli/core`, has packages that a script can import: `cli/core/process` (child processes),
`cli/core/fsops` (copy and remove), `cli/core/netops` (HTTP), `cli/core/platform` and `cli/core/cli` (argument
parser).

## Pre-Push Requirements

**⚠️ IMPORTANT**: All lint, format, and validation checks **MUST** pass before pushing to the repository.

### Required Checks

Before any `git push`, the following checks must pass:

1. **Linting** (`mise run lint`)
   - YAML file validation
   - Moonbit code style checks

2. **Format Check** (`mise run lint:moonbit`)
   - Moonbit code formatting verification
   - Ensures code is formatted with `moon fmt`

3. **Validation** (`mise run validate`)
   - Package structure validation
   - Configuration file verification

### Automated Enforcement

Git hooks are **automatically installed** when you enter the directory (via mise hooks). You can also manually run:

```bash
# Manually trigger hook setup (idempotent)
mise run setup:hooks
```

This installs a pre-push git hook that:
- Runs all required checks before allowing a push
- Prevents pushing code that fails validation
- Provides clear error messages if checks fail
- Can be bypassed with `git push --no-verify` (not recommended)

### Manual Verification

You can run all checks manually before pushing:

```bash
mise run check
```

Or run individual checks:

```bash
mise run lint           # Run linting
mise run format         # Auto-format code
mise run validate       # Run validation
```

### CI/CD Integration

The same checks run in CI/CD pipelines. Commits that fail these checks will:
- Block PR merges
- Fail CI workflows
- Require fixes before merge approval

**Always run checks locally before pushing to avoid CI failures.**

## Contributing

When adding or modifying skills:

- Follow the Agent Skills specification (agentskills.io)
- Test with multiple agents when possible
- Update documentation
- Keep skills focused and modular
- **Ensure all pre-push checks pass**

## References

- [Agent Skills Specification](https://agentskills.io/specification)
- [Project Contributing Guide](../CONTRIBUTING_DEV.md)
- [Project Architecture](../docs/ARCHITECTURE.md)
