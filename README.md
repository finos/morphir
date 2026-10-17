# Morphir Moonbit Monorepo

[![FINOS - Incubating](https://cdn.jsdelivr.net/gh/finos/contrib-toolbox@master/images/badge-incubating.svg)](https://community.finos.org/docs/governance/Software-Projects/stages/incubating)
[![CI](https://github.com/finos/morphir-moonbit/actions/workflows/ci.yml/badge.svg)](https://github.com/finos/morphir-moonbit/actions/workflows/ci.yml)

A monorepo for Morphir implementation in Moonbit, providing core libraries and bindings for WebAssembly targets.

## Overview

This repository contains the Moonbit implementation of Morphir, organized as a monorepo with multiple packages:

- **morphir-sdk**: Standard library for Morphir with functional programming primitives
- **morphir-ir**: [Versioned IR models, JSON codecs and migrations](pkgs/morphir-ir/README.md) for v1–v4
- **morphir-scheme**: [Embeddable Scheme, IR transforms and runtime](pkgs/morphir-scheme/README.mbt.md)
- **morphir-host**: [Runtime adapters, snapshots and artifact publication](pkgs/morphir-host/README.md)
- **morphir-engine**: [Scriptable file, directory, project and workspace pipelines](pkgs/morphir-engine/README.md)
- **morphir-core**: Core abstractions and types for the Morphir ecosystem
- **morphir-moonbit-bindings**: FFI bindings for Moonbit WASM targets
- **morphir-elm**: [Elm source generation from Morphir IR](pkgs/morphir-elm/README.md)
- **morphir-typing**: [Type inference and checking for Morphir IR](pkgs/morphir-typing/README.md)
- **morphir-sdk-spec**: [The IR specification of the Morphir SDK](pkgs/morphir-sdk-spec/README.md)
- **@morphir/morphir**: CLI application in [`apps/morphir`](apps/morphir/README.md)
- **Morphir Workbench**: shared Rabbita [browser UI](apps/morphir-workbench/README.md) and [Proton desktop host](apps/morphir-workbench-desktop/README.md)

## Project site

The project site at <https://finos.github.io/morphir-moonbit/> publishes the docs, the design records, the blog
and the Morphir Workbench. It is built from `docs/`, `site/` and package READMEs by
[`apps/morphir-site`](apps/morphir-site/README.md) and deployed on every push to `main`. To write for it, read
[Writing for the site](docs/WRITING_FOR_THE_SITE.md).

## Prerequisites

- [mise](https://mise.jdx.dev/) - Development environment manager
- All other tools (Moonbit, Bun, yamllint, uv) are managed by mise

The [toolchain library overview](docs/ARCHITECTURE.md#moonbit-libraries) identifies
`moonbitlang/core`, `moonbitlang/x` and `moonbitlang/async`, including async support
for our tooling. These are foundational libraries within a broader dependency set.

## Installation

1. Install mise by following the [official installation guide](https://mise.jdx.dev/getting-started.html)

2. Clone the repository:
   ```bash
   git clone https://github.com/finos/morphir-moonbit.git
   cd morphir-moonbit
   ```

3. Install tools:
   ```bash
   mise install
   ```

**Note**: Git hooks are automatically installed when you enter the directory via mise. The pre-push hook enforces lint, format, and validation checks before allowing pushes, preventing CI failures by catching issues locally.

## Development

### Pre-Push Validation

**⚠️ Important**: All code must pass lint, format, and validation checks before pushing.

The pre-push hook automatically runs these checks, but you can run them manually:

```bash
# Run all checks
mise run check

# Or individual checks
mise run lint           # Linting
mise run lint:moonbit   # Format check  
mise run validate       # Validation
```

### Available Tasks

All development tasks are managed through mise. You can list all available tasks with:

```bash
mise tasks
```

#### Linting

```bash
# Run all linting tasks
mise run lint

# Lint YAML files only
mise run lint:yaml

# Check Moonbit code formatting
mise run lint:moonbit
```

#### Formatting

```bash
# Format all Moonbit code
mise run format
```

#### Building

```bash
# Build all packages for all targets
mise run build

# Build for WASI target only
mise run build:wasi

# Build for browser (WASM-GC) target only
mise run build:browser

# Build JavaScript and native executables
mise run build:js
mise run build:native
```

#### Testing

```bash
# Run tests on WASM, WASM-GC, JavaScript and native
mise run test
```

#### Validation

```bash
# Run all validation checks (YAML lint + package structure)
mise run validate

# Verify package structure only
mise run validate:packages
```

## Project Structure

```
morphir-moonbit/
├── .config/
│   └── mise/
│       ├── config.toml          # Mise configuration
│       └── tasks/               # Task definitions
│           ├── lint/
│           ├── format/
│           ├── build/
│           └── test/
├── .github/
│   └── workflows/
│       └── ci.yml               # CI workflow
├── pkgs/                        # Moonbit packages (workspace members)
│   ├── morphir-sdk/
│   ├── morphir-core/
│   ├── morphir-ir/
│   ├── morphir-scheme/
│   ├── morphir-engine/
│   ├── morphir-host/
│   └── morphir-moonbit-bindings/
├── apps/                        # Applications (workspace members)
│   └── morphir/                 # @morphir/morphir CLI
├── moon.mod                     # Root module configuration
└── moon.work                    # Workspace manifest (member modules)
```

## Build Targets

The workspace builds for four targets:

1. **WASI (wasm)**: For server-side and command-line applications
2. **Browser (wasm-gc)**: For browser-based applications with WASM-GC support
3. **JavaScript (js)**: For Node.js and the `@morphir/morphir` npm package
4. **Native (native)**: Standalone executables for the build platform

See the [CLI target documentation](apps/morphir/README.md#wasm-and-wasm-gc) for runtime
requirements. `mise run test:cli` checks CLI execution on all four targets.

## AI Agent Skills

This repository includes AI agent skills following the [Agent Skills specification](https://agentskills.io/specification). These skills enhance AI coding assistants with project-specific knowledge.

**Available Skills**:
- **code-reviewer**: Comprehensive code review for PRs and changes

**Supported Agents**: Claude, GitHub Copilot, OpenAI Codex, Cursor, Windsurf, Google Antigravity

See [.github/AGENTS.md](.github/AGENTS.md) for more information.

## Contributing

For any questions, bugs or feature requests please open an [issue](https://github.com/finos/morphir-moonbit/issues).
For anything else please send an email to morphir@finos.org.

To submit a contribution:
1. Fork it (<https://github.com/finos/morphir-moonbit/fork>)
2. Create your feature branch (`git checkout -b feature/fooBar`)
3. Read our [contribution guidelines](.github/CONTRIBUTING.md) and [Community Code of Conduct](https://www.finos.org/code-of-conduct)
4. Commit your changes (`git commit -am 'Add some fooBar'`)
5. Push to the branch (`git push origin feature/fooBar`)
6. Create a new Pull Request

_NOTE:_ Commits and pull requests to FINOS repositories will only be accepted from those contributors with an active, executed Individual Contributor License Agreement (ICLA) with FINOS OR who are covered under an existing and active Corporate Contribution License Agreement (CCLA) executed with FINOS. Commits from individuals not covered under an ICLA or CCLA will be flagged and blocked by the FINOS Clabot tool (or [EasyCLA](https://community.finos.org/docs/governance/Software-Projects/easycla)). Please note that some CCLAs require individuals/employees to be explicitly named on the CCLA.

*Need an ICLA? Unsure if you are covered under an existing CCLA? Email [help@finos.org](mailto:help@finos.org)*

## License

Copyright 2026 FINOS

Distributed under the [Apache License, Version 2.0](http://www.apache.org/licenses/LICENSE-2.0).

SPDX-License-Identifier: [Apache-2.0](https://spdx.org/licenses/Apache-2.0)
