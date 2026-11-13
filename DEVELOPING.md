# Morphir Development Guide

This guide covers the development workflow for contributing to Morphir.

## Prerequisites

- Rust 1.98.0 or later (for the development tools `morphir-mck` and `morphir-dev`, which are built from the `ecosystem/morphir-rust` submodule)
- Node.js 24+ (for website development)
- Git
- Mise (task runner) - Install from https://mise.jdx.dev
- The Morphir CLI itself is .NET and lives in [finos/morphir-dotnet](https://github.com/finos/morphir-dotnet), pinned here at `ecosystem/morphir-dotnet`; work on it there. The deleted Rust CLI's MSVC Spectre-library requirement ([#886](https://github.com/finos/morphir/issues/886)) went with it.
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

For MoonBit work, mise installs the same pinned toolchain as
`finos/morphir-moonbit`, including its matching core library and `moonx`. To
install only MoonBit and its bootstrap dependency:

```bash
mise install bun http:moonbit
mise exec -- moon version --all
```

This supports Linux x64/ARM64, macOS Apple Silicon and Windows x64. Mise sets
`MOON_HOME` to its own installation directory. Use `mise exec -- <command>` if
your shell does not activate mise automatically.

### 3. Verify Your Setup

```bash
mise run build
mise run test
```

## OpenSpec proposals

Use `mise run openspec:verify` to check the shared proposal workflow. The
[OpenSpec guide](docs/developers/openspec.md) covers setup, HTML designs, Beads
links and bundle updates.

## Development Workflow

### Working on the development tools (Rust)

```bash
mise run mck -- --help   # morphir-mck, the shared compatibility kit runner
mise run kb -- check     # morphir-dev kb, the knowledge base commands
```

Neither tool is the Morphir CLI or is released. The CLI's release is built from `ecosystem/morphir-dotnet` by
`.github/workflows/release.yml`; `bun test tools/cli-release.test.ts` checks that orchestration.

Release validation requires the checkout, the selected tag and the workflow's triggering `GITHUB_SHA` to name the
same commit. This prevents a moved tag from changing the source after a run starts. `GITHUB_SHA` is supplied by
[GitHub Actions](https://docs.github.com/en/actions/reference/workflows-and-actions/variables), rather than derived
from the fetched tag. A missing or mismatched triggering SHA fails validation, including in a dry run.

Acquisition contract behavior runs through the .NET implementation against this checkout's fixed corpus.
The CI `toolchain-contracts` job reads `.config/toolchain-contract-tests.json` and checks out that exact
source separately. Its pin is independent of the CLI delivery tuple in `.config/cli-release.json`,
the `ecosystem/morphir-dotnet` gitlink and `release.yml`. Metadata-only checks remain in
`tools/check-toolchain-corpus.ts`; no Rust acquisition checker remains. See
[the contract guide](docs/spec/toolchain/index.md) for the external-corpus command.

### Working on the Website (Docusaurus)

```bash
cd website
npm start    # Development server
npm run build  # Production build
```

### Running Tests

```bash
# Run all tests of the Rust development tools (their source is in the morphir-rust submodule)
mise run test

# Or manually, from the root of this repository:
cargo test --locked --manifest-path ecosystem/morphir-rust/umbrella-tools/Cargo.toml --all-features --workspace
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
├── ecosystem/            # Morphir implementation submodules
│   └── morphir-rust/umbrella-tools/  # Rust development tools of this repository
│       └── crates/
│           ├── morphir-mck/       # MCK engine
│           ├── morphir-mck-cli/   # morphir-mck: the standalone runner (development only)
│           └── morphir-dev-tools/ # morphir-dev: kb and repository gates (internal)
├── website/               # Docusaurus documentation site
│   ├── docs/
│   ├── src/
│   └── package.json
├── docs/                  # Documentation content
└── examples/              # Example Morphir projects
```

This repository has no Rust workspace of its own. The development tools moved to
[finos/morphir-rust](https://github.com/finos/morphir-rust) (`umbrella-tools/`). They read the specifications and
fixtures of this repository by relative path, so build and test them from here, through the mise tasks or with
`cargo ... --manifest-path ecosystem/morphir-rust/umbrella-tools/Cargo.toml`. To change them, open a pull request
in finos/morphir-rust, then move the `ecosystem/morphir-rust` pin here.

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

### Building a CLI release

Releases are built by `.github/workflows/release.yml` from a `v<version>` tag; see [INSTALLING.md](INSTALLING.md).
Nothing in this repository builds the CLI by hand.

### Adding Dependencies

```bash
# The Rust development tools are in the morphir-rust submodule.
# Add to a specific crate
cd ecosystem/morphir-rust/umbrella-tools/crates/morphir-mck-cli
cargo add some-crate

# Add to workspace (shared)
# Edit ecosystem/morphir-rust/umbrella-tools/Cargo.toml [workspace.dependencies]
```

### Cleaning Build Artifacts

```bash
mise run clean
# Or: cargo clean --manifest-path ecosystem/morphir-rust/umbrella-tools/Cargo.toml
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
