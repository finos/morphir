---
title: Distribution Structure
sidebar_label: Distributions
sidebar_position: 7
---

# Distribution Structure

A Distribution is the top-level container representing a complete compilation unit with its dependencies.

## Distribution Types

```gleam
// === distribution.gleam ===

/// Distribution variants
pub type Distribution(attributes) {
  /// A library distribution - reusable package with implementations
  Library(library: LibraryDistribution(attributes))

  /// A specs distribution - specifications only (no implementations)
  /// Used for native/external dependencies, FFI bindings, SDK primitives
  Specs(specs: SpecsDistribution(attributes))

  /// An application distribution - executable with named entry points
  Application(application: ApplicationDistribution(attributes))
}

/// Library distribution - a package plus its resolved dependencies
/// Contains full definitions (implementations)
pub type LibraryDistribution(attributes) {
  LibraryDistribution(
    /// The package being compiled/distributed
    package: PackageInfo,
    /// Full definition of the local package
    definition: PackageDefinition(attributes),
    /// Resolved dependency specifications (not full definitions)
    dependencies: Dict(PackagePath, PackageSpecification(attributes)),
  )
}

/// Specs distribution - specifications only, no implementations
/// Used for:
/// - Native/FFI bindings (types exist but implementations are platform-specific)
/// - External SDKs (Morphir.SDK basics implemented natively per-platform)
/// - Third-party packages where only the public API is needed for type-checking
pub type SpecsDistribution(attributes) {
  SpecsDistribution(
    /// The package being described
    package: PackageInfo,
    /// Public specifications only (no implementations)
    specification: PackageSpecification(attributes),
    /// Other specs this depends on (also specification-only)
    dependencies: Dict(PackagePath, PackageSpecification(attributes)),
  )
}

/// Application distribution - executable package with named entry points
/// Like a statically linked binary, contains full definitions for all dependencies
pub type ApplicationDistribution(attributes) {
  ApplicationDistribution(
    /// The application package
    package: PackageInfo,
    /// Full definition of the application
    definition: PackageDefinition(attributes),
    /// Fully resolved dependencies (complete definitions, not just specs)
    /// Enables standalone execution without external dependency resolution
    dependencies: Dict(PackagePath, PackageDefinition(attributes)),
    /// Named entry points into the application
    entry_points: Dict(Name, EntryPoint),
  )
}

/// An entry point into an application
pub type EntryPoint {
  EntryPoint(
    /// The value to invoke
    target: FQName,
    /// What kind of entry point this is (main, command, handler, job, policy)
    kind: EntryPointKind,
    /// Documentation for this entry point
    doc: Option(Documentation),
  )
}

> **Note:** Entry points are stored as `Dict(Name, EntryPoint)` where:
> - The **key** (Name) is an arbitrary identifier chosen by the developer (e.g., `"startup"`, `"api-handler"`, `"build"`)
> - The **`kind`** field categorizes the entry point semantically (one of: `main`, `command`, `handler`, `job`, `policy`)
>
> The key and kind can differ. For example, you might name an entry point `"startup"` but mark it as `kind: "main"`, or name it `"api"` but mark it as `kind: "handler"`.

/// Classification of entry points
pub type EntryPointKind {
  /// Default/primary entry point (like main)
  Main
  /// CLI subcommand
  Command
  /// Service endpoint or message handler
  Handler
  /// Batch or scheduled job
  Job
  /// Business policy or rule
  Policy
}

/// Package metadata
pub type PackageInfo {
  PackageInfo(
    name: PackagePath,
    version: SemanticVersion,
  )
}
```

## Distribution Type Comparison

| Aspect | Library | Specs | Application |
|--------|---------|-------|-------------|
| **Contains** | Definitions | Specifications only | Definitions + entry points |
| **Dependencies** | PackageSpecification | PackageSpecification | PackageDefinition (full) |
| **Use case** | Reusable packages | Native bindings, FFI, SDK | Executables, services, CLIs |
| **Analogy** | Shared library (.so/.dll) | Header files (.h) | Static binary |
| **Entry points** | None (any public value) | N/A | Named entry points with kind |

## Entry Point Kinds

> **Note:** Entry point kinds categorize entry points semantically. The **entry point name** (the dictionary key) and the **kind** serve different purposes:
>
> - **Name** (key): Arbitrary identifier chosen by developers (e.g., `"startup"`, `"build"`, `"api-handler"`)
> - **Kind**: Semantic category from a fixed set (see table below)
>
> The name and kind can differ. For example, you might name an entry point `"startup"` but mark it as `kind: "main"`, or name it `"api"` but mark it as `kind: "handler"`.

| Kind | Description | Example |
|------|-------------|---------|
| `Main` | Default/primary entry point | Application startup |
| `Command` | CLI subcommand | `morphir build`, `morphir test` |
| `Handler` | Service endpoint or message handler | HTTP route, queue consumer |
| `Job` | Batch or scheduled job | Nightly report, data sync |
| `Policy` | Business policy or rule | Validation rule, pricing policy |

## Semantic Versioning

Full semantic version support per the [SemVer 2.0.0 specification](https://semver.org/).

```gleam
// === semver.gleam ===

/// Semantic version with full pre-release and build metadata support
/// Format: MAJOR.MINOR.PATCH[-PRERELEASE][+BUILD]
pub type SemanticVersion {
  SemanticVersion(
    major: Int,
    minor: Int,
    patch: Int,
    pre_release: Option(PreRelease),
    build_metadata: Option(BuildMetadata),
  )
}

/// Pre-release version identifiers
/// Examples: alpha, alpha.1, 0.3.7, x.7.z.92
pub type PreRelease {
  PreRelease(identifiers: List(PreReleaseIdentifier))
}

/// A pre-release identifier is either numeric or alphanumeric
pub type PreReleaseIdentifier {
  NumericIdentifier(value: Int)
  AlphanumericIdentifier(value: String)
}

/// Build metadata (ignored in version precedence)
/// Examples: 001, 20130313144700, exp.sha.5114f85
pub type BuildMetadata {
  BuildMetadata(identifiers: List(String))
}

/// Parse a semantic version string
pub fn semver_from_string(s: String) -> Result(SemanticVersion, String) {
  // Split off build metadata first (after +)
  let #(version_pre, build) = case string.split(s, "+") {
    [vp, b] -> #(vp, Some(parse_build_metadata(b)))
    [vp] -> #(vp, None)
    _ -> #(s, None)
  }

  // Split off pre-release (after -)
  let #(version, pre) = case string.split_once(version_pre, "-") {
    Ok(#(v, p)) -> #(v, Some(parse_pre_release(p)))
    Error(_) -> #(version_pre, None)
  }

  // Parse core version
  case string.split(version, ".") {
    [maj, min, pat] -> {
      use major <- result.try(int.parse(maj) |> result.map_error(fn(_) { "Invalid major" }))
      use minor <- result.try(int.parse(min) |> result.map_error(fn(_) { "Invalid minor" }))
      use patch <- result.try(int.parse(pat) |> result.map_error(fn(_) { "Invalid patch" }))
      Ok(SemanticVersion(major, minor, patch, pre, build))
    }
    _ -> Error("Invalid version format: expected MAJOR.MINOR.PATCH")
  }
}

/// Render semantic version to canonical string
pub fn semver_to_string(v: SemanticVersion) -> String {
  let core = int.to_string(v.major) <> "." <>
             int.to_string(v.minor) <> "." <>
             int.to_string(v.patch)

  let with_pre = case v.pre_release {
    Some(pre) -> core <> "-" <> pre_release_to_string(pre)
    None -> core
  }

  case v.build_metadata {
    Some(build) -> with_pre <> "+" <> build_metadata_to_string(build)
    None -> with_pre
  }
}

/// Compare two semantic versions for precedence
/// Build metadata is ignored per SemVer spec
pub fn semver_compare(a: SemanticVersion, b: SemanticVersion) -> Order {
  // Compare core version first
  case int.compare(a.major, b.major) {
    Eq -> case int.compare(a.minor, b.minor) {
      Eq -> case int.compare(a.patch, b.patch) {
        Eq -> compare_pre_release(a.pre_release, b.pre_release)
        other -> other
      }
      other -> other
    }
    other -> other
  }
}
```

### Semantic Version Examples

| Version String | Parsed |
|----------------|--------|
| `1.0.0` | `SemanticVersion(1, 0, 0, None, None)` |
| `1.0.0-alpha` | `SemanticVersion(1, 0, 0, Some(PreRelease([Alpha("alpha")])), None)` |
| `1.0.0-alpha.1` | `SemanticVersion(1, 0, 0, Some(PreRelease([Alpha("alpha"), Num(1)])), None)` |
| `1.0.0-0.3.7` | `SemanticVersion(1, 0, 0, Some(PreRelease([Num(0), Num(3), Num(7)])), None)` |
| `1.0.0+20130313` | `SemanticVersion(1, 0, 0, None, Some(BuildMetadata(["20130313"])))` |
| `1.0.0-beta+exp.sha.5114f85` | Full version with pre-release and build metadata |

### Version Precedence (lowest to highest)

```
1.0.0-alpha < 1.0.0-alpha.1 < 1.0.0-alpha.beta < 1.0.0-beta
< 1.0.0-beta.2 < 1.0.0-beta.11 < 1.0.0-rc.1 < 1.0.0
```

## Distribution Modes

```gleam
/// Distribution layout mode
pub type DistributionMode {
  /// Single JSON blob containing entire IR
  ClassicMode
  /// Directory tree with individual files per definition
  VfsMode
}

/// VFS distribution manifest (format.json)
pub type VfsManifest {
  VfsManifest(
    format_version: String,
    layout: DistributionMode,
    package: PackagePath,
    created: String,  // ISO 8601 timestamp
  )
}

/// VFS module manifest (module.json)
pub type VfsModuleManifest {
  VfsModuleManifest(
    format_version: String,
    path: ModulePath,
    types: List(Name),
    values: List(Name),
  )
}
```

### Distribution Modes Comparison

| Mode | Structure | Use Case |
|------|-----------|----------|
| **Classic** | Single `morphir-ir.json` blob | Simple projects, backwards compatibility |
| **VFS** | `.morphir-dist/` directory tree | Large projects, incremental updates, shell tools |

## IR Hierarchy Summary

```
Distribution
├── Library(LibraryDistribution)
│   ├── package: PackageInfo (name, version)
│   ├── definition: PackageDefinition
│   │   └── modules: Dict(ModulePath, AccessControlled(ModuleDefinition))
│   └── dependencies: Dict(PackagePath, PackageSpecification)
│
├── Specs(SpecsDistribution)
│   ├── package: PackageInfo (name, version)
│   ├── specification: PackageSpecification
│   │   └── modules: Dict(ModulePath, ModuleSpecification)
│   └── dependencies: Dict(PackagePath, PackageSpecification)
│
└── Application(ApplicationDistribution)
    ├── package: PackageInfo (name, version)
    ├── definition: PackageDefinition
    │   └── modules: Dict(ModulePath, AccessControlled(ModuleDefinition))
    ├── dependencies: Dict(PackagePath, PackageDefinition)  ← Full definitions (statically linked)
    └── entry_points: Dict(Name, EntryPoint)
        │   └── Key: Name (arbitrary identifier, e.g., "startup", "build", "api-handler")
        └── EntryPoint
            ├── target: FQName
            ├── kind: EntryPointKind (main|command|handler|job|policy)  ← Semantic category (can differ from key)
            └── doc: Option(Documentation)
```

## JSON Serialization Examples

### Library Distribution (Classic Mode)

Single-blob `morphir-ir.json`:

```json
{
  "formatVersion": "4.0.0",
  "distribution": {
    "Library": {
      "packageName": "my-org/my-project",
      "dependencies": {
        "morphir/sdk": {
          "modules": {
            "basics": { "types": { "...": "..." }, "values": { "...": "..." } },
            "string": { "types": { "...": "..." }, "values": { "...": "..." } },
            "list": { "types": { "...": "..." }, "values": { "...": "..." } }
          }
        }
      },
      "def": {
        "modules": {
          "domain/users": {
            "access": "Public",
            "value": {
              "types": { "...": "..." },
              "values": { "...": "..." }
            }
          }
        }
      }
    }
  }
}
```

### Semantic Version Serialization

Versions are serialized as canonical strings:

```json
"1.0.0"
"2.1.0-alpha.1"
"3.0.0-rc.2+build.456"
"1.0.0+20130313144700"
```

## VFS File Examples

### VFS File Format Version

All VFS node files include a `formatVersion` field using semantic versioning:

```gleam
pub type VfsNodeHeader {
  VfsNodeHeader(
    format_version: String,  // Semver: "4.0.0"
    name: Name,
  )
}
```

### Type File

File: `.morphir-dist/pkg/my-org/domain/types/user.type.json`

```json
{
  "formatVersion": "4.0.0",
  "name": "user",
  "def": {
    "TypeAliasDefinition": {
      "body": {
        "Record": {
          "fields": {
            "created-at": { "Reference": { "fqname": "my-org/sdk:local-date-time#local-date-time" } },
            "email": { "Reference": { "fqname": "morphir/sdk:string#string" } },
            "user-(id)": { "Reference": { "fqname": "my-org/domain:types#user-(id)" } }
          }
        }
      }
    }
  }
}
```

### Value File

File: `.morphir-dist/pkg/my-org/domain/values/get-user-by-email.value.json`

```json
{
  "formatVersion": "4.0.0",
  "name": "get-user-by-email",
  "def": {
    "access": "Public",
    "value": {
      "ExpressionBody": {
        "inputTypes": {
          "email": { "Reference": { "fqname": "morphir/sdk:string#string" } },
          "users": {
            "Reference": {
              "fqname": "morphir/sdk:list#list",
              "args": [{ "Reference": { "fqname": "my-org/domain:types#user" } }]
            }
          }
        },
        "outputType": {
          "Reference": {
            "fqname": "morphir/sdk:maybe#maybe",
            "args": [{ "Reference": { "fqname": "my-org/domain:types#user" } }]
          }
        },
        "body": { "Apply": { "...": "..." } }
      }
    }
  }
}
```

### Module File

File: `.morphir-dist/pkg/my-org/domain/module.json`

```json
{
  "formatVersion": "4.0.0",
  "path": "my-org/domain",
  "types": ["user", "user-(id)", "order"],
  "values": ["get-user-by-email", "create-order", "validate-user"]
}
```

### Format File (Library Distribution)

File: `.morphir-dist/format.json`

```json
{
  "formatVersion": "4.0.0",
  "distribution": "Library",
  "package": "my-org/my-project",
  "version": "1.2.0",
  "created": "2026-01-15T12:00:00Z"
}
```

### Format File (Specs Distribution)

File: `.morphir-dist/format.json`

```json
{
  "formatVersion": "4.0.0",
  "distribution": "Specs",
  "package": "morphir/sdk",
  "version": "3.0.0",
  "created": "2026-01-15T12:00:00Z"
}
```

### Format File (Application Distribution)

File: `.morphir-dist/format.json`

```json
{
  "formatVersion": "4.0.0",
  "distribution": "Application",
  "package": "my-org/my-cli",
  "version": "2.0.0",
  "created": "2026-01-15T12:00:00Z",
  "entryPoints": {
    "startup": {
      "target": "my-org/my-cli:main#run",
      "kind": "main",
      "doc": "Primary application entry point"
    },
    "build": {
      "target": "my-org/my-cli:commands#build",
      "kind": "command",
      "doc": "Build the project"
    },
    "validate": {
      "target": "my-org/my-cli:commands#validate",
      "kind": "command",
      "doc": "Validate project configuration"
    },
    "api-handler": {
      "target": "my-org/my-cli:api#handle-request",
      "kind": "handler",
      "doc": "HTTP API request handler"
    },
    "nightly-report": {
      "target": "my-org/my-cli:jobs#generate-report",
      "kind": "job",
      "doc": "Scheduled nightly report generation"
    },
    "pricing-policy": {
      "target": "my-org/my-cli:policies#calculate-price",
      "kind": "policy",
      "doc": [
        "Calculate product pricing based on rules.",
        "Applies discounts, taxes, and regional adjustments."
      ]
    }
  }
```

> **Note on Entry Point Names vs Kinds:**
>
> The entry point structure uses a dictionary where:
> - **Keys** (e.g., `"startup"`, `"build"`, `"api-handler"`) are arbitrary identifiers chosen by developers
> - **`kind` values** (e.g., `"main"`, `"command"`, `"handler"`) are semantic categories from a fixed set
>
> Examples showing the distinction:
> - `"startup"` with `kind: "main"` - The name differs from the kind
> - `"build"` with `kind: "command"` - The name matches the kind (common but not required)
> - `"api-handler"` with `kind: "handler"` - Descriptive name, semantic kind
> - `"nightly-report"` with `kind: "job"` - Job name, job kind
>
> This allows flexible naming while maintaining semantic categorization for tooling and runtime behavior.
}
```

## VFS Specification File Examples

For Specs distributions (or dependencies), files contain specifications instead of definitions.

### Type Specification File

File: `.morphir-dist/pkg/morphir/sdk/types/int.type.json`

```json
{
  "formatVersion": "4.0.0",
  "name": "int",
  "spec": {
    "doc": "Arbitrary precision integer",
    "OpaqueTypeSpecification": {}
  }
}
```

### Value Specification File

File: `.morphir-dist/pkg/morphir/sdk/values/add.value.json`

```json
{
  "formatVersion": "4.0.0",
  "name": "add",
  "spec": {
    "doc": [
      "Add two integers.",
      "This is a native operation implemented per-platform."
    ],
    "inputs": {
      "a": { "Reference": { "fqname": "morphir/sdk:basics#int" } },
      "b": { "Reference": { "fqname": "morphir/sdk:basics#int" } }
    },
    "output": { "Reference": { "fqname": "morphir/sdk:basics#int" } }
  }
}
```
