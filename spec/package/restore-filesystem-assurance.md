# Restore filesystem assurance

Status: design approved on 2026-09-17. Portable restore on Linux, macOS and Windows is
the first-delivery target; hardened providers follow separately. Neither mode is an
implemented or qualified platform capability yet.

This addendum separates package authentication from protection against a hostile local
filesystem. It applies to consumption of published Libraries from local-directory
registries. It does not relax publication, introduce remote sources or archives, or
change the artifact contracts for executable extensions and installable tools.

## Modes and threat boundary

`portable` mode assumes caller-controlled local registry, cache, staging, destination
and security-state directories. The caller trusts their local ownership, permissions
and filesystem administration. Untrusted processes must not be able to change these
directories or their ancestors during restore. Package contents remain untrusted.
Cooperating Morphir processes must still serialize writes and security-state changes.
An actively published registry must coordinate with readers or supply an immutable view;
portable mode does not make a racing publication safe.

`hardened` mode additionally provides the original local Library contract's anchored,
no-follow traversal and special-file protections under hostile source-entry replacement.
It does not protect against an administrator replacing the kernel, tampering with
protected security state, or defeating the filesystem's own guarantees.

| Requirement | Portable | Hardened |
| --- | --- | --- |
| TUF workflow, publisher signatures, namespace policy and revocations | Required unchanged | Required unchanged |
| Exact lock replay, content digests, IR and dependency checks | Required unchanged | Required unchanged |
| Input bounds, path grammar and exact inventory | Required unchanged | Required unchanged |
| Reject detected symlinks, reparse points, hardlinks and special files | Required | Required |
| Resistance to hostile concurrent path or file-type substitution | Outside the trusted-local-filesystem assumption | Required by the original contract |
| Private staging and verification of the bytes consumers receive | Required unchanged | Required unchanged |
| Writer exclusion, no overwrite of an existing completed bundle, atomic visibility | Required | Required |
| Durable trust transitions, recovery, rollback floors and continued-use grants | Required unchanged | Required unchanged |

The portable relaxation is limited to race-resistant acquisition and confinement.
It is not permission to follow known links, accept unsafe paths, ignore observed changes,
read a known device or block on a known FIFO. Check entries before opening, inspect the
opened object where supported, and reject any detected type, identity or inventory change.
The provider must document residual check/open races. These checks do not prove resistance
to an attacker who can change local entries concurrently.

Portable restore is unsuitable for directories writable by untrusted local principals,
uncoordinated shared writers or package-controlled hooks. No restore mode executes such
hooks. A signature authenticates bytes; it cannot make an unsafe filesystem access safe.

## Selection and failure behavior

The trusted caller selects the mode before package access. A project configuration counts
as caller policy only when the host explicitly trusts it; package metadata, registry
contents and `morphir.lock` cannot lower the mode. Selecting `portable` is explicit consent
to its local-filesystem assumption. The existing draft.3 execution contract retains its
stronger requirements when no separately identified portable execution profile is selected.

An implementation must report the selected mode and qualified provider environment in
operation context and MCK evidence. Reports must not infer hardened support from an OS
name, a successful restore or a set of passing portable tests.

If the requested mode is unavailable, fail before package access. Never catch a hardened
capability failure and retry in portable mode automatically. Authentication, corruption,
observed mutation, lock failure, failed flush or failed state commit must never trigger
a mode downgrade. A caller may start a new portable operation explicitly; it must first
reconcile any durable in-flight security update under the unchanged recovery rules.

## Persistence is not a reduced guarantee

Both modes preserve the [trust profile](package-trust-profile.md#durable-local-security-state).
Trusted roots, rollback floors, known revocations, in-flight markers and grants remain
outside the lock and ordinary cache. Missing or corrupt established state fails closed.
Disabling offline use does not make lost rollback floors safe.

A provider must establish durable, serialized trust-state transactions on its supported
OS/filesystem combination. The private storage format remains implementation-defined;
equivalent transactional storage may satisfy the contract without reproducing a particular
directory layout. No-op flushes, ignored persistence errors and default-on-missing state
are not alternatives. File/directory promotion and cache recovery also need evidence for
their required guarantees. Portable mode does not waive these requirements.

## Contract and MCK separation

The package artifact formats remain unchanged: `morphir.lock`, registry records, statements,
release identity, digests and the three draft.3 lock capabilities retain their meanings.
Filesystem assurance is a host execution choice, not another package identity or trust
grant. Release versions remain outside IR Package names and FQNames.

Portable execution needs an explicitly identified, versioned execution/report profile in
the shared TypeScript MCK. Its transport and report schema must land before exposing a
public portable adapter. Do not add fields to closed existing messages or treat an
unqualified `graph-ready` response as a portable compatibility result.

The existing 54 draft.3 cases keep their original requirements and fixed expectations.
Their full admission continues to fail while required assets are pending. A portable
corpus must declare its own complete required-case set and provenance, reusing common
fixed assets without relabeling the existing full suite. Excluding hardened-only cases
is a profile definition, not a runtime skip or a passing hardened test.

Required portable evidence includes:

- Explicit selection, rejection of unknown modes, and refusal of automatic downgrade.
- All applicable authentication, replay, bounds and complete staged-byte checks.
- Rejection of static links, devices, FIFOs, unsafe paths and detected source changes.
- Cooperative concurrent restores, process-held exclusion and no overwritten winner.
- Crash/restart and injected write/flush failures for roots, floors, revocations, markers
  and grants, including state loss. An exception-only test is not restart evidence.
- Mode/provider identity in reports, plus refusal of a hardened request on a
  portable-only provider before reading package data.

Hardened evidence additionally covers deterministic hostile path/type substitution and
retained-root confinement. MCK must not count a skipped required case as compatible in
either mode. The parent owns cases and fixed results; finos/morphir-typescript owns their
execution, comparison and reporting. Independent implementations reuse that shared core.

## Delivery gate

Qualify portable restore independently on Linux, macOS and Windows local filesystems.
Record the provider version, runtime, OS, architecture and filesystem assumptions.
First delivery is incomplete if one target lacks its required evidence. Network filesystems
and hostile shared-directory use are not implied by a desktop OS support claim.

The portable mode does not require Seatbelt or a `nodev` volume. Those remain possible
hardened-provider choices, not prerequisites for ordinary consumption. Selecting this
design does not qualify Node filesystem calls, a Rust helper or any particular backend.
Provider packaging and trust-state durability still require implementation and review.

See the [accepted decision](../../kb/bundles/morphir/morphir-package-system/decisions/0002-portable-restore-with-explicit-filesystem-assurance.md)
for the rationale and rejected alternatives.
