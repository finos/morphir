# Morphir Development Guide

This guide covers the development workflow for contributing to Morphir.

## Prerequisites

- Rust 1.98.0 or later (for Morphir CLI development)
- Node.js 24+ (for website development)
- Git
- Mise (task runner) - Install from https://mise.jdx.dev

## Quick Start

### 1. Clone the Repository

```bash
git clone https://github.com/finos/morphir.git
cd morphir
```

### 2. Install Dependencies

```bash
# Install mise tools
mise install

# For website development
cd website && npm install
```

### 3. Verify Your Setup

```bash
mise run build
mise run test
```

## Development Workflow

### Working on the Morphir CLI (Rust)

```bash
cargo run --package morphir -- --help
```

### Working on the Website (Docusaurus)

```bash
cd website
npm start    # Development server
npm run build  # Production build
```

### Running Tests

```bash
# Run all Rust tests
mise run test

# Or manually:
cargo test --all-features --workspace
```

### Code Quality Checks

```bash
# Run linting (clippy)
mise run lint

# Format code
mise run fmt

# Check formatting
mise run fmt-check

# Run all checks
mise run check
```

## Project Structure

```
morphir/
├── crates/
│   ├── morphir/          # Morphir CLI
│   └── integration-tests/ # Cross-crate CLI integration tests
├── ecosystem/            # Vendored Morphir implementation submodules
├── website/               # Docusaurus documentation site
│   ├── docs/
│   ├── src/
│   └── package.json
├── docs/                  # Documentation content
├── examples/              # Example Morphir projects
└── Cargo.toml             # Workspace configuration
```

## Making Changes

### 1. Create a Feature Branch

```bash
git checkout -b feat/my-feature
```

### 2. Make Your Changes

Edit code and ensure tests pass.

### 3. Run Verifications

```bash
mise run check
mise run test
```

### 4. Commit Your Changes

```bash
git add .
git commit -m "feat: add my feature"
```

### 5. Push and Create PR

```bash
git push -u origin feat/my-feature
gh pr create
```

## Common Tasks

### Building for Release

```bash
cargo build --locked --release --package morphir
```

### Adding Dependencies

```bash
# Add to a specific crate
cd crates/morphir
cargo add some-crate

# Add to workspace (shared)
# Edit root Cargo.toml [workspace.dependencies]
```

### Cleaning Build Artifacts

```bash
mise run clean
# Or: cargo clean
```

## Troubleshooting

### Website Build Issues

If the website fails to build:

1. Clear the cache:
   ```bash
   cd website
   npm run clear
   ```

2. Reinstall dependencies:
   ```bash
   rm -rf node_modules
   npm install
   ```

## Getting Help

- **Issues**: Use Beads issue tracking (`bd create --title="your issue"`)
- **Discussions**: GitHub Discussions at https://github.com/finos/morphir/discussions
- **Contributing**: See [CONTRIBUTING.md](./docs/developers/contributing.md)

## Additional Resources

- [Morphir Documentation](https://morphir.finos.org)
- [FINOS Community](https://finos.org)
