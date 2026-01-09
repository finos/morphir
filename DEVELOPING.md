# Morphir Development Guide

This guide covers the development workflow for contributing to Morphir.

## Prerequisites

- Go 1.25.5 or later
- Git
- Mise (task runner) - Install from https://mise.jdx.dev
- (Optional) Beads - For issue tracking

## Quick Start

### 1. Clone the Repository

```bash
git clone https://github.com/finos/morphir.git
cd morphir
```

### 2. Set Up Development Environment

Run the development setup task to configure your local Go workspace:

```bash
mise run dev-setup
```

This script will:
- Create a `go.work` file that enables cross-module development
- Sync the workspace with all modules
- Verify your setup

**Important**: The `go.work` file is git-ignored and only used for local development. This allows you to make changes across multiple modules without needing version tags or replace directives.

### 3. Verify Your Setup

```bash
mise run verify
```

This will run all module verifications, ensuring everything is correctly configured.

## Development Workflow

### Working Across Modules

With the `go.work` file in place, you can freely edit code across modules:

```bash
# Edit code in pkg/models
cd pkg/models
# Make changes...

# Edit code in cmd/morphir that uses pkg/models
cd ../../cmd/morphir
# Your local changes from pkg/models are automatically used!
```

The Go workspace automatically handles the module dependencies using your local code.

### Running Tests

```bash
# Run all tests
mise run test

# Run tests for a specific module
cd pkg/models
go test ./...
```

`mise run test` is preferred because it runs the workspace doctor first and applies the default
local fix for missing internal module tags.

### Building the CLI

```bash
# Build morphir CLI
mise run build

# Run the CLI
./bin/morphir --help
```

### Code Quality Checks

```bash
# Run linting
mise run lint

# Format code
mise run fmt

# Run all verifications (tests, lint, build)
mise run verify
```

## Module Structure

Morphir uses a multi-module Go workspace:

```
morphir/
├── cmd/
│   └── morphir/          # Main CLI application
├── pkg/
│   ├── config/           # Configuration management
│   ├── models/           # Morphir IR models
│   ├── pipeline/         # Processing pipelines
│   ├── sdk/              # SDK components
│   └── tooling/          # Tooling utilities
├── tests/
│   └── bdd/              # BDD tests
└── go.work               # Workspace file (local only, git-ignored)
```

Each subdirectory with a `go.mod` file is an independent Go module.

## Making Changes

### 1. Create a Feature Branch

```bash
git checkout -b feat/my-feature
```

### 2. Make Your Changes

Edit code across any modules as needed. The workspace handles dependencies automatically.

### 3. Run Verifications

```bash
mise run verify
```

### 4. Commit Your Changes

```bash
git add .
git commit -m "feat: add my feature"
```

**Important**: Do NOT commit the `go.work` or `go.work.sum` files. They are git-ignored and should remain local only.

### 5. Push and Create PR

```bash
git push -u origin feat/my-feature
gh pr create
```

## Common Tasks

### Adding a New Dependency

```bash
# Navigate to the module that needs the dependency
cd pkg/models

# Add the dependency
go get github.com/example/package@latest

# Sync the workspace
cd ../..
go work sync
```

### Updating Dependencies

```bash
# Update all modules
mise run mod-tidy

# Or manually for each module
cd pkg/models && go get -u ./...
cd ../config && go get -u ./...
# ... repeat for each module
```

### Cleaning Build Artifacts

```bash
mise run clean
```

## Troubleshooting

### "package not found" errors

If you get "package not found" errors:

1. Verify your workspace is set up:
   ```bash
   cat go.work
   ```

2. Re-run the setup script:
   ```bash
   ./scripts/dev-setup.sh
   ```

3. Sync the workspace:
   ```bash
   go work sync
   ```

### Module version conflicts

If you see module version conflicts:

1. Ensure you're using the workspace:
   ```bash
   ls go.work  # Should exist
   ```

2. Check workspace modules:
   ```bash
   go work edit -print
   ```

3. Run sync:
   ```bash
   go work sync
   ```

### Go workspace resolution errors

If you see errors like `unknown revision pkg/.../vX.Y.Z` or Go tries to fetch local modules:

Run the workspace doctor for an interactive diagnosis and default fixes:
```bash
mise run workspace-doctor
```
The default fix will create `go.work` (via `setup-workspace`) if missing and add versioned
`go.work` replaces for missing internal tags.

1. Confirm the workspace is in use:
   ```bash
   go env GOWORK
   ```
   It should point at your repo's `go.work`.

   From the repo root, `go env GOMOD` is expected to be `/dev/null` when the workspace is active.

2. Ensure all modules are in the workspace:
   ```bash
   go work use -r .
   go work edit -print
   ```

3. Sync the workspace:
   ```bash
   go work sync
   ```

4. If `go env GOWORK` is empty or not the repo workspace, run tests from the repo root
   or set the workspace explicitly for the command:
   ```bash
   GOWORK="$(git rev-parse --show-toplevel)/go.work" go test ./cmd/morphir/...
   ```

5. Verify no `replace` directives are in any `go.mod`:
   ```bash
   rg -n "^replace " --glob "*/go.mod"
   ```

6. Confirm `go.work` and `go.work.sum` are not staged:
   ```bash
   git status --short | rg "go.work"
   ```

7. If errors still mention `unknown revision pkg/.../vX.Y.Z`, verify the version exists.
   Untagged internal modules must not be required at non-existent versions:
   - Prefer adding a release tag for the module, or
   - Avoid introducing the dependency until a release tag exists.
   - `go.work` use does not override invalid version references in go.mod.
   - As a local-only workaround, add a versioned `go.work` replace:
     ```bash
     go work edit -replace=github.com/finos/morphir/pkg/<module>@vX.Y.Z=./pkg/<module>
     ```

8. If you are using git worktrees, each worktree needs its own `go.work`.
   Re-run the workspace setup in each worktree:
   ```bash
   ./scripts/setup-workspace.sh
   ```

9. If you suspect stale cache behavior after repeated attempts:
   ```bash
   go clean -cache -modcache
   ```

**Observed behaviors (playbook notes):**
- From repo root with workspace active, `go env GOMOD` is `/dev/null`.
- `go work sync` fails if any internal module version in go.mod does not exist as a tag.
- `go test ./cmd/morphir/...` will still fail when a required internal module version tag is missing.

### Build failures after pulling changes

After pulling changes from main:

```bash
# Sync workspace
go work sync

# Update dependencies
mise run mod-tidy

# Verify everything works
mise run verify
```

## Understanding the Workspace

The `go.work` file tells Go to use your local copies of modules instead of fetching them from GitHub. This means:

- ✅ **Immediate feedback**: Changes are reflected across modules instantly
- ✅ **No version tagging needed**: Work with local code directly
- ✅ **No replace directives**: Cleaner go.mod files
- ✅ **Go install compatible**: Modules can be installed via `go install` since they have no replace directives
- ✅ **Stable versions in go.mod**: Keep internal deps on released tags; use go.work for unreleased local changes

When a module needs an unreleased change from another module, keep the dependency version in `go.mod`
at the latest released tag and rely on `go.work` to use the local code. Avoid pseudo-versions for
in-repo modules. If the module has never been tagged, prefer a local-only, versioned `go.work`
replace as the default workaround; add an initial tag before depending on it only when you intend
to publish and consume that version.

**Questions about how CI and releases work?** See [CI_RELEASE_FAQ.md](./CI_RELEASE_FAQ.md) for detailed answers about:
- How CI tests your PR code (not old published versions)
- How multi-module PRs work
- How the release workflow handles versioning
- Common troubleshooting scenarios

## Release Process

For maintainers preparing releases, see the detailed release process in [AGENTS.md](./AGENTS.md).

Quick reference:

```bash
# Prepare release (creates tags for all modules)
./scripts/release-prep.sh v0.3.0

# Push tags to trigger release
git push origin --tags
```

## Getting Help

- **Issues**: Use Beads issue tracking (`bd new "your issue"`)
- **Discussions**: GitHub Discussions at https://github.com/finos/morphir/discussions
- **Contributing**: See [CONTRIBUTING.md](./CONTRIBUTING.md)

## Additional Resources

- [Go Workspaces Documentation](https://go.dev/doc/tutorial/workspaces)
- [Morphir Documentation](https://morphir.finos.org)
- [FINOS Community](https://finos.org)

## Using AI Assistance

### Release Manager Skill

The repository includes a Claude Code skill for release management. To use it:

```
/skill release-manager
```

The release manager can help with:
- Analyzing commits and suggesting changelog entries
- Determining appropriate version numbers
- Updating CHANGELOG.md
- Creating release tags
- Managing the release process

### Quick Release Workflow with AI

```bash
# 1. Suggest changelog entries
mise run changelog-suggest

# 2. Use release manager skill to update CHANGELOG.md
# /skill release-manager
# Ask: "Help me prepare a release with the suggested changes"

# 3. The skill will guide you through:
#    - Version number selection
#    - CHANGELOG.md updates
#    - Tagging and release

# 4. Or do it manually:
mise run release -- v0.3.0
```
