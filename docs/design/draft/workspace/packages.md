---
title: Package Management
sidebar_label: Packages
sidebar_position: 5
---

# Package Management

This document defines the package format, registry backends, and publishing workflow for Morphir packages.

## Overview

Morphir packages are distributable archives containing compiled IR and metadata. The package management system supports multiple registry backends, allowing packages to be published to and retrieved from existing infrastructure.

| Component | Description |
|-----------|-------------|
| **Package Format** | Standardized archive containing IR, metadata, and sources |
| **Registry Backend** | Pluggable storage/retrieval layer (npm, Maven, etc.) |
| **Pack Command** | Creates distributable package from project |
| **Publish Command** | Uploads package to configured registry |

## Package Format

A Morphir package is a gzipped tarball (`.morphir.tgz`) containing the compiled distribution and metadata. The package format supports both classic (single-file) and VFS (directory tree) distribution modes.

See [Distribution Structure](../vfs-protocol/distributions.md) for the complete IR format specification.

### Package Contents

```
my-org-core-1.0.0.morphir.tgz
├── morphir.toml              # Package metadata
├── .morphir-dist/            # Distribution (VFS mode, recommended)
│   ├── format.json           # Distribution manifest
│   ├── pkg/
│   │   └── my-org/
│   │       └── core/
│   │           ├── module.json
│   │           ├── types/
│   │           │   └── *.type.json
│   │           └── values/
│   │               └── *.value.json
│   └── deps/                 # Dependency specifications
│       └── ...
├── src/                      # Source files (optional, configurable)
│   └── ...
└── CHANGELOG.md              # Changelog (optional)
```

For simpler packages or backwards compatibility, classic mode is also supported:

```
my-org-core-1.0.0.morphir.tgz
├── morphir.toml              # Package metadata
├── morphir-ir.json           # Single-file distribution (classic mode)
├── src/                      # Source files (optional)
└── CHANGELOG.md              # Changelog (optional)
```

### Distribution Types

Packages contain one of three distribution types:

| Type | Description | Use Case |
|------|-------------|----------|
| **Library** | Package with full definitions | Reusable domain packages |
| **Specs** | Specifications only (no implementations) | SDK bindings, FFI, native types |
| **Application** | Definitions with named entry points | Executables, services, CLIs |

### Package Metadata

The `morphir.toml` in a package contains distribution metadata:

```toml
[package]
name = "my-org/core"
version = "1.0.0"
description = "Core domain models for my-org"
license = "Apache-2.0"
repository = "https://github.com/my-org/morphir-packages"

[package.authors]
"Jane Doe" = "jane@my-org.com"

[package.keywords]
keywords = ["domain", "finance", "morphir"]

# Dependencies required by this package
[dependencies]
"morphir/sdk" = { git = "https://github.com/finos/morphir-sdk.git", tag = "v3.0.0" }
```

### Distribution Manifest

The `.morphir-dist/format.json` identifies the distribution:

```json
{
  "formatVersion": "4.0.0",
  "distribution": "Library",
  "package": "my-org/core",
  "version": "1.0.0",
  "created": "2026-01-16T12:00:00Z"
}
```

**Format Version**: The `formatVersion` follows semantic versioning and corresponds to the Morphir IR specification version. Tools should check compatibility before processing.

### Classic Mode (Single-File)

For backwards compatibility or simpler packages, a single `morphir-ir.json` can be used:

```json
{
  "formatVersion": "4.0.0",
  "Library": {
    "package": {
      "name": "my-org/core",
      "version": "1.0.0"
    },
    "def": {
      "modules": { "...": "..." }
    },
    "dependencies": {
      "morphir/sdk": { "...": "..." }
    }
  }
}
```

## Registry Backends

Morphir supports pluggable registry backends, allowing packages to be stored in existing package infrastructure.

### Backend Architecture

```
┌──────────────────────────────────────────────────────────────────────┐
│                           Morphir CLI                                 │
├──────────────────────────────────────────────────────────────────────┤
│                        Registry Interface                             │
│  ┌─────────────┐  ┌───────────────┐  ┌─────────────┐  ┌──────────┐  │
│  │ npm Backend │  │GitHub Releases│  │Maven Backend│  │ (future) │  │
│  └──────┬──────┘  └───────┬───────┘  └──────┬──────┘  └──────────┘  │
└─────────┼─────────────────┼─────────────────┼────────────────────────┘
          │                 │                 │
          ▼                 ▼                 ▼
    ┌───────────┐    ┌───────────┐     ┌───────────┐
    │npm Registry│   │  GitHub   │     │Maven Repo │
    │ (npmjs.org)│   │ Releases  │     │ (Central) │
    └───────────┘    └───────────┘     └───────────┘
```

### Backend Comparison

| Backend | Package Format | Infrastructure | Best For |
|---------|---------------|----------------|----------|
| **npm** | tar.gz | Central registry | JavaScript ecosystem, public packages |
| **GitHub Releases** | .morphir.tgz | Per-repository | Open source, no extra infrastructure |
| **Maven** | JAR | Central repository | JVM ecosystem, enterprise |

### Registry Interface

```gleam
/// Registry backend interface
pub type RegistryBackend {
  /// Publish a package to the registry
  publish: fn(package: PackageArchive, config: RegistryConfig) -> Result(PublishResult, RegistryError)

  /// Fetch a package from the registry
  fetch: fn(name: PackagePath, version: SemVer, config: RegistryConfig) -> Result(PackageArchive, RegistryError)

  /// List available versions of a package
  versions: fn(name: PackagePath, config: RegistryConfig) -> Result(List(SemVer), RegistryError)

  /// Search for packages
  search: fn(query: String, config: RegistryConfig) -> Result(List(PackageInfo), RegistryError)
}
```

### npm Backend

The npm backend stores Morphir packages as npm packages, leveraging existing npm infrastructure and tooling.

#### Package Mapping

| Morphir | npm |
|---------|-----|
| `my-org/core` | `@morphir/my-org--core` |
| `1.0.0` | `1.0.0` |
| `.morphir.tgz` | `.tgz` (standard npm tarball) |

#### npm Package Structure

```
package/
├── package.json           # npm metadata
├── morphir.toml          # Morphir metadata
├── morphir-ir.json       # Compiled IR
└── src/                  # Sources (if included)
```

**Generated `package.json`:**

```json
{
  "name": "@morphir/my-org--core",
  "version": "1.0.0",
  "description": "Core domain models for my-org",
  "morphir": {
    "name": "my-org/core",
    "formatVersion": 4
  },
  "files": [
    "morphir.toml",
    "morphir-ir.json",
    "src/"
  ],
  "keywords": ["morphir", "domain", "finance"],
  "license": "Apache-2.0",
  "repository": {
    "type": "git",
    "url": "https://github.com/my-org/morphir-packages"
  }
}
```

#### Configuration

```toml
# morphir.toml
[registry]
backend = "npm"

[registry.npm]
# npm registry URL (default: https://registry.npmjs.org)
registry = "https://registry.npmjs.org"

# Scope for published packages (default: @morphir)
scope = "@morphir"

# Package name separator (default: --)
separator = "--"

# Access level for scoped packages
access = "public"  # or "restricted"
```

#### Authentication

npm authentication uses standard npm configuration:

```bash
# Login to npm registry
npm login --registry=https://registry.npmjs.org

# Or use token-based auth
npm config set //registry.npmjs.org/:_authToken=${NPM_TOKEN}
```

The Morphir CLI respects `.npmrc` for authentication.

### GitHub Releases Backend

The GitHub Releases backend fetches Morphir packages from GitHub release assets. This is ideal for open source projects and organizations that want to distribute packages directly from their repositories without additional infrastructure.

Unlike npm or Maven backends which use a central registry, GitHub Releases packages are fetched directly from individual repositories. Each package specifies its source repository.

#### Package Discovery

Packages are discovered from release assets matching the Morphir package naming convention:

| Release Asset | Morphir Package |
|---------------|-----------------|
| `morphir-sdk-3.0.0.morphir.tgz` | `morphir/sdk@3.0.0` |
| `my-org-core-1.0.0.morphir.tgz` | `my-org/core@1.0.0` |

#### Dependency Declaration

Each GitHub dependency specifies its source repository:

```toml
[dependencies]
# Package from finos/morphir repository
"morphir/sdk" = { github = "finos/morphir", tag = "sdk-v3.0.0" }

# Package from a different organization's repository
"acme/domain" = { github = "acme-corp/morphir-domain", tag = "v1.0.0" }

# Package from a monorepo with package-specific tags
"my-org/core" = { github = "my-org/morphir-packages", tag = "core-v1.0.0" }
"my-org/utils" = { github = "my-org/morphir-packages", tag = "utils-v2.0.0" }

# Private repository (requires authentication)
"internal/models" = { github = "my-org/internal-models", tag = "v1.5.0" }
```

#### Workspace-Level Configuration

Common settings can be configured at the workspace level:

```toml
# morphir.toml
[registry.github]
# GitHub API URL (for GitHub Enterprise)
api_url = "https://api.github.com"  # default, or https://github.mycompany.com/api/v3

# Asset naming pattern (default shown)
asset_pattern = "{name}-{version}.morphir.tgz"

# Default organization for unqualified references
default_owner = "my-org"
```

#### Workspace Dependencies with GitHub

```toml
# workspace/morphir.toml
[workspace]
members = ["packages/*"]

[workspace.dependencies]
# Shared GitHub dependencies
"morphir/sdk" = { github = "finos/morphir", tag = "sdk-v3.0.0" }
"finos/morphir-json" = { github = "finos/morphir-json", tag = "v1.0.0" }
```

```toml
# workspace/packages/domain/morphir.toml
[dependencies]
"morphir/sdk" = { workspace = true }  # Inherits github source from workspace
```

#### Authentication

For private repositories, GitHub authentication uses standard methods:

```bash
# Via environment variable
export GITHUB_TOKEN=ghp_xxxxxxxxxxxx

# Or via gh CLI authentication
gh auth login

# For GitHub Enterprise
export GH_ENTERPRISE_TOKEN=ghp_xxxxxxxxxxxx
```

#### Checksums and Bill of Materials

For security and reproducibility, GitHub releases should include checksums and optionally a Software Bill of Materials (SBOM).

**Checksum file** (`CHECKSUMS.txt`):

```
sha256:abc123def456...  my-org-core-1.0.0.morphir.tgz
sha256:789xyz012...     my-org-utils-1.0.0.morphir.tgz
```

**Morphir manifest** (`morphir-manifest.json`):

```json
{
  "formatVersion": "4.0.0",
  "repository": "my-org/morphir-packages",
  "tag": "v1.0.0",
  "created": "2026-01-16T12:00:00Z",
  "packages": [
    {
      "name": "my-org/core",
      "version": "1.0.0",
      "asset": "my-org-core-1.0.0.morphir.tgz",
      "checksum": "sha256:abc123def456...",
      "dependencies": [
        { "name": "morphir/sdk", "version": "3.0.0" }
      ]
    }
  ]
}
```

The CLI verifies checksums when fetching packages:

```toml
[registry.github]
# Require checksum verification (default: true)
verify_checksums = true

# Checksum file name pattern
checksum_file = "CHECKSUMS.txt"

# Optional manifest file
manifest_file = "morphir-manifest.json"
```

#### Publishing to GitHub Releases

```bash
# Pack the package (generates checksum)
morphir pack

# Generate checksums file for all packages
morphir pack --checksums dist/CHECKSUMS.txt

# Generate manifest
morphir pack --manifest dist/morphir-manifest.json

# Create a GitHub release with package and checksums
gh release create v1.0.0 \
  dist/my-org-core-1.0.0.morphir.tgz \
  dist/CHECKSUMS.txt \
  dist/morphir-manifest.json \
  --repo my-org/morphir-packages \
  --title "my-org/core v1.0.0" \
  --notes "Release notes"

# Or use morphir publish (generates and uploads checksums automatically)
morphir publish --backend github --repository my-org/morphir-packages --tag v1.0.0
```

#### Comparison with Git Repository Dependencies

| Aspect | Git Repository | GitHub Releases |
|--------|---------------|-----------------|
| Source | Full repository clone | Release asset only |
| Size | Entire repo history | Single package archive |
| Speed | Slower (clone) | Faster (direct download) |
| Versioning | Any git ref | Release tags only |
| Use case | Development, pre-release | Published releases |

For development and pre-release packages, use git repository dependencies. For published, stable releases, GitHub Releases provides a more efficient distribution mechanism.

### Maven Backend

The Maven backend stores Morphir packages as JAR files in Maven repositories.

#### Package Mapping

| Morphir | Maven |
|---------|-------|
| `my-org/core` | `dev.morphir:my-org-core` |
| `1.0.0` | `1.0.0` |
| `.morphir.tgz` | `.jar` containing Morphir files |

#### JAR Structure

```
my-org-core-1.0.0.jar
├── META-INF/
│   ├── MANIFEST.MF
│   └── maven/
│       └── dev.morphir/
│           └── my-org-core/
│               ├── pom.xml
│               └── pom.properties
├── morphir.toml
├── morphir-ir.json
└── src/
```

**Generated `pom.xml`:**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<project>
  <modelVersion>4.0.0</modelVersion>
  <groupId>dev.morphir</groupId>
  <artifactId>my-org-core</artifactId>
  <version>1.0.0</version>
  <packaging>jar</packaging>

  <name>my-org/core</name>
  <description>Core domain models for my-org</description>

  <properties>
    <morphir.name>my-org/core</morphir.name>
    <morphir.formatVersion>4</morphir.formatVersion>
  </properties>

  <dependencies>
    <dependency>
      <groupId>dev.morphir</groupId>
      <artifactId>morphir-sdk</artifactId>
      <version>3.0.0</version>
    </dependency>
  </dependencies>
</project>
```

#### Configuration

```toml
# morphir.toml
[registry]
backend = "maven"

[registry.maven]
# Maven repository URL
repository = "https://repo1.maven.org/maven2"

# For publishing (e.g., Sonatype OSSRH)
snapshot_repository = "https://oss.sonatype.org/content/repositories/snapshots"
release_repository = "https://oss.sonatype.org/service/local/staging/deploy/maven2"

# Group ID prefix (default: dev.morphir)
group_id = "dev.morphir"
```

#### Authentication

Maven authentication uses standard Maven settings:

```xml
<!-- ~/.m2/settings.xml -->
<settings>
  <servers>
    <server>
      <id>ossrh</id>
      <username>${env.MAVEN_USERNAME}</username>
      <password>${env.MAVEN_PASSWORD}</password>
    </server>
  </servers>
</settings>
```

## CLI Commands

### Pack

Creates a distributable package from a project.

```bash
# Pack current project
morphir pack

# Pack specific project in workspace
morphir pack --project my-org/core

# Pack with specific output location
morphir pack --output dist/

# Pack without sources
morphir pack --no-sources

# Pack for specific backend (affects format)
morphir pack --backend npm
morphir pack --backend maven
```

#### Behavior

1. Verify project builds successfully
2. Validate package metadata (name, version, license)
3. Compile IR to distribution format
4. Create archive based on backend format
5. Write to output directory

#### Output

```
$ morphir pack
Building my-org/core...
Validating package metadata...
Creating package archive...

Created: dist/my-org-core-1.0.0.morphir.tgz
  Size: 45.2 KB
  IR Format: v4
  Includes sources: yes
```

### Publish

Uploads a package to the configured registry.

```bash
# Publish current project
morphir publish

# Publish specific package file
morphir publish dist/my-org-core-1.0.0.morphir.tgz

# Publish to specific registry
morphir publish --registry https://npm.my-org.com

# Dry run (validate without uploading)
morphir publish --dry-run

# Publish with specific tag (npm)
morphir publish --tag beta
```

#### Behavior

1. Verify package archive exists (or run pack)
2. Validate credentials for registry
3. Check if version already exists
4. Transform package for backend (if needed)
5. Upload to registry
6. Verify upload success

#### Output

```
$ morphir publish
Publishing my-org/core@1.0.0 to npm...
Authenticating with registry.npmjs.org...
Uploading @morphir/my-org--core@1.0.0...

Published: https://www.npmjs.com/package/@morphir/my-org--core
```

### Other Commands

```bash
# List published versions
morphir registry versions my-org/core

# Search for packages
morphir registry search "domain model"

# Show package info
morphir registry info my-org/core@1.0.0

# Unpublish (if supported by registry)
morphir registry unpublish my-org/core@1.0.0 --force
```

## WIT Interface

```wit
/// Package archive
record package-archive {
    /// Package name
    name: package-path,
    /// Package version
    version: semver,
    /// Archive contents (tar.gz bytes)
    data: list<u8>,
    /// Checksum
    checksum: string,
}

/// Registry configuration
record registry-config {
    /// Backend type
    backend: registry-backend-type,
    /// Registry URL
    url: string,
    /// Additional backend-specific options
    options: list<tuple<string, string>>,
}

/// Backend types
enum registry-backend-type {
    npm,
    github,
    maven,
}

/// Pack a project into a distributable package
pack: func(
    project: package-path,
    options: pack-options,
) -> result<package-archive, package-error>;

/// Publish a package to a registry
publish: func(
    archive: package-archive,
    config: registry-config,
) -> result<publish-result, registry-error>;

/// Fetch a package from a registry
fetch-package: func(
    name: package-path,
    version: semver,
    config: registry-config,
) -> result<package-archive, registry-error>;
```

## JSON-RPC

### Pack

**Request:**
```json
{
  "method": "package/pack",
  "params": {
    "project": "my-org/core",
    "options": {
      "includeSources": true,
      "outputDir": "dist/"
    }
  }
}
```

**Response:**
```json
{
  "result": {
    "path": "dist/my-org-core-1.0.0.morphir.tgz",
    "name": "my-org/core",
    "version": "1.0.0",
    "size": 46284,
    "checksum": "sha256:abc123..."
  }
}
```

### Publish

**Request:**
```json
{
  "method": "package/publish",
  "params": {
    "archive": "dist/my-org-core-1.0.0.morphir.tgz",
    "registry": {
      "backend": "npm",
      "url": "https://registry.npmjs.org"
    }
  }
}
```

**Response:**
```json
{
  "result": {
    "name": "my-org/core",
    "version": "1.0.0",
    "url": "https://www.npmjs.com/package/@morphir/my-org--core",
    "backend": "npm"
  }
}
```

## Configuration Reference

### Project-Level

```toml
# morphir.toml

[project]
name = "my-org/core"
version = "1.0.0"

[package]
# Package metadata
description = "Core domain models"
license = "Apache-2.0"
repository = "https://github.com/my-org/core"
readme = "README.md"
changelog = "CHANGELOG.md"

# What to include in package
[package.include]
sources = true           # Include src/ directory
readme = true            # Include README
changelog = true         # Include CHANGELOG

# Files to exclude from package
[package.exclude]
patterns = ["*.test.morphir", "internal/*"]

[registry]
# Default backend
backend = "npm"

[registry.npm]
scope = "@my-org-morphir"
access = "public"
```

### Workspace-Level

```toml
# morphir.toml (workspace root)

[workspace]
members = ["packages/*"]

# Default registry settings for all members
[registry]
backend = "npm"

[registry.npm]
scope = "@my-org-morphir"
registry = "https://npm.pkg.github.com"
```

## Dependency Resolution with Registries

When registry dependencies become available, the dependency system will integrate with registry backends:

```toml
[dependencies]
# Future: registry dependency
"morphir/sdk" = "3.0.0"

# Current: explicit registry
"morphir/sdk" = { version = "3.0.0", registry = "npm" }

# With specific registry URL
"internal/utils" = { version = "1.0.0", registry = { backend = "npm", url = "https://npm.internal.com" } }
```

Resolution will:
1. Query configured registry backend for available versions
2. Download package archive
3. Extract to dependency cache
4. Verify checksum

## Best Practices

1. **Semantic Versioning**: Follow semver for version numbers
2. **Meaningful Descriptions**: Include clear package descriptions
3. **License Compliance**: Always specify license
4. **Minimal Packages**: Exclude test files and internal modules
5. **Changelog**: Maintain a changelog for each version
6. **CI/CD Publishing**: Automate publishing from CI pipelines

## Future Backends

Additional backends may be supported in the future:

| Backend | Format | Use Case |
|---------|--------|----------|
| **OCI Registry** | Container image layers | Cloud-native deployments, artifact registries |
| **S3/GCS** | Object storage | Private infrastructure, air-gapped environments |
| **Artifactory** | Universal | Enterprise artifact management |
| **Morphir Registry** | Native format | Dedicated Morphir ecosystem (planned) |
