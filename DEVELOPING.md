# Morphir Development Guide

This guide covers the development workflow for contributing to Morphir.

## Prerequisites

- Go 1.25.5 or later
- Git
- Just (command runner) - Install from https://github.com/casey/just
- (Optional) Beads - For issue tracking

## Quick Start

### 1. Clone the Repository

```bash
git clone https://github.com/finos/morphir.git
cd morphir
```

### 2. Set Up Development Environment

Run the development setup script to configure your local Go workspace:

```bash
./scripts/dev-setup.sh
```

This script will:
- Create a `go.work` file that enables cross-module development
- Sync the workspace with all modules
- Verify your setup

**Important**: The `go.work` file is git-ignored and only used for local development. This allows you to make changes across multiple modules without needing version tags or replace directives.

### 3. Verify Your Setup

```bash
just verify
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
just test

# Run tests for a specific module
cd pkg/models
go test ./...
```

### Building the CLI

```bash
# Build morphir CLI
just build

# Run the CLI
./bin/morphir --help
```

### Code Quality Checks

```bash
# Run linting
just lint

# Format code
just fmt

# Run all verifications (tests, lint, build)
just verify
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
just verify
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
just mod-tidy

# Or manually for each module
cd pkg/models && go get -u ./...
cd ../config && go get -u ./...
# ... repeat for each module
```

### Cleaning Build Artifacts

```bash
just clean
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

### Build failures after pulling changes

After pulling changes from main:

```bash
# Sync workspace
go work sync

# Update dependencies
just mod-tidy

# Verify everything works
just verify
```

## Understanding the Workspace

The `go.work` file tells Go to use your local copies of modules instead of fetching them from GitHub. This means:

- ✅ **Immediate feedback**: Changes are reflected across modules instantly
- ✅ **No version tagging needed**: Work with local code directly
- ✅ **No replace directives**: Cleaner go.mod files
- ✅ **Go install compatible**: Modules can be installed via `go install` since they have no replace directives

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
