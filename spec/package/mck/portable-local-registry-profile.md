# Portable Local Library required inventory

The execution profile is `local-library-portable`, version `0.1.0-draft.1`, over
artifact contract `0.1.0-draft.3`. Host consent uses the separate assurance contract
`restore-filesystem-assurance/0.1.0-draft.1`.

[`portable-local-registry-cases.json`](portable-local-registry-cases.json) is a
**definition-planning inventory**. It records required work, not executable
coverage. All 296 entries have pending executable definitions. There is no public
portable adapter, executable kit hash, passing portable report or provider
qualification in this slice. The schema intentionally has no bound-definition,
content-hash or pass-result branch. Inspection cannot promote this inventory to
an executable kit.

## Source derivations

The inventory retains 46 consumption cases from the original 54 definitions:
13 wire, 20 trust, four replay, three recovery, two bounds and four filesystem.
Each source derivation names its original case and its new stable
`portable-local-registry.<family>.<case>` ID. The shared Rust engine checks the
original corpus with its existing schema and semantic validator before checking
the derivations. The original index, publication definitions and fixture bytes
remain unchanged.

The derivation recipe has the following exact meaning:

- `removeSetup` lists only the original registry `publisher` initialization
  fields. The consumer still explicitly initializes its protected security state.
- `removeObservations` removes only `/registries/*/reserved`. Here `*` means each
  array member of the complete registry observation list. Keep each registry's
  identity and timestamp observation. Keep complete security, filesystem, input
  lock byte and graph-readiness observations.
- `operations: unchanged` preserves original operation order, inputs, expected
  results, action schedule, observation time and policies. All original applicable
  operation expectations and observation assertions remain required. No publisher
  policy, publisher signature or publisher authorization check is removed.
- `consumptionObservations: complete` requires a new complete publisher-free
  observation asset. It is pending even if the original snapshot was bound.
  Parse cases have no setup or observation projection.

These recipes are a precise plan for new definitions. They are not executable
scenario bodies and do not bind a portable protocol. An executable implementation
must materialize and validate those derived definitions, bind all assets and
complete observations, and freeze the expectations independently of the testee.

The original 46-case source closure has 90 assets: six bound and 84 pending.
These are source-planning counts. In particular, the bound original observation
asset still contains publisher reservations and is not a bound portable
observation. New obligations, protocol changes and transitive assets will change
the final portable closure. The whole original corpus remains 54 definitions,
six bound assets and 121 pending assets.

The six publication cases remain outside this consumption profile. The original
`filesystem.special-file` and `filesystem.case-collision` cases remain intact
and are replaced in the portable inventory by the native environment obligations
below. This changes fixture applicability, not the required rejection behavior.

## Required environment membership

`requiredGroups` explicitly enumerates every case ID, with one group per case.
Each case also declares its group so inspection can detect missing, unknown,
duplicate and misplaced memberships. `environments` names the exact required
group union for each declared OS, architecture, filesystem and case behavior.
There are 287 common obligations, two POSIX obligations, three Windows
obligations, one case-sensitive obligation and three case-insensitive obligations.

| Required environment | Required groups | Required cases |
| --- | --- | --- |
| Linux/ext4, x86-64 and aarch64, case-sensitive | common, posix, case-sensitive | 290 each |
| macOS/APFS, x86-64 and aarch64, case-sensitive | common, posix, case-sensitive | 290 each |
| macOS/APFS, x86-64 and aarch64, case-insensitive | common, posix, case-insensitive | 292 each |
| Windows/NTFS, x86-64 and aarch64, case-insensitive | common, windows, case-insensitive | 293 each |

These eight declarations cover filesystem variants across the six shipped OS and
architecture targets. They are required qualification work, not evidence that
an environment is supported. Inspection rejects mismatched environment
identities and reduced membership lists. Runtime qualification must additionally
bind source/build identity, runtime, detected filesystem, assumptions and evidence
digests to the exact immutable provider artifact. A declaration or user-authored
receipt supplies no such authority. An undeclared filesystem variant requires an
explicit inventory and provider-design revision before qualification.

POSIX obligations use real FIFO and device entries and must reject them without
opening them. Windows obligations use real junctions, reparse entries and
nonregular objects. Case-sensitive filesystems require two real colliding names.
Case-insensitive filesystems require exact spelling, collision-input rejection
and native enumeration. Failure to create a required fixture is an infrastructure
failure. It cannot produce a skip or a synthetic pass.

## Additional obligations

Each added entry cites its existing package contract and states the behavior to
freeze. The inventory includes host selection, current and historical
authentication, fresh catalog resolve/update, staging and graph verification,
real-process exclusion and recovery, and controller/report checks. Every one of
the 35 named profile resources has separate inclusive-boundary and first-excess
obligations. Local-policy limits, shared-input accounting and overflow have
additional cases.

Recovery obligations include process death, failed writes and failed flushes at
root, reset-context, rollback-floor, accepted-time, revocation, grant,
candidate-marker, marker-clearance and promotion boundaries. These entries still
need exact schedules, fixed inputs and independently frozen expected complete
observations. A passing process-kill test alone cannot qualify power-loss
persistence. Platform/storage evidence remains a separate required gate.

The eventual controller must admit the complete transitive closure before
adapter startup, then compute the executable hash. No required case may be
skipped. The consolidated portable report will use version `2.0.0-draft.2`;
report and controller requirements here are pending definitions, not implemented
report support. Existing package draft.1/draft.2 and IR report formats remain
unchanged.

## Planning inspection

`morphir_mck::package::local_registry::inspect_portable_profile` returns a
`definition-planning-summary`. It checks the offline profile schema, membership,
environment identity, source derivations and source asset closure through the
shared engine. It exposes no executable hash.

There is no portable admission API in this planning slice. Actual admission will
extend the existing `AdmittedKit` path when executable definitions, complete
observations and the transitive fixture closure are bound. It must validate the
selected environment and complete required inventory before adapter startup.

Run `cargo test -p morphir-mck --test package_portable_profile` for profile
mutation checks, and `cargo test -p morphir-mck --test package_local_registry` to
verify the retained original corpus.
