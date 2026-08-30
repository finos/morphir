---
title: Extension distribution and package acquisition
sidebar_label: Distribution and acquisition
sidebar_position: 3
status: draft
tracking:
  beads: [morphir-ct7h, morphir-h0pf, morphir-uhk3]
---

# Extension distribution and package acquisition

Morphir needs two related distribution systems. Morphir packages distribute reusable logic and types for frontends to compile. Extension distributions deliver capability providers that a Morphir host can load, start, or contact. They should share identity, resolution, integrity, acquisition, caching, and locking machinery without sharing one manifest or lifecycle.

The [Morphir Extension Protocol](./protocol.md) begins after the host has selected an installed extension. This design covers the work that happens before that point and the local state that remains afterward.

The accepted [WASM runtime and Avro backend proposal](../../proposals/wasm-extension-runtime-and-avro-backend.md)
specializes this draft for portable WASM extensions. That feature is not
released. The accepted proposal controls if the two documents differ.

## Boundaries

| Concern | Morphir package | Extension distribution |
|---|---|---|
| Purpose | Supply reusable model logic and types | Supply frontend, backend, validator, or transform capabilities |
| Primary content | Source modules and native project metadata | WASM module, executable, JVM artifact, or daemon connection metadata |
| Materialized result | Verified source tree | Verified runnable artifact or connection description |
| Consumer | Frontend and build pipeline | Extension host |
| Runtime lifecycle | Compiled as build input | Initialized, called, cancelled, and stopped through MEP |
| Platform selection | Usually none for source packages | Often required for native and JVM artifacts |

An extension may consume Morphir packages while compiling a project. That dependency does not turn the package into an extension or make the extension host responsible for package semantics.

## Direction from Morphir Scala and MoonBit

The morphir-scala knowledge base contains two inputs to this design:

- [Package URL-centered package management](https://github.com/finos/morphir-scala/blob/2f697f4e4155926eb3107c8f83b009fe2d0b3f40/kb/bundles/morphir/morphir-scala/design/package-url-package-management.md) proposes Package URL as the canonical package identity, Package VERS for ranges, typed source descriptors, immutable resolution, content digests, and locks that retain the complete graph and provenance.
- [MoonBit registry, resolution, and source materialization](https://github.com/finos/morphir-scala/blob/2f697f4e4155926eb3107c8f83b009fe2d0b3f40/kb/bundles/morphir/morphir-scala/design/moonbit-package-management.md) documents a Git-distributed registry index with one line-delimited history per package, a small resolver-facing record, separate archive storage, checksum verification, staged extraction, and immutable materialized trees.

MoonBit provides architectural evidence, not a format to copy. Its implementation is AGPL-3.0, its version-selection rules belong to its ecosystem, and its observed registry has case-colliding paths that fail on common case-insensitive filesystems. Morphir must define its own schema, namespace rules, and resolution policy.

The useful lessons are:

1. Keep logical identity independent from content location.
2. Keep the resolver record small while allowing publication metadata to grow.
3. Resolve the complete graph before acquiring content.
4. Verify cached and downloaded bytes before materialization.
5. Validate the materialized manifest against the selected identity.
6. Pin the registry-index revision as well as package versions and digests.
7. Treat local workspace replacements as policy over a stable identity, not as publishable dependencies.

## Shared distribution kernel

A common distribution kernel should provide pure value types and effects for:

- canonical identity and version requirements;
- version discovery and dependency metadata;
- exact resolution and lock generation;
- typed source descriptors and provenance;
- content and normalized-tree digests;
- authenticated acquisition;
- staged verification and materialization;
- content-addressed storage under `MorphirHome`;
- offline and mirror-aware lookup.

Interpreters provide network, Git, filesystem, credential, archive, and cache behavior. Buildkit, frontends, and the extension host consume resolved or materialized values and do not depend on registry URLs, cache layouts, or credentials.

Package and extension policy remains above this shared kernel:

- the Morphir package resolver understands package dependencies, source roots, module enumeration, and source-package locks;
- the extension resolver understands capabilities, MEP versions, permissions, runtime kinds, operating systems, architectures, launch arguments, and daemon endpoints;
- each family validates its own manifest after materialization.

## Registry architecture

The first distributed registry backend should be service-free and mirrorable. A Git-backed index is a good launch option when paired with a local-directory backend for tests and air-gapped use.

The index should partition histories by a canonical, filesystem-portable encoding of package identity. Each version record should contain only what resolution needs:

- exact identity and version;
- dependency requirements when the package family supports dependencies;
- source descriptor or an input from which the source can be derived;
- content digest and digest algorithm;
- manifest kind and schema version;
- optional yanked or revoked status.

Presentation fields such as descriptions, licenses, documentation, maintainers, and search keywords may extend the record without becoming inputs to dependency resolution.

The client pins the Git commit used for resolution. A future HTTP registry may expose the same logical operations, but reproducibility must not depend on a mutable `latest` response. Mirrors may provide the same identity and digest from a different location.

### Index and repository topology

Morphir packages and extension distributions use separate logical registry indexes. Each index has its own record schema, validation rules, version history, and resolution policy. A model-package index cannot contain extension records, and an extension index cannot contain model-package records.

Both indexes implement the same client capability for version discovery, exact-record lookup, provenance, and mirroring. That shared capability does not erase the different record types.

An index is a metadata view, not a Git repository. The Git-file backend may store both indexes in one repository under separate roots, for example `model-packages/` and `extensions/`. Deployments may also place them in separate repositories or expose them through different services. Repository layout is a backend and operational choice. It does not change the logical index boundary.

When one Git repository contains both indexes, a lock records the index kind, logical index identity, repository source, root path, and pinned commit. This prevents the shared repository from making an index reference ambiguous.

### Release channels

Each index supports release channels as mutable version-selection policy. The first channel model includes:

- `stable` for versions intended for general use;
- `preview` for pre-release testing, also exposed as `insiders` by products that already use that name;
- optional segmented preview channels such as `preview/<segment>` for a bounded prototype, compatibility test, or staged rollout.

A segmented preview channel remains part of the same logical index. It does not create a new package identity, extension identity, or registry index. Index policy defines valid segment names, who may publish to them, and whether they inherit candidates from the general preview channel.

A channel request resolves to an exact version before acquisition. The lock records the requested channel, exact selected identity and version, index revision, source, and digest. Reusing the lock never follows a moving channel. Refreshing or changing channels is an explicit resolution operation.

Stable resolution excludes preview versions unless the request or workspace policy opts into them. Promotion changes channel eligibility. It does not let a registry replace locked bytes for an existing exact identity and digest.

## Morphir package flow

```mermaid
flowchart LR
    Requirement[Package requirement] --> Index[Registry index]
    Index --> Resolve[Resolve graph]
    Resolve --> Lock[Write or verify lock]
    Lock --> Acquire[Acquire sources]
    Acquire --> Verify[Verify and materialize]
    Verify --> Frontend[Compile with frontend]
```

A Morphir package is a source distribution first. A materialized package may come from a registry archive, immutable Git commit, vendored tree, or workspace snapshot. All sources must declare the same logical identity and produce the locked normalized digest. Compiler caches and generated IR remain derived data unless a later package format explicitly includes them.

Compilation receives a prepared source view and runs without package-network access. Credentials remain confined to acquisition and are resolved through the protected secret mechanism.

## Extension flow

```mermaid
flowchart LR
    Request[Capability request] --> Catalog[Installed extension catalog]
    Catalog --> Resolver[Select distribution and artifact]
    Resolver --> Acquire[Acquire if explicitly requested]
    Acquire --> Verify[Verify and install]
    Verify --> Runtime[Select runtime adapter]
    Runtime --> MEP[Open MEP session]
```

The installed extension catalog is local state, not the distributed registry.
It records the extension ID, name, version, runtime, platform, arguments,
artifact digest, content-addressed store path, capabilities, MEP versions,
index provenance, backend metadata, and executable mode. The matching lock also
records the requested selection and artifact source; the catalog does not. The
host uses the catalog and lock together to select an artifact and runtime
without contacting a registry during normal execution.

An extension manifest needs:

- extension identity and version;
- supported MEP versions;
- declared capabilities and languages or targets;
- requested permissions;
- one or more artifacts;
- each artifact's runtime kind, source, digest, and platform constraints;
- launch commands and arguments for managed processes;
- endpoint and authentication requirements for connected daemons.

The runtime kind is independent from the acquisition source. A GitHub Release may contain a portable WASM module, a native process, or a JVM process. A daemon entry may require no artifact at all when policy permits connecting to an existing endpoint.

Schema-v2 extension records use these rules for runnable artifacts:

| Runtime | Platform | Arguments and executable bit | Rights |
|---|---|---|---|
| `wasm` | Must be absent. The artifact is portable. | Arguments must be empty and `executable` must be `false`. | The guest has no direct filesystem or network access. |
| `process` | Required and matched to the host OS and architecture. | The locked arguments and executable mode are used exactly. | The process retains the ambient rights of the user who launches Morphir. |

`wasm` is the public runtime name. Extism is the current engine behind that
adapter and does not appear as a runtime value. A future WASM engine can replace
it without changing an extension record or the MEP methods.

Installation verifies the selected artifact's SHA-256 before publishing it to
the content-addressed store. It then records the exact artifact in both the
catalog and lock. Backend records also lock target IDs and supported Morphir IR
versions. Normal activation is offline. It loads one catalog and lock snapshot,
checks that they agree, canonicalizes the stored artifact under Morphir home,
rehashes it, and verifies its runtime-specific mode before starting a session.

The MEP handshake is a second check, not a replacement for the lock:

| Stage | Compared values | Result on mismatch |
|---|---|---|
| Catalog against lock | Extension ID, name, version, runtime, platform, arguments, digest, capabilities, MEP versions, index provenance, complete backend metadata, and executable mode | Activation stops before guest code runs. |
| Installed record against initialization | Extension ID, name, version, capability kinds, and the complete backend capability, including targets, IR versions, and `generate` | The host rejects initialization and does not call the backend. |
| Requested operation against negotiated capability | Target ID, input IR version, and `generate` support | The host does not send `morphir.backend.generate`. |

This comparison prevents a verified file from silently advertising a different
backend after installation. Artifact integrity proves which bytes the host
loaded. The handshake proves what those bytes claim in the current session.

The host supports these activation modes behind one session contract:

- load a portable WASM module through the current Extism engine;
- spawn a process and use `Content-Length` framed MEP over standard input and output;
- connect to an existing daemon through a specified MEP socket or HTTP transport;
- start a managed daemon, wait for its endpoint, and then use the daemon transport;
- call a built-in provider through the same logical operation contract where practical.

## Morphir Scala example

Morphir Scala publishes native CLI archives, a portable executable JVM assembly, and checksums through GitHub Releases. An extension record can point at those independently released assets instead of packaging them with the Morphir CLI.

On Windows ARM64, the resolver selects the JVM artifact because GraalVM Native Image does not provide a Windows ARM64 target. Installation verifies the release checksum and records a launch description such as `java -jar <artifact> extension stdio`. Other platforms may select a native artifact from the same extension version. Both variants must report the same MEP identity and capabilities.

The existing `morphir server` command becomes an extension daemon only if it implements a specified MEP transport and lifecycle. Otherwise Morphir Scala should expose a dedicated MEP entry point. A user-facing HTTP server and a host-managed standard-stream process have different lifecycle and logging requirements.

## Security and reproducibility

- Normal compilation and generation do not download missing extensions without an explicit install policy.
- Checksums provide integrity, not publisher authenticity. Signature or provenance verification remains an open policy decision.
- Registry and Git credentials use protected secret references and never enter identities, locks, manifests, transcripts, or diagnostics.
- Installation uses staging and atomic publication so readers never observe partial content.
- Archives must reject path traversal, unsafe links, device files, and platform path collisions.
- Native processes inherit a filtered environment and explicit working directory.
- Daemon connections require a transport-specific identity, authentication, timeout, and ownership policy.
- Locks retain the exact registry snapshot, selected records, sources, digests, and transitive package graph.

## Current host and guest split

The SDK keeps protocol types and extension traits portable across native and
WASM builds. Its Extism PDK dependency, guest exports, and imported host
functions are compiled only for `wasm32`. Native hosts use the Extism runtime
adapter and do not link guest PDK imports.

Process and WASM adapters feed the same runtime-neutral MEP session controller.
An in-memory provider remains useful for unit tests, while runtime tests load an
independently built artifact through the production host boundary.

## Open questions

1. Which Package URL convention identifies Morphir-native packages, and should extension distributions use that type or a distinct provisional type?
2. What normalized digest rules remain stable across archives and case-sensitive or case-insensitive filesystems?
3. Which version and range rules apply to Morphir-native packages and extensions?
4. Which signature or build-provenance policy establishes publisher authenticity?
5. How does a host distinguish a daemon it owns from an endpoint it only connects to?
6. Which yank and revocation behavior must work before the first public registry?

## Non-goals

- Copy MoonBit's index schema, resolver, or AGPL implementation.
- Make MEP responsible for installation or registry storage.
- Treat a Morphir package as an executable extension.
- Require a network service for the first registry backend.
- Let compiler or runtime cache layouts become public package contracts.
- Infer trust from a checksum alone.
