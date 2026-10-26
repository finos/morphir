# AI Agent Configuration

This repository includes AI agent skills to enhance development workflows. The skills are compatible with multiple AI coding assistants.

## Supported Agents

- **Claude** (Anthropic)
- **GitHub Copilot**
- **OpenAI Codex**
- **Cursor**
- **Windsurf**
- **Google Antigravity**
- **Grok**
- **Muse Code**
- **Devin**
- **Gemini CLI**
- **OpenCode**

This list is not complete. Any agent that reads `AGENTS.md` or the shared `.agents/skills/` directory can use
this guidance and the skills.

## Available Skills

### Build master skill and agent

Read [build-master](skills/build-master/SKILL.md) for CI/CD execution planning, check placement,
artifact reuse, qualification, and build performance work. Keep PR CI a quick, credible correctness
signal and give deeper assurance deliberate execution paths and enforced release requirements.

The separate [build-master agent](agents/build-master.agent.md) owns that specialist role in delegated
work and agent teams. For workflow structure, new jobs or matrices, gate placement, or cross-cutting
build changes, delegate a bounded review to it when delegation is available and permitted. Otherwise
apply its skill directly. Give it the candidate/diff, desired outcome, constraints, available run evidence,
review or implementation mode, and file ownership. It returns decisions and evidence to the coordinator;
it does not grant merge or release approval. Routine test execution does not need a separate review.
For material decisions, its shared rubric makes classification, hard requirements, scoring criteria,
evidence, confidence, and tradeoffs visible to the team.

#### Scarce runners: macOS and some Windows labels

macOS runners and some Windows runners are valuable, limited resources. The account can run only a few of
these jobs at the same time, so each job on them can delay every other workflow and the merge queue. Plan
and justify each use. Do not add a macOS or scarce Windows job, matrix axis or trigger, or move one to a
more frequent event, as a side effect of other work.

Always send these decisions to the build-master. Delegate a bounded review to the build-master agent when
delegation is available and permitted; otherwise apply the build-master skill directly before you change
the workflow. This applies to new jobs, matrix entries, reusable-workflow inputs that select a runner, and
selector changes that make an existing job run more often. The
[repository reference](skills/build-master/references/repository.md#scarce-runners) records the current
placement of these runners.

A platform matrix finds platform-specific defects before a release. When platform-neutral tests prove the logic,
the platform result does not have to arrive on every push. If you tested a change on macOS, Windows or another
platform, add a `Tested-on:` trailer to the commit and copy it into the PR description. The reference gives
the format. This attestation is a useful hint, not evidence, and it never replaces a required or release run.

The [skill catalog](skills/README.md#build-master-skill-and-agent) lists native entry points and a portable
handoff prompt. The repository contains the complete skill and persona; personal installations are optional.

### Rich designs and frontend design

- [Rich designs](../.agents/skills/rich-designs/SKILL.md) covers HTML authoring, diagrams, browser review,
  durable storage, site integration and PR landing. Follow its repository-specific reference.
- [Frontend design](../.agents/skills/frontend-design/SKILL.md) is vendored unchanged from Anthropic,
  with its license and pinned provenance. Apply it within this repository's template and user requirements.

Both skills have discovery links under `.github/skills` and `.claude/skills`, with canonical sources in `.agents/skills`.

### Archify and explanatory diagrams

Read [Archify](../.agents/skills/archify/SKILL.md) for validated architecture, workflow, sequence, data-flow and
lifecycle diagrams. The complete upstream package, licenses and pinned provenance are installed in
`.agents/skills/archify/`; no personal installation is required. The
[skill catalog](skills/README.md#archify-across-agents) lists discovery paths for the supported agents and a
direct-file fallback.

Use connected narrative prose to explain the user's goal, a concrete example and the responsibilities of each
part. Pair it with Mermaid sources, accessible SVG and Archify diagrams as appropriate. Follow the
[rich-designs repository guidance](../.agents/skills/rich-designs/references/repository.md) for rendering,
evidence, storage and integration with the existing docs site. Keep the approved document head, CSS and script
policy; standalone Archify pages are separate review artifacts.

### Beads companion

**Location**: [.agents/skills/beads-companion/SKILL.md](../.agents/skills/beads-companion/SKILL.md)

Preserve rich HTML designs, capture reusable discoveries and handoff notes, and sync the shared tracker.
Its portable helpers run through `moonx scripts/beads-companion.mbtx` or `mise run beads:companion -- ...`.
The same skill is exposed through `.agents/skills`, `.github/skills` and `.claude/skills`.

### Project management

**Location**: `.github/skills/project-management/`

Report initiative and open-work progress across beads and GitHub Issues with bars, ratios, percentages,
priorities, IDs, and summaries. Organize tasks, verify dependencies, and recommend ready work without
double-counting mirrors or treating withdrawn work as delivered.

Read its `SKILL.md` for reporting or work-management requests. The skill uses the host agent's available
tools and the repository's tracker rules. It does not require a personal skill installation.
The [skill catalog](skills/README.md) lists discovery paths for Codex, Claude, Grok, Muse, Cursor, Copilot,
and Devin, plus a direct-file invocation for other agents.

### OpenSpec

**Location**: `openspec/` and the `openspec-*` skills in each agent's skill directory

[OpenSpec](https://github.com/Fission-AI/OpenSpec) is a spec-driven change workflow. A change in
`openspec/changes/<name>/` holds `proposal.md`, `design.html`, spec deltas and `tasks.md`. Archiving the change
merges its deltas into `openspec/specs/`. The project schema `openspec/schemas/html-design/` makes the design an
HTML review page; the CLI parses the other files, so they stay Markdown. See the root
[AGENTS.md](../AGENTS.md#specs-and-plans-are-html-documents). The skills are `openspec-explore`, `openspec-propose`, `openspec-apply-change`,
`openspec-update-change`, `openspec-sync-specs` and `openspec-archive-change`. Invoke them as
`/openspec-propose`, or as `$openspec-propose` in Codex.

The skills run the `openspec` CLI. Install the version that generated them, which each skill records as
`generatedBy` (now 1.14.3): `mise use -g npm:@fission-ai/openspec@1.14.3`. Do not add it to
`.config/mise/config.toml`: `mise run` installs every missing tool in that file, so each CI job would download it.

The CLI generates the skills: do not edit them. To change the version, install the new version, run
`openspec update`, and commit the regenerated files. The
[skill catalog](skills/README.md#openspec-across-agents) lists the directory for each agent.

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

### Agent instruction files and discovery

The root `AGENTS.md` routes project-management requests to the canonical skill. Directory links under
`.agents/skills/`, `.claude/skills/`, and `.grok/skills/` expose the complete skill, including its reference
files. Copilot can discover it directly under `.github/skills/`. Edit the canonical directory only.

Existing agents and skills may use older instruction links; consult the [skill catalog](skills/README.md)
for the project-management paths rather than assuming every agent uses the same directory.

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

Read [scripts/AGENTS.md](../scripts/AGENTS.md) before adding or changing automation. It covers library-based
command-line parsing. The root [MoonBit dependency guidance](../AGENTS.md#moonbit-dependencies) applies here too.

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
- All mise task names are declared in `.config/mise/config.toml`; their orchestration lives in `scripts/*.mbtx`.
  The legacy Bash/PowerShell pairs and Python fixture generator have been removed. Keep toolchain installation
  bootstrap under `tools/` separate, and do not introduce another platform-specific task variant.
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
