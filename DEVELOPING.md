# Morphir Development Guide

This guide covers the development workflow for contributing to Morphir.

## Prerequisites

- Rust 1.93.0 or later (for morphir-live development)
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

### Working on morphir-live (Rust)

```bash
# Run in development mode with hot reload
mise run dev

# Or manually:
cd crates/morphir-live
dx serve
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
│   └── morphir-live/     # Interactive Morphir visualization app
│       ├── src/
│       │   ├── main.rs
│       │   ├── components/  # UI components
│       │   ├── models.rs
│       │   └── routes.rs
│       └── Cargo.toml
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
# Build optimized WASM for morphir-live
cd crates/morphir-live
dx build --release
```

### Adding Dependencies

```bash
# Add to a specific crate
cd crates/morphir-live
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

### WASM Build Issues

If you encounter WASM build issues:

1. Ensure the WASM target is installed:
   ```bash
   rustup target add wasm32-unknown-unknown
   ```

2. Install dioxus-cli:
   ```bash
   cargo install dioxus-cli
   ```

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

- [Dioxus Documentation](https://dioxuslabs.com/docs)
- [Morphir Documentation](https://morphir.finos.org)
- [FINOS Community](https://finos.org)
