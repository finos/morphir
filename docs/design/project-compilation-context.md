---
title: Project compilation context
sidebar_label: Project compilation context
---

# Project compilation context

A compilation produces one Morphir package from a set of source documents. A
workspace can contain several projects; each selected project contributes its
own package, source root, module exposure, and compile task result. Multiple
modules in one package do not imply cross-package dependency compilation.

## Configuration and command-line precedence

Select the project before applying command-line overrides. Configuration keeps
its existing layer order: defaults, system, global user, workspace, selected
member, adjacent user overrides, environment. Explicit command-line values win
over the corresponding effective settings.

`--project` accepts an exact project name or a declared workspace-relative
member path. `.` selects a project declared at the workspace root. Unknown or
ambiguous names are errors. An explicit selection also works when invoked from
a sibling member. Without it, configuration discovery selects the current
member, then the configured default member or sole member. A workspace without
an unambiguous project requires a selection.

| Input | Resolution |
| --- | --- |
| `--config` | Selects the configuration entry point; it does not change the working directory. |
| `--project` | Selects the member before configuration merging. |
| `project.source_directory` | Relative to the selected project root. |
| `--input` | Replaces the configured source input; relative to the invocation directory. |
| `--package-name` | Replaces the emitted package name; does not relocate project output. |
| `--language` | Replaces the configured frontend language. |
| `--ir-version` | Replaces `ir.format_version` for project compilation; v4 is the default. |
| `--out-dir` | Overrides `MORPHIR_OUT_DIR`, then `workspace.out_dir`, then the default `.morphir/out`. |
| `--output` | Installs a copy of the task product at the supplied location. |

Scalar options replace their corresponding settings. They do not append paths
or implicitly select another project. TOML and YAML represent the same nested
configuration model. Legacy `morphir.json` continues to normalize `name`,
`sourceDirectory`, and `exposedModules` into that model.
An omitted project version defaults to `0.1.0`, as in legacy normalization;
opening a discovered project does not require adding a version just to read its model.

The existing single-file Elm route is an isolated compilation: it synthesizes
exposure for the one submitted module. A surrounding project's exposure list
does not add unsubmitted modules to that request. Project-mode compilation,
including Python, forwards the configured exposure list for its complete source set.

Project compilation requests the selected IR version when resolving and invoking
the frontend. A provider must advertise that version, and both its result and
embedded document header must match the request. V3 supports JSON/YAML single-file
storage; v4 also supports document trees. Task records retain the emitted version,
so generation and workspace model loading read the correct transport. The isolated
single-file Elm route remains v3-only and rejects an explicit v4 override.

## Source identity across MEP hosts

`CompileRequest.sources` is the complete compilation unit. Its `documents`
field supplies document contents; resolving an identity does not authorize
filesystem or network access. `sources.root` is the standard optional MEP
source root, shared by CLI and UI callers, with these rules:

- Use an absolute hierarchical URI for the source root. Absolute native paths
  remain accepted for compatibility; hosts should emit file URIs for local files.
- Relative document paths retain their directory segments.
- Absolute document URIs must be beneath the source root, with matching URI
  scheme and authority. Root matching respects path-segment boundaries.
- Multiple documents containing any absolute URI require a source root. A
  single absolute document without a root retains basename identity for
  compatibility with existing single-document callers.
- Query strings and fragments are diagnostic metadata, not module identity.
  Decode path segments once. Reject dot segments, encoded separators, invalid
  UTF-8, empty file paths, outside-root paths, and duplicate document identities.
- Preserve the original URI in diagnostics. Frontends map validated relative
  source paths to language-specific module names and reject name collisions.

The Rust SDK owns validation through `CompileRequest::source_paths()` and the
validated `SourceRoot` and `SourcePath` types. Keeping the root in the same
`SourceSet` as its documents prevents document replacement or combination from
silently changing module identities. Python derives `domain/models.py` as
`domain.models`; a nested `__init__.py` represents its package module according
to the Python frontend's documented rules.

One root per compilation gives stable module identity across local paths,
editor documents, and generated source round trips. Computing a common ancestor
would make module names change when documents are added or removed. Explicit
per-document module IDs or several source roots would need additional collision
and import-resolution rules; neither is inferred by this contract.

## Public and private modules

`package.exposedModules` is optional. Omission exposes every compiled module for
ad hoc callers. An explicit empty array exposes none. A nonempty array names
exactly the public modules; all other compiled modules are private. Unknown
module names are errors. Configuration forwards its exposure list without
replacing it with an empty array.

Private modules remain in the package definition and may be referenced by
sibling modules. They are excluded from its public module specification. Python
generation emits both public and private modules so internal references remain
usable. Python does not enforce Morphir access control at runtime: retain the
exposure configuration when recompiling generated files. Module access does
not imply support for private types, values, or constructors.

The SDK's Rust field becomes `Option<Vec<String>>`. Existing callers that
intended an empty public interface must send `Some(vec![])`; callers intending
all modules public use `None`. This is an API change within the current 0.x
SDK. Older Python releases reject partial exposure; use an extension build
containing private-module support.

## Loading the compile result

Connected workspace providers resolve the selected project's output using the
same configuration and out-root precedence as the CLI. They read
`<out>/<member>/compile.json` and the IR descriptor inside `compile.dest`,
including JSON/YAML single files and document trees. The task record carries
the artifact's format, layout, and version; current configuration does not
reinterpret an earlier successful artifact.

A present invalid or tombstoned record is an error. Only an absent record permits
the legacy `<project>/morphir-ir.json` fallback. Readers hold the compile task's
shared lock while reading its record and artifact. Artifact paths stay confined
to their granted output directory; record paths cannot grant new access.
Document trees are reconstructed as a single IR value for the existing UI RPC.

This contract covers connected CLI workspace providers. Browser-local workspace
loading requires a corresponding browser implementation and an explicit handle
grant if the configured output lies outside the opened directory.
