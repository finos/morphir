# Morphir

Morphir represents business logic as a language-neutral model and provides tools that read, transform, and generate that model.

## Language

**Configuration model**:
The nested set of Morphir settings after parsing, independent of the file syntax used to write them.
_Avoid_: TOML model, YAML model

**Configuration serialization**:
A file syntax that represents the configuration model, such as TOML or YAML.
_Avoid_: Configuration model

**Effective configuration**:
The configuration model produced after Morphir merges defaults and configured sources in precedence order.
_Avoid_: Final file, merged file

**Global user configuration**:
Configuration that applies to every Morphir workspace for one operating-system user.
_Avoid_: User override, project configuration

**Morphir Home**:
The per-user coordination boundary shared by Morphir components for configuration, durable state, installed artifacts, caches, and logs.
_Avoid_: Cache directory, configuration directory, user profile

**Cache entry**:
Re-creatable content beneath Morphir Home's cache directory that a maintenance operation may remove when no active operation holds it.
_Avoid_: Installed artifact, active release

**Verified artifact store**:
The content-addressed area of Morphir Home containing installed tool and extension artifacts whose removal requires catalog and runtime reachability checks.
_Avoid_: Download cache, temporary staging

**User override**:
Personal configuration stored beside one Morphir project, workspace, or workspace-member configuration and loaded above its shared settings.
_Avoid_: Global user configuration

**Secret reference**:
An inert configuration value that names an external source for a secret without containing the resolved secret.
_Avoid_: Secret, credential value

**Secret resolver**:
An explicitly invoked capability that turns one secret reference into a protected secret value.
_Avoid_: Configuration loader, automatic resolution

**Protected secret**:
A resolved secret value that redacts formatting, has no ordinary serialization path, and requires an explicit operation to expose its contents.
_Avoid_: Plain string, secret reference

## Extensions

**Morphir Extension Protocol**:
The versioned contract between a Morphir host and an extension.
_Avoid_: CLI protocol, backend protocol

**Extension**:
An independently packaged provider of one or more Morphir capabilities.
_Avoid_: Plugin, backend when referring to every extension type

**Extension host**:
The Morphir component that discovers, starts, negotiates with, and calls extensions.
_Avoid_: Extension server, backend manager

**Frontend**:
An extension capability that compiles source documents into Morphir IR.
_Avoid_: Compiler extension

**Backend**:
An extension capability that converts Morphir IR into generated artifacts.
_Avoid_: Extension when referring to any capability provider

**Capability**:
A named family of operations that an extension can provide.
_Avoid_: Feature flag, extension type

**Provider registry**:
The host-local collection of built-in and installed provider snapshots considered during capability resolution.
_Avoid_: Extension registry, extension catalog, installed extension inventory

**Provider origin**:
Whether an extension provider is built into the host or comes from the installed extension inventory. Among eligible providers, installed takes precedence over built-in.
_Avoid_: Invocation mode, transport, runtime

**Invocation mode**:
The route an extension host selects to call one resolved provider, independent of the provider's origin.
_Avoid_: Provider origin, capability, extension type

**Native direct**:
An invocation mode that calls a trusted in-process extension through typed native capability traits without Morphir Extension Protocol serialization.
_Avoid_: Built-in provider, native MEP

**Native MEP**:
An invocation mode that calls a trusted in-process extension through the Morphir Extension Protocol, using the same extension instance available to native direct invocation.
_Avoid_: Native direct, process MEP, WASM MEP

**Extension distribution**:
A versioned package that describes an extension and provides one or more artifacts that can implement it.
_Avoid_: Morphir package, loaded extension

**Extension artifact**:
A runnable payload for one extension runtime and, when applicable, one operating-system and architecture target.
_Avoid_: Extension, source package

**Extension repository**:
A logical collection of published extension releases, repository metadata, and artifacts, independent of how clients access it.
_Avoid_: Index, registry when no service is involved, installed extension inventory

**Repository endpoint**:
A configured location through which a Morphir client accesses one repository, such as a directory, Git checkout, HTTP URL, or OCI reference.
_Avoid_: Repository, registry, mirror

**Extension registry**:
A network service that hosts one or more extension repositories.
_Avoid_: Local repository, catalog, index

**Extension catalog**:
The searchable view Morphir builds from the enabled extension repositories.
_Avoid_: Repository, registry, installed extension inventory

**Repository metadata**:
The backend-specific records used to discover and resolve releases in a repository, such as an index, TUF metadata, or OCI manifests.
_Avoid_: Repository, catalog, installed inventory

**Installed extension inventory**:
The host's local record of verified extension distributions available for selection and activation.
_Avoid_: Extension catalog, extension repository, loaded-extension registry

## Tools

**Tool**:
An independently packaged Morphir executable or application launched by a person.
_Avoid_: Extension, component

**Desktop**:
The graphical Morphir tool with the canonical tool identity `desktop`.
_Avoid_: Desktop extension, UI component

**Tool distribution**:
A versioned package that describes a tool and provides one or more platform-specific artifacts.
_Avoid_: Extension distribution, Morphir package, installed tool

**Tool repository**:
An authenticated logical source of tool release descriptors and artifacts governed by one trust root.
_Avoid_: Repository mirror, installed tool catalog, download cache

**Repository mirror**:
A location that serves metadata and artifacts for one tool repository without becoming a separate trust authority.
_Avoid_: Tool repository, release channel

**Trusted repository root**:
The out-of-band trust anchor and its accepted rotation state for one tool repository.
_Avoid_: Repository mirror, TLS certificate, signing key

**Tool release descriptor**:
The immutable record for one exact tool version, including compatibility, channel membership, and platform artifacts.
_Avoid_: Release channel, tool artifact, installed selection

**Installed tool inventory**:
The local record of verified tool distributions and the exact release active for each tool.
_Avoid_: Tool catalog, tool registry, release index, download cache

**Protected release**:
An installed tool or extension release that cleanup cannot remove because it is active, retained for rollback, pinned, leased by a running process, or referenced by another durable record.
_Avoid_: Cached version, latest version

**Installed selection**:
The persistent update intent for an installed tool or extension, expressed as a release channel or an exact version.
_Avoid_: Active version, latest version

## Packages

**Morphir package**:
A named collection of modules that define reusable logic and types and are distributed together.
_Avoid_: Extension distribution, tool distribution, generated artifact

**Package path**:
The canonical authority-bearing logical name of a Morphir package. Its authority prefix establishes namespace ownership, while its repository or acquisition location remains separate.
_Avoid_: Download URL, repository coordinate, local dependency alias

**Package authority**:
The owner of a Package path prefix, established initially through its authority-bearing name and represented by signed metadata that delegates package namespaces, registry indexes, and publication keys.
_Avoid_: Package registry, package catalog, content mirror

**Authority delegation**:
Signed, versioned metadata through which a Package authority assigns narrower namespace and publication rights. It can be discovered through the authority's well-known HTTPS endpoint or supplied and pinned explicitly.
_Avoid_: Package requirement, registry search result, unsigned mirror configuration

**Package release ID**:
The canonical identity of a Morphir package release, consisting of its Package path and exact semantic version.
_Avoid_: Package requirement, source descriptor, content digest

**Morphir package PURL**:
The standardized external Package URL representation of an exact Package release ID for SBOM, provenance, catalog, vulnerability, and repository interoperability. It does not represent requirements, sources, dependency slots, exports, or unpublished snapshots.
_Avoid_: Package release ID in domain APIs, Package requirement, Module reference

**Morphir package release**:
An immutable versioned Library or Contract release of a Morphir package. Its normative payload is Morphir IR; source code and provenance may accompany it, but they do not replace or redefine that IR.
_Avoid_: Source checkout, extension distribution, tool distribution

**Library release**:
A Morphir package release whose normative payload is a Library distribution containing reusable Morphir implementations. Its Specs distribution is a derived projection.
_Avoid_: Contract release, Application distribution

**Contract release**:
A Morphir package release whose normative payload is a Specs distribution and whose implementations must be supplied by compatible runtimes or executable providers. Providers bind to the exact Package release ID and Specs digest.
_Avoid_: Library release, extension distribution, cryptographic signature

**Morphir distribution**:
A top-level typed Morphir IR compilation artifact: Library, Specs, or Application. Its logical content is independent of whether it is encoded as one document or a document tree.
_Avoid_: Package bundle, extension distribution, tool distribution

**Library distribution**:
The normative reusable IR payload of a Morphir package release, containing the package definition and the dependency specifications needed to interpret it.
_Avoid_: Application distribution, package bundle

**Specs distribution**:
A public-interface Morphir IR distribution and its dependency interfaces. It is a derived projection sharing a Library release's identity, or the normative payload of a Contract release.
_Avoid_: Library distribution, executable provider, separately versioned projection

**Application distribution**:
A versioned, portable Morphir IR artifact linked from a root package and an exact resolved model dependency graph, with required Library implementations, exact Contract requirements, and any declared entry points. It may contain multiple releases or explicit unpublished snapshots of the same Package path, may be stored and distributed, and is not a reusable package dependency.
_Avoid_: Library distribution, executable extension, installable tool

**Application binding**:
A target-specific record that maps every Contract release required by an Application distribution to a compatible executable provider and artifact digest. It remains outside the model package graph.
_Avoid_: Application distribution, Package lock, embedded provider artifact

**Bound application**:
An Application distribution paired with a complete compatible Application binding and therefore ready for its declared runtime target.
_Avoid_: Portable application, installable tool, package bundle

**Package bundle**:
A canonical logical content layout for a package release. It contains its manifest, lock, integrity metadata, and the release kind's normative distribution. That distribution is Library for a Library release and Specs for a Contract release. The bundle may also contain derived projections, source, provenance, or attestations. The same bundle may use a directory, archive, OCI, or repository-specific transport encoding.
_Avoid_: Morphir distribution, package release, transport encoding

**Package authoring configuration**:
The human-maintained package intent within a project's Morphir Configuration model, including Package path, proposed version, requirements, exports, and workspace policy. It may also coexist with non-publishable task, toolchain, source, and credential settings.
_Avoid_: Package release manifest, Package lock, published metadata

**Package release manifest**:
The normalized, immutable, machine-oriented metadata generated during publication and stored in a Package bundle. It contains only portable package identity, requirements, exports, content references, compatibility, and integrity information.
_Avoid_: Package authoring configuration, Effective configuration, Package lock

**Package release statement**:
An authorized signed statement binding one Package release ID to its Package release manifest and Package content digest. Its signing authority follows the Package authority's delegation chain.
_Avoid_: Transport signature, build attestation, registry status

**Registry status statement**:
Signed, versioned registry metadata that records index snapshots and mutable release status such as yank, revocation, or tombstone without changing immutable package content.
_Avoid_: Package release statement, Package release manifest, release channel

**Package compatibility report**:
A machine-readable comparison between a proposed package release and a prior stable release, based on their Package export tables and Specs distributions. It classifies provable structural compatibility and records anything requiring behavioral or human attestation.
_Avoid_: Package lock, changelog, semantic-equivalence proof

**Package content digest**:
A digest of the normalized Package release manifest and the canonical sorted digests of every declared-content file. The manifest does not contain this resulting digest. It remains stable when identical logical content is encoded for a different transport.
_Avoid_: Transport digest, Package release ID, source revision

**Transport digest**:
A digest of one particular encoded archive, blob, or other transport object. It verifies acquisition bytes but does not define the identity of the logical package content.
_Avoid_: Package content digest, Package release ID

**Package requirement**:
A request for a Package path with an explicit semantic-version constraint. Prerelease versions are eligible only when the constraint explicitly admits them.
_Avoid_: Download URL, source location

**Dependency slot**:
A stable name within a consuming Morphir package that associates its IR references with one Package requirement. Different slots may request different versions of the same Package path.
_Avoid_: Package path, source location, resolved package

**Package export path**:
A public logical module path addressed through a dependency slot. It is either generated canonically from a public Morphir Module path or declared as an explicit alias.
_Avoid_: Filesystem path, Package path, source-language import alias

**Package export table**:
The complete immutable mapping from Package export paths to public Morphir Module paths in a package release. Publication expands convention-based exports, exclusions, and aliases into this table; consumers never infer it from a filesystem layout.
_Avoid_: Source directory layout, incomplete export configuration, dependency graph

**Resolved package**:
An exact Package release ID selected for a requirement, together with its dependency metadata, integrity, and source provenance.
_Avoid_: Package requirement, materialized package

**Unpublished package snapshot**:
An immutable IR-first package instance compiled from a workspace, local path, modified vendor tree, or pinned Git revision. It records its declared Package path, source revision or tree digest, compiler provenance, and Package content digest without claiming a published Package release ID.
_Avoid_: Morphir package release, mutable source checkout, package mirror

**Resolved dependency edge**:
A binding from a dependency slot on one resolved node to another resolved node. A resolved node is either an exact Package release or an Unpublished package snapshot. The graph may contain incompatible releases or snapshots of the same Package path without renaming that path.
_Avoid_: Package requirement, import alias, source descriptor

**Package lock**:
A complete reproducibility record that binds every dependency slot in a resolved graph to an exact Package release ID or Unpublished package snapshot, Source descriptor, content digest, and dependency metadata. Normal builds consume it without selecting newer releases.
_Avoid_: Package manifest, registry index, filesystem lock

**Workspace override**:
A root-workspace policy that redirects a Package requirement to a workspace member, local path, pinned Git revision, or vendored source. It never propagates through a published package's dependency metadata.
_Avoid_: Package requirement, Package mirror, transitive dependency

**Legacy package adapter**:
A compatibility boundary that interprets an older Morphir configuration or IR distribution as package-domain values without inventing missing authority or version information. Unsupported graph-aware behavior is reported as a capability error.
_Avoid_: IR migration, silent format upgrade, legacy package manager

**Package diagnostic**:
A stable, versioned, structured report of a package operation's warning or failure, including a machine code, subject, dependency path, details, causes, and human guidance. Integrity and authority diagnostics fail closed and never cause silent trust or resolution fallback.
_Avoid_: Implementation-specific error string, log entry, solver trace

**Package conformance corpus**:
The normative, language-neutral fixtures and expected normalized values, serializations, digests, graphs, and Package diagnostics used to verify package behavior across Morphir implementations.
_Avoid_: Reference implementation, implementation-specific unit tests, examples without assertions

**Source descriptor**:
A typed description of where package content can be acquired, such as a verified registry archive, immutable Git commit, workspace snapshot, or vendored tree.
_Avoid_: Package identity, package requirement

**Materialized package**:
A verified local package tree prepared from a resolved package for compilation or inspection.
_Avoid_: Package archive, compiler cache

**Registry index**:
A distributable metadata view that maps Package paths and versions to dependency, integrity, and Source descriptor information without requiring package content to be downloaded.
_Avoid_: Git repository, artifact store, installed extension catalog

**Package registry**:
A publication and resolution authority that exposes the Registry index capability and may delegate package-content storage to one or more sources. Local-directory, static Git or HTTPS, OCI, and hosted services can provide this capability.
_Avoid_: Package catalog, package bundle, extension registry

**Package catalog**:
A potentially aggregated search and browsing view used to discover Morphir packages. Catalog results do not establish namespace authority or participate in deterministic dependency resolution.
_Avoid_: Package registry, Registry index, dependency lock

**Package mirror**:
An alternate source of byte-identical registry metadata or package bundles. A mirror changes acquisition location but gains no authority to create releases without a valid delegation and publication signature.
_Avoid_: Package authority, Package registry, workspace override

**Yanked package release**:
An immutable package release excluded by mutable registry status from new range-based resolution. Existing locks and explicit exact requirements may continue selecting it under policy.
_Avoid_: Revoked package release, deleted package content, prerelease

**Revoked package release**:
An immutable package release covered by signed security or integrity status that policy may warn about or block even when already locked.
_Avoid_: Yanked package release, expired signing key, tombstone

**Package tombstone**:
A durable record that a previously published Package release ID is exceptionally unavailable. It preserves the name, version, and audit history so the identity cannot be reused.
_Avoid_: Yank, ordinary package deletion, missing mirror

**Release channel**:
A named, mutable policy that selects eligible package, tool, or extension versions for updates.
_Avoid_: Package identity, exact version, registry index
