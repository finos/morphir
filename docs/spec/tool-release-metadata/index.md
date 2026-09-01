---
title: Tool release metadata v1
sidebar_label: Version 1 profile
status: draft
tracking:
  beads: [morphir-ds9e.1]
---

# Tool release metadata v1

This specification defines how Morphir authenticates, discovers, selects, and locks tool releases. It profiles [The Update Framework 1.0.36](https://theupdateframework.github.io/specification/v1.0.36/) and adds Morphir fields to signed target metadata. TUF remains authoritative for signature verification, root rotation, metadata versioning, expiry, rollback protection, and target hash verification.

The profile applies to tools such as Morphir Desktop. Extensions may reuse the trust and transport machinery, but their release descriptors remain a separate schema.

## Trust boundary

A tool repository is one logical source governed by one trusted repository root. A repository can have several mirrors. Mirror URLs choose where bytes come from and do not change what the client trusts.

The CLI receives its first trusted root through an out-of-band path:

- the official Morphir root is embedded in a CLI release;
- an administrator may provision another root with global configuration;
- a user may explicitly import a root file after inspecting its repository identity.

The repository identity is the lowercase SHA-256 digest of the canonical JSON encoding of the initial root's `signed` object. Root signatures do not affect identity because they can be added or reordered without changing the trusted keys and roles. Moving between mirrors preserves this identity. Replacing the initial root changes the repository identity and requires explicit trust bootstrap.

Trusted root state is durable security data beneath Morphir Home. Cached timestamp, snapshot, targets, release descriptors, and artifact bytes are disposable copies. Cache cleanup must never remove the current trusted root or the installed inventory's exact release locks.

## TUF profile

Metadata follows TUF 1.0 JSON with these constraints:

| Concern | Version 1 rule |
| --- | --- |
| TUF version | `spec_version` must be compatible with `1.0`. The conformance fixture uses `1.0.36`. |
| Encoding | UTF-8 JSON. Signed objects use TUF canonical JSON for signature verification. Floating-point values are forbidden. |
| Keys | Ed25519. An implementation may add a TUF-defined scheme only after adding conformance fixtures. |
| Target hashes | SHA-256 is required. Other TUF hashes may accompany it. |
| Snapshots | `consistent_snapshot` must be `true`. |
| Root threshold | The official production repository uses at least two trusted root signatures. Test and explicitly configured development repositories may use one. |
| Targets threshold | At least one targets signature. The official version 1 repository treats the top-level targets role as its publisher authority. |
| Delegations | Version 1 does not assign Morphir semantics to delegated role names. A conforming TUF client may process standard delegations when repository policy enables them. |

Clients apply bounded download limits before parsing metadata. The initial limits are 64 KiB for each root or timestamp file, 1 MiB for a snapshot, 8 MiB for targets metadata, and 1 MiB for a release descriptor. A trusted target's declared length limits every artifact download.

### Root rotation

The client persists the newest trusted root. Starting at trusted version `N`, it requests only `N + 1`, then continues one version at a time. Each new root must:

1. have version `N + 1`;
2. satisfy the old root role threshold;
3. satisfy its own new root role threshold;
4. pass the remaining TUF root checks.

The client stops after 32 accepted roots in one refresh and asks the user to retry. This bounds one operation without changing trust. A repository must retain every numbered root so an old client can follow the complete chain.

If a threshold of trusted root keys is compromised, ordinary online rotation cannot restore trust. Recovery requires a new root delivered out of band.

### Freshness and rollback

One refresh uses a fixed trusted start time for every expiry check. The client rejects expired timestamp, snapshot, targets, and delegated targets metadata. It also applies TUF version and hash checks so a mirror cannot replay an older snapshot or mix metadata versions.

Recommended maximum publication lifetimes for the official repository are:

| Role | Maximum lifetime |
| --- | --- |
| Timestamp | 24 hours |
| Snapshot | 7 days |
| Targets | 30 days |
| Root | 366 days |

These are publisher limits. A client still trusts the exact signed `expires` value when it is shorter.

## Repository layout

Logical target paths use forward slashes and normalized lowercase identity segments:

```text
releases/<tool-id>/<exact-version>.json
artifacts/<tool-id>/<exact-version>/<platform-archive>
```

Target paths are relative, contain no empty, `.` or `..` segment, and never contain a backslash or drive prefix. TUF consistent-snapshot rules determine the physical URL used to retrieve a target.

Each release descriptor target has a `custom.morphir` object:

```json
{
  "schemaVersion": 1,
  "kind": "tool-release",
  "toolId": "desktop",
  "version": "1.0.0",
  "channels": ["stable"],
  "status": "active",
  "compatibility": {
    "morphirCli": ">=0.4.0-alpha.5, <0.5.0"
  },
  "platforms": [
    { "os": "windows", "arch": "x86_64" }
  ]
}
```

This small record is enough to resolve a release before downloading its descriptor. Its channel membership and status are the current authenticated release state and are authoritative for resolution and revocation. The descriptor repeats the identity, version, compatibility, and immutable artifact contract. A mismatch in those immutable values is `release_descriptor_mismatch`.

Version 1 descriptors also carry `channels` and `status`. Those fields record the state at initial publication. Clients validate their shape but do not compare them with current targets metadata or use them for selection. This keeps the descriptor bytes immutable when a publisher moves a release between channels, yanks it, or revokes it.

An artifact target uses `kind: "tool-artifact"` and records its tool, version, and platform in the same namespace. The release descriptor references artifact target paths. Length and hashes come only from authenticated TUF target metadata, even if another publication format repeats them.

The release descriptor schema is published as [tool-release-v1.schema.json](/schemas/tool-release-v1.schema.json).

## Release states

| Status | Moving channel | Exact selection | Already installed |
| --- | --- | --- | --- |
| `active` | Eligible | Eligible | Launches normally |
| `yanked` | Excluded | Eligible | Launches normally |
| `revoked` | Excluded | Rejected | Launch is rejected after the revocation is learned and persisted |

Revocation is monotonic for a repository metadata history. A later targets version must not return the same tool version to `active` or `yanked`. Republishing different bytes under an existing tool version is forbidden. A corrected build receives a new semantic version.

Publishers change channel membership and release status only in a later signed targets version. A `yanked` or `revoked` release has no channel memberships in current targets metadata.

When a refresh learns that an installed release is revoked, the inventory records the trusted targets version and revocation reason before reporting the failure. Offline launch then enforces the known revocation without consulting a mirror.

## Channel and exact-version resolution

The request is either one exact semantic version or one channel. The installed lock retains the original request spelling and the exact selected result.

Metadata recognizes these channel names:

- `stable`
- `preview`
- `insiders`
- `preview/<segment>`, where the segment is a lowercase portable token

`insiders` and the unsegmented `preview` request select the same preview family. Publishers should use `preview` in new metadata. Keeping the requested `insiders` spelling in the lock preserves user intent.

A resolver performs these steps without network or filesystem effects:

1. Authenticate and freshness-check the complete TUF metadata set.
2. Keep release records for the requested tool with a matching CLI requirement and platform.
3. Exclude revoked releases. Exclude yanked releases for moving channels.
4. For `stable`, keep only final semantic versions that name `stable`.
5. For `preview` or `insiders`, keep releases naming `preview`, `insiders`, or any `preview/<segment>`.
6. For a segmented preview, keep only the exact segment.
7. Select the greatest semantic-version precedence.

An exact request ignores channel membership and may select a prerelease or yanked release. It still enforces the current authenticated status, CLI compatibility, platform availability, and immutable descriptor consistency.

One repository cannot contain two records with the same exact version. It also cannot contain versions with equal semantic precedence but different build metadata. Both would make the selected record depend on document order.

## Mirrors

Mirror order belongs to effective user or administrator configuration. The client tries mirrors in order for each metadata or target path. It verifies every response with the same trusted root, metadata links, declared length, and hashes.

A mirror failure can cause a retry at another mirror. A signature, rollback, expiry, length, or hash failure emits a repository integrity event before any retry. A successful retry must still produce the one metadata version and target digest selected by the trusted update workflow.

Proxy, TLS, timeout, and authentication behavior belongs to transport configuration. HTTPS is required for public mirrors, but TLS never replaces TUF authentication.

## Offline and expired metadata

| Operation | Offline behavior |
| --- | --- |
| Launch an installed active release | Use the installed inventory lock and reverify installed bytes. Do not read repository metadata. |
| Repair an installed release | Use a verified content-addressed object when present. Otherwise report that network access is required. |
| Resolve a moving channel | Use cached metadata only when the complete set is unexpired. |
| Install an exact release not already locked | Require unexpired cached metadata and cached verified target bytes. |
| Refresh metadata | Fail immediately because `--offline` forbids mirror access. |

Expired repository metadata never invalidates an otherwise valid installed release. It prevents a new resolution. Known revocation state remains durable and continues to block launch.

A failed online refresh leaves the previous trusted metadata and active installed release unchanged. The error reports the repository identity, mirror, metadata role, stable diagnostic code, operation ID, and log path.

## Stable diagnostics

Implementations use these codes at the public boundary:

- `metadata_signature_invalid`
- `metadata_expired`
- `metadata_rollback`
- `metadata_link_mismatch`
- `metadata_root_rotation_invalid`
- `target_length_mismatch`
- `target_digest_mismatch`
- `release_descriptor_mismatch`
- `release_revoked`
- `no_compatible_release`
- `offline_metadata_unavailable`

More detail may appear in structured fields and logs. The code remains stable across TUF library changes.

## Conformance fixture

The [version 1 fixture](./fixtures/v1/conformance.json) contains deterministic test-only Ed25519 keys and signed metadata. It proves:

- a two-of-three trusted root and a dual-threshold root rotation;
- timestamp, snapshot, targets, release descriptor, and artifact authentication;
- expiry and tamper rejection;
- active and revoked release handling;
- deterministic stable, preview, insiders, segmented preview, and exact selection;
- CLI and platform compatibility filtering;
- repository identity that remains unchanged across two mirrors.

The keys and payloads are fixtures. They must never be used by a deployed repository.
