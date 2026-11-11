---
title: Toolchain schema family and portable extension selection
sidebar_label: Current-family candidate
---

This is a candidate contract, not an implemented manager feature. The existing
`0.1.0-draft.1` corpus remains unchanged and executable through its existing pinned
.NET runner. The new family follows Decision 15A. Its documents use
`0.1.0-preview.1` schema URLs under `/schemas/toolchains/0.1.0-preview.1/`.
This is a contract version, not a choice of CLI release version.

The maintainer approved project/workspace pins, the generation overlay and their
selection behavior on 11 November 2026. This page supplies the candidate document
boundary. Behavioral adoption, a complete new-family corpus, independent review
and website verification must finish before these files become a supported
production input. Schema validation alone does not establish those gates.

## One family, with historical documents preserved

| Document | Schema file | Purpose |
| --- | --- | --- |
| Toolset recipe | `recipe.schema.json` | Authenticated host/provider choices |
| Project request | `request.schema.json` | The requested host, deployment and toolset |
| Portable lock | `lock.schema.json` | Exact selected artifacts and platform closures |
| Local receipt | `receipt.schema.json` | Machine-local launch and installation facts |
| Manager result | `result.schema.json` | Plan/result observations and diagnostics |
| Fixed workflow | `workflow-case.schema.json` | Runner-neutral source, IR and generated-file expectations |
| Extension selection | `selection.schema.json` | Portable project/workspace pins and generation overlays |

Each file has the same family version. A JSON document has a required `$schema`
member, written first, with its exact schema URL. A TOML request instead starts
with this directive and has no version member in its body:

```toml
#:schema https://morphir.finos.org/schemas/toolchains/0.1.0-preview.1/request.schema.json
[host]
implementation = "dotnet"
deployment = "native-aot"
channel = "stable"
[toolset]
preset = "fsharp"
```

The TOML reader must check that directive before interpreting the body. The JSON
Schema validates the parsed TOML body; it cannot verify comments. There is no
`schemaVersion` member and no automatic conversion from draft.1. A reader lists
the exact URLs it accepts and refuses any other prerelease. Historical schemas,
signed metadata and fixture bytes retain their existing identities.

The candidate recipe and lock schemas reference the published extension id
grammar, including its 238-character total limit and first-segment device rule.
They do not impose the historical 64-character segment limit. The extension
family, MEP, IR and tool release metadata retain their own version authorities.
The candidate result's embedded lock uses the same new-family lock schema.

## Authenticated recipe targets

A preview recipe is read only after the existing TUF client has authenticated
the target record and verified the target's exact byte length and digest. Its
`custom.morphir` object uses the following candidate projection. This projection
does not change the outer tool-release-metadata-v1 profile or its role envelopes.

| Member | Required | Meaning |
| --- | --- | --- |
| `$schema` | Yes | The exact preview `recipe.schema.json` URL, identifying the target payload contract |
| `kind` | Yes | Exactly `toolset-recipe`, distinct from a v1 tool release or artifact |
| `preset` | Yes | The selected recipe preset, equal to the verified payload's `preset` |
| `version` | Yes | Canonical SemVer, equal to the verified payload's exact `version` |
| `channels` | Yes | Nonempty channel labels used for recipe discovery |
| `status` | Yes | `active` or `revoked`; a learned revocation prevents recipe use |

The `$schema` value identifies the target payload; it is not a claim that the
custom projection itself validates as a whole recipe document. No
`schemaVersion` member replaces or accompanies it in this preview projection.
Existing v1 tool-release target metadata and release descriptors keep their
numeric v1 identity. Historical draft.1 recipe metadata keeps its own version
member and fixed signatures. Readers do not convert either representation into
the other, infer a schema from a filename, or retry a historical codec after a
preview refusal.

After verifying target bytes, read the payload through the exact-schema recipe
reader and compare preset/version against the authenticated projection. Refuse
disagreement before resolving, downloading or executing any host or provider.
Channel discovery uses only accepted current metadata. Once a later trusted
refresh marks the recipe revoked, the same previously accepted recipe digest
does not authorize a new resolution or launch contrary to the existing learned
revocation policy. Durable trust handoff remains an implementation prerequisite.

The [signed candidate inputs](./corpus/signed/README.md) supply an independent
TEST-ONLY repository and fixed positive/refusal expectations. Parent schema and
integrity checks are not trust or behavioral qualification. This projection
requires independent review and shared-runner adoption before production use.

## A portable extension selection

A project or workspace uses `.morphir/extensions/selection.json`. A manager
generation uses `extensions/selection.json` below its immutable generation
directory. The host consumes the same document in all three locations:

```json
{
  "$schema": "https://morphir.finos.org/schemas/toolchains/0.1.0-preview.1/selection.schema.json",
  "extensions": [
    {
      "extensionId": "org.finos.morphir.fsharp-frontend",
      "version": "0.6.0",
      "runtime": "process",
      "platforms": {
        "win-x64": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
        "osx-arm64": "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
      }
    }
  ]
}
```

These illustrative digests do not name a published F# release. The fixed cases
use them as identities; the acquired-artifact journey must use actual verified
release bytes.

### Members

| Member | Required | Meaning |
| --- | --- | --- |
| `$schema` | Yes | The exact `selection.schema.json` URL above |
| `critical` | No | Unique understood member paths; an unknown critical path is refused |
| `extensions` | Yes | Pins in increasing ordinal extension-id order, at most one per identity; empty is valid |
| `extensions[].extensionId` | Yes | The published extension-family id grammar |
| `extensions[].version` | Yes | An exact canonical SemVer, compared as exact identity including build metadata |
| `extensions[].runtime` | Yes | `process` or `wasm`; no inferred/default runtime |
| `extensions[].platforms` | Process only | A nonempty platform-to-SHA-256 map, with no portable `sha256` member |
| `extensions[].sha256` | WASM only | One portable SHA-256, with no `platforms` member |
| `extensions[].critical` | No | Unique understood paths within that pin |

Digests are 64 lowercase hexadecimal characters over the exact installed
artifact identity. The selected inventory record must agree on id, version,
runtime and digest. For a multi-file process package this means its recorded
package artifact digest; installation separately verifies the complete file
inventory and tree as the extension package contract requires. Selection does
not replace package verification, the shared catalog/lock, or runtime leases.

No selection document stores a local launch path, Morphir Home, credentials,
repository password or machine-specific directory. Unknown optional members
are ignored unless listed as critical, but credential scanning still applies
throughout the document. JSON duplicate members, duplicate ids, unsorted pins,
unsupported schema URLs and invalid critical lists are reader refusals.
JSON Schema expresses only part of these rules. In particular, differently
valued pins with the same id can satisfy the schema while the reader refuses
them.

## Selection and launch

For each requested extension identity, the first layer containing that id wins:

1. The read-only generation overlay selected by `MORPHIR_EXTENSION_OVERLAY`.
2. The project pin.
3. The workspace pin.
4. The shared catalog and its extension lock.
5. The system pin.

A selected but broken pin stops selection. Missing platform content, absent
inventory objects, digest disagreement or unsupported runtime never permits
fallback to a lower layer. Selection does not download, refresh repositories,
install content or rewrite a pin. The report names the winning source. Isolation
omits the shared catalog and system pin while preserving the higher layers.

The proxy supplies an absolute generation directory in
`MORPHIR_EXTENSION_OVERLAY`. A relative, missing or unreadable explicit overlay
is a refusal. The host reads `extensions/selection.json` within that directory
and never writes to it. The manager publishes a complete immutable generation
before changing the active pointer; an in-flight run retains its generation
lease. This environment variable does not authorize arbitrary file writes or
an implicit installation.

Project/workspace pin updates take a manager lock in Morphir Home keyed by the
canonical destination path. An effectful update and its dry run share one plan;
the dry run changes no selection, inventory, journal, store or activation
pointer. Catalog and lock files remain in their published extension-family
formats. A normalized layer in a test case is not a new catalog file format.

Configuration names an installed frontend with `extension_id` and an installed
extension table with `id`. Existing string path configuration keeps its path
meaning. Both configured identities and command selection use this same
pipeline.

An extension table key remains its extension identity, including the existing
quoted-key rule for dotted ids. Its explicit `id` must match that key exactly;
the table key is not an alias. For example:

```toml
[extensions."acme.installed"]
id = "acme.installed"
```

In that table, `id` cannot occur with `path`, `url` or `command`, even when a
value is empty or appears to name the same artifact. Refuse conflicting sources
before inventory resolution, installation or launch. A table without `id`
retains its existing launch-source semantics. This adds `id` as a recognized
string setting; it does not reinterpret an existing path or command as an id.

Similarly, `[frontend.<language>]` may use either `extension_id` for an installed
identity or the existing `extension` string for a command/path, never both.
The language key is a language id, so it need not match the selected extension
id. An explicit identity must pass the extension id grammar in either setting.
The fixed configuration cases specify these refusals independently of TOML
whitespace or JSON member order.

## Unsigned local content

Explicit local-source installation or an explicit staged-mode choice supplies
developer consent. An omitted setting inheriting `auto` does not. Discovery can
report such a candidate without installing or probing it. Global staged/file
installation records a generated one-release local repository and labels it
`local-developer`; neither fact authenticates a publisher. Selection of an
existing pin is not fresh consent to install missing content.

## Fixed cases and unfinished gates

[selection-cases.json](./selection-cases.json) separates wire documents from
test-only normalized layer/inventory inputs. `read-selection` exercises document
reading, `select` exercises precedence and local binding, and `overlay-root`
exercises explicit overlay validation. Expected refusals without a diagnostic
code are structural-contract expectations; command diagnostic mapping must
retain the approved `extension.*` vocabulary when adoption lands.
`read-provider-configuration` reads the supplied TOML and exercises the explicit
identity, legacy source and conflicting-source rules above. Those inputs are
project configuration, not selection JSON documents.

Parent tests validate schema structure, schema-expressible examples and manifest
integrity. They do not execute selection. The shared .NET runner must execute
every declared operation and reject unknown or unrun cases. Until it does, the
new corpus is not behavioral qualification. New-family request/lock/receipt,
signed recipe and workflow inputs are distinct from the historical corpus;
historical bytes are not relabeled as new evidence. The [preview reader inputs](./corpus/README.md)
now provide 37 fixed document cases across all seven family documents, including
a version-specific workflow manifest that references the existing frozen
resources. Their integrity and schema results do not establish .NET reader or
workflow execution. The selection inputs include isolated optional/critical
controls, portable WASM and empty positives, and duplicate/order/credential
counterexamples that JSON Schema alone cannot refuse. A separate signed TEST-ONLY recipe fixture supplies six
authentication expectations and complete inert target records. Its actual
signature verification, semantic target binding and the remaining cutover gates
are still pending.

Eight additional [authenticated binding inputs](./corpus/signed/README.md#authenticated-binding-cases)
retain that repository's original authority and supply separately signed,
schema-valid variants. They pin a full positive closure and first refusals for
host identity/platform and provider repository/digest/protocol/model
disagreement. Their byte/schema integrity is checked here; actual authentication
and binding outcomes remain unrun through the shared .NET checker.
