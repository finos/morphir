---
title: CLI-managed Desktop acquisition and launch
sidebar_label: Desktop acquisition and launch
status: review
tracking:
  beads: [morphir-doi4, morphir-ds9e]
  implementation:
    cli: crates/morphir
    distribution: ecosystem/morphir-rust/crates/morphir-distribution
    desktop: https://github.com/finos/morphir-ui/tree/main/apps/morphir-desktop
---

# CLI-managed Desktop acquisition and launch

Morphir users should be able to install the CLI and then run `morphir desktop`. The CLI acquires a compatible Desktop release from the configured channel when needed, activates it safely, and launches it with the same Morphir Home used by the rest of the suite.

This design follows [ADR-0005](../../adr/ADR-0005-cli-managed-desktop.md) and [ADR-0006](../../adr/ADR-0006-local-observability-by-default.md). It generalizes the verified extension acquisition machinery without collapsing tools and extensions into one domain concept.

## Goals

- Give configuration, durable state, installed artifacts, caches, and logs one coordination root.
- Make first-use Desktop acquisition an ordinary part of `morphir desktop`.
- Support stable, preview, insiders, and exact-version selection.
- Preserve a working installed release through failed downloads, verification, extraction, probes, or catalog writes.
- Share integrity, storage, locking, and release-selection code across tools and extensions.
- Keep launch fast and usable offline after installation.
- Correlate CLI acquisition and Desktop launch activity under one user-visible operation ID.
- Keep useful local logs and crash diagnostics while preventing secret disclosure and silent telemetry upload.

## Domain boundaries

| Concept | Purpose | Primary command |
| --- | --- | --- |
| Tool | A user-launched executable or application | `morphir tool` |
| Desktop | The well-known tool `desktop` | `morphir desktop` |
| Extension | A host-launched capability provider | `morphir extension` |
| Morphir package | Reusable modeled logic and types | Package commands and build resolution |

The distribution kernel may share value types and effects across these families. Their manifests, catalogs, lifecycle rules, and user-facing commands remain distinct.

`component` is an architectural umbrella term and is not a CLI installation noun.

## CLI contract

### Launch Desktop

```text
morphir desktop [PATH]
morphir desktop --offline [PATH]
morphir desktop --wait [PATH]
```

`morphir desktop` resolves the active `desktop` tool from the installed tool catalog. If none exists, it installs the default selection and then launches it. Invoking the named application is sufficient consent for this first-use acquisition, so the command reports the download without asking an additional question.

`--offline` prohibits registry and artifact network access. It launches a valid active release or fails with a diagnostic that includes the exact installation command to run when network access is available.

The optional path identifies the workspace or artifact to open. The default is the current directory. The CLI launches Desktop detached by default and returns after successful process creation. `--wait` keeps the CLI in the foreground and returns the Desktop process exit status.

### Manage tools

```text
morphir tool install desktop
morphir tool install desktop --channel preview
morphir tool install desktop --version 0.3.1
morphir tool update desktop
morphir tool update --all
morphir tool repair desktop
morphir tool list
morphir tool uninstall desktop
```

`--channel` and `--version` are mutually exclusive. Installation without either option uses the configured default channel, falling back to `stable`.

Installation records the requested selection and the exact active release. Updating re-resolves the stored selection. An exact selection is pinned and produces a no-op update until the user supplies a new version or channel. Changing channels is explicit:

```text
morphir tool update desktop --channel preview
```

Installing an already installed tool exits successfully when the requested selection is unchanged. A conflicting request tells the user to run `tool update` so repeated setup scripts remain safe without hiding a selection change.

`repair` verifies the active exact release and reinstalls missing or corrupt content from a verified local object or the configured source. It never selects a different release.

The CLI does not expose `tool refresh`. `update`, `repair`, and a future manifest-driven `restore` name the three distinct operations that `refresh` might otherwise obscure.

### Bootstrap a user environment

`morphir setup` is an optional, interactive, and idempotent onboarding workflow. No other command requires it.

Setup:

1. Resolves Morphir Home and verifies that it is writable.
2. Shows the resolved path and existing configuration.
3. Selects a default release channel when one is not configured.
4. Ensures Desktop is installed.
5. Offers recommended extensions without making them part of Desktop.

Non-interactive automation uses the underlying commands. Setup delegates to those operations and owns no separate installation state.

## Selection model

Selection follows this precedence for a first installation:

1. Explicit `--version` or `--channel`.
2. Global user acquisition policy.
3. `stable`.

Project configuration does not silently select a different globally installed Desktop. A future project tool manifest may request local tools through an explicit restore operation, but it does not change the active global Desktop as a side effect of entering a directory.

The catalog records both:

- requested selection, such as `channel stable` or `version 0.3.1`;
- resolved release, including exact version, platform, source provenance, metadata revision, artifact digest, and launch description.

Normal launch uses the resolved release without contacting a registry. Channel movement only takes effect during install or update.

## Morphir Home contract

Morphir Home is always the coordination root, whether it came from `MORPHIR_HOME` or the platform-independent default beneath the user's home directory. Caches do not move to an unrelated OS cache directory when the environment variable is absent.

```text
MORPHIR_HOME/
  morphir.toml
  data/
    desktop/
  config/
    desktop/
  catalog/
    tools.json
    extensions.json
  store/
    tools/sha256/...
    extensions/sha256/...
  locks/
  cache/
    downloads/
    indexes/
    desktop/
  logs/
    cli/
    desktop/
  tmp/
```

The root is one location, not one shared mutable file:

- user-authored policy belongs in configuration;
- durable application state belongs in a namespaced data directory;
- active installation state belongs in versioned catalogs;
- verified immutable content belongs in the content-addressed store;
- disposable content belongs in cache;
- coordination files belong in locks and temporary staging belongs in `tmp`.

Each catalog and owned application file carries its own schema version. Components do not require one global home schema upgrade and must not write files owned by another component. The distribution kernel is the only writer for tool and extension catalogs and stores.

The CLI passes the fully resolved absolute `MORPHIR_HOME` value to Desktop on every launch. This prevents the child process from deriving a different root through environment, symlink, profile, or platform differences.

Desktop config, Electron `userData`, session data, Chromium cache, crash output, and application logs must resolve into their assigned Morphir Home directories before Electron becomes ready. Credentials stored in an operating-system keyring remain OS-managed; Morphir Home contains only the secret reference or encrypted application record required by the selected secret provider.

CLI instrumentation always uses `logs/cli`. It does not switch to a workspace-local directory because the current working directory happens to contain Morphir configuration. Desktop uses `logs/desktop`, including renderer, main-process, child-process, and crash records.

### Global configuration migration

The current loader treats platform configuration directories and `MORPHIR_HOME/morphir.toml` as alternate global-user locations. The canonical location becomes Morphir Home.

During a compatibility period, Morphir may read one legacy platform global-user file when the canonical file is absent and emit a migration diagnostic. If canonical and legacy files both exist, discovery reports the ambiguity rather than merging them. Setup can offer to move the legacy file after showing the exact source and destination.

### Installation state migration

The current metadata-only `tools.json` entries do not prove that a runnable artifact exists. Migration follows these rules:

- A verified catalog entry is an installed tool.
- A legacy entry with no artifact digest and launch description is imported only as historical intent.
- List output labels such an entry as incomplete rather than installed.
- Update or repair may turn the intent into a verified installation.
- Migration never invents a digest, executable path, or exact resolved version.

## Acquisition transaction

One tool installation or update runs under a per-tool interprocess lock:

1. Read and validate the installed catalog.
2. Resolve the requested selection for the current operating system and architecture.
3. Check compatibility with the invoking CLI and supported Desktop launch contract.
4. Acquire metadata and artifact bytes into secure staging beneath Morphir Home.
5. Verify authenticated release metadata, declared size, and content digest.
6. Extract portable archives while rejecting traversal, unsafe links, device files, and platform path collisions.
7. Run the packaged application's non-interactive probe.
8. Atomically publish immutable content into the verified store.
9. Atomically replace the active catalog entry.
10. Retain the previously active release for rollback and later garbage collection.

A failure before step 9 leaves the previous catalog untouched. A failure while replacing the catalog restores or retains the previous complete file. Readers never observe a partially extracted release or partially written catalog.

Uninstall removes active catalog and selection state. Content-addressed bytes may remain until an explicit garbage-collection policy proves that no catalog or running release needs them.

## Storage maintenance

Morphir separates disposable cache cleanup from installed-artifact pruning. A cache entry is re-creatable content under `cache/`. A verified release under `store/` is installed state even when it is not active. `cache clean` never removes verified releases, and `tool prune` never treats an active catalog entry as disposable.

### Manual commands

Users can inspect and clean storage without finding Morphir Home by hand:

```text
morphir cache status [--json]
morphir cache clean [--dry-run] [--all] [--component <NAME>]
morphir tool prune [<NAME>] [--dry-run] [--keep <COUNT>] [--older-than <DURATION>]
```

`cache status` reports bytes and entry counts by owned cache namespace, the applicable policy, the last successful automatic run, and any bytes it cannot classify. `cache clean` applies the configured age and size policy by default. `--all` removes every known disposable entry, but still respects active-operation leases and ownership boundaries. It does not remove logs, crash reports, diagnostic bundles, or durable application data. Those have separate retention rules. `--component` limits cleanup to a registered owner such as `downloads`, `indexes`, `desktop`, or `extensions`.

`tool prune` removes verified releases only when the maintenance engine proves they are unreachable. It protects:

- every active catalog release;
- the configured rollback releases;
- exact versions pinned by durable configuration or selection state;
- releases leased by running CLI, Desktop, or extension processes;
- artifacts referenced by an installation, repair, rollback, or diagnostic-bundle transaction.

The commands print the number of removed and skipped entries, bytes reclaimed, remaining usage, and the policy that made each skip necessary. JSON output carries stable reason codes. A dry run follows the same discovery and protection logic without changing files.

### Automatic cleanup

The CLI and Desktop call the same maintenance engine. Automatic cleanup is enabled by default and runs opportunistically after successful write-heavy operations or during Desktop idle time. A persisted last-run record and an interprocess maintenance lock limit it to once per configured interval across all Morphir processes. A foreground invocation has a small runtime budget. If it reaches that budget, it records a continuation cursor and resumes during a later run.

Morphir does not require an operating-system scheduled task. `morphir cache clean` remains safe to call from cron, Task Scheduler, launchd, or managed workstation tooling. A future `morphir setup` option may install such a schedule only with explicit user or administrator consent.

The initial default policy is:

```toml
[cache.cleanup]
automatic = true
interval = "24h"
max_age = "30d"
max_size = "2GiB"

[tools.retention]
automatic = true
max_versions_per_tool = 2
min_inactive_age = "7d"
```

Age cleanup removes eligible entries older than `max_age`. If known cache usage still exceeds `max_size`, cleanup removes the least recently used eligible entries until usage falls below the limit. Morphir records last use in owned cache metadata rather than relying on filesystem access time. The size limit is a target, not permission to remove protected or unknown content.

Automatic tool pruning runs after a successful update and during the same periodic maintenance opportunity used for caches. `max_versions_per_tool` includes the active release, so the default retains the active release and one rollback candidate. The minimum inactive age prevents an update followed by immediate automatic pruning. Protected releases may keep the store above any configured size target, which `cache status` and `tool prune --dry-run` report clearly. Setting `tools.retention.automatic` to `false` keeps manual `tool prune` available.

Retention settings choose what Morphir may remove, not where components store it. The legacy `cache.dir` setting cannot relocate managed cache content outside Morphir Home. Configuration migration diagnoses that setting and directs managed environments to relocate the whole home with `MORPHIR_HOME`.

### Ownership and deletion safety

Each cache namespace registers its owner, root, entry discovery rules, and lease checks with the maintenance engine. Cleanup ignores unknown files and directories. It never follows symbolic links or junctions, crosses the registered namespace root, deletes an active staging directory, or removes files selected only from untrusted metadata.

Deletion first renames an eligible entry into a maintenance trash directory beneath Morphir Home, then removes it. This keeps discovery and removal atomic from the perspective of new readers. Failed physical deletion leaves a named trash entry for a later retry and does not fail the user's primary command.

Cleanup emits structured events for policy evaluation, reclaimed bytes, skipped protected entries, failures, and elapsed time. Manual and automatic runs receive operation IDs. Troubleshooting output points to the CLI log and names the cache namespace without logging cached content or source credentials.

## Registry and trust

The first remote tool repository exposes immutable release descriptors plus mutable channel membership through the [tool release metadata v1 profile](../../spec/tool-release-metadata/index.md). A channel resolves to an exact descriptor before download. The installed catalog retains the exact trusted metadata version used for that resolution.

Artifact digests detect corruption only when the metadata carrying the digest is authentic. Public Desktop acquisition uses The Update Framework 1.0 with an out-of-band trusted root, consistent snapshots, sequential dual-threshold root rotation, signed freshness metadata, and SHA-256 target hashes. Mirrors share one repository identity and trust root. HTTPS remains required but is not the publisher-authentication mechanism. New resolution rejects expired metadata, while an installed release continues to launch from its exact catalog lock unless the client has persisted a trusted revocation.

Network access supports bounded timeouts, proxies, standard certificate stores, resumable downloads where the server permits them, and useful diagnostics. Cached metadata and bytes are verified before reuse.

## Desktop release contract

The CLI-managed release uses portable artifacts rather than system installers:

| Platform | Managed artifact | Separate system installer |
| --- | --- | --- |
| Windows | zip | NSIS or package-manager installer |
| macOS | zip containing the application bundle | DMG |
| Linux | tar archive or AppImage | deb and other distribution packages |

Each published artifact record includes exact version, operating system, architecture, archive type, digest, size, launch entry point, probe arguments, and minimum supported CLI or launch-contract version.

The Desktop release workflow publishes these artifacts and signed metadata to a durable release location. CI workflow artifacts are not a release source because they expire and may require repository authentication.

Windows executables and installers require code signing. The macOS application requires signing and notarization. Distribution metadata verification does not replace operating-system trust and quarantine checks.

## Launch contract

The CLI invokes the catalog's exact entry point directly without shell interpolation. It supplies:

- the resolved absolute `MORPHIR_HOME`;
- the requested workspace or artifact path;
- a launch-contract version;
- the parent operation ID and launch ID;
- filtered inherited environment variables;
- a platform-correct detached or foreground process mode.

Detached Desktop output goes to its Morphir Home log directory. Foreground operation may stream output to the terminal. Failure diagnostics name the exact release, executable, log path, and repair command without exposing credentials.

Launching an existing valid installation performs no required network operation. A bounded update check may report availability, but it must not delay launch, replace the active release, or turn a metadata outage into a launch failure. Applying updates remains explicit through `morphir tool update` until a separate automatic-update policy is approved.

## Observability and troubleshooting

Instrumentation, logs, and user-facing diagnostics have different jobs:

- instrumentation emits versioned structured events and spans from code;
- logs persist those events locally for later inspection;
- metrics summarize counts, sizes, and durations without replacing event detail;
- traces connect work across the CLI, acquisition engine, spawned processes, and Desktop;
- diagnostics explain failures and tell a person what to inspect or run next.

The first implementation uses structured local events and spans. Its field model remains compatible with OpenTelemetry, but no exporter is enabled by default.

### Current implementation gaps

The CLI now initializes structured local logging on the ordinary command path, writes per-session files beneath `MORPHIR_HOME/logs/cli`, applies separate console and file filters, and enforces the default age and size retention policy at startup. `MORPHIR_LOGGING__LEVEL` and `MORPHIR_LOGGING__FILE_LEVEL` are canonical, with the older names retained as compatibility aliases. Startup logging is currently environment-controlled and does not yet consume a discovered `[logging]` configuration table. Remaining CLI work includes configuration-file integration, operation and launch correlation, lifecycle spans, log discovery, diagnostic bundles, and redaction sentinel coverage. Tool and extension commands still print some lifecycle details directly instead of emitting structured events.

Morphir Desktop currently writes a few smoke messages through `console` and has no file logger, event schema, crash path, operation correlation, or troubleshooting interface. These are release gaps rather than optional refinements.

### User experience

Every install, update, repair, and Desktop launch receives an opaque operation ID. A launch also receives a launch ID and Desktop session ID. The CLI passes the parent IDs to Desktop so one troubleshooting query can follow selection, download, activation, spawn, readiness, and later process failure.

On success, normal output stays concise. On failure, the terminal and Desktop error view show:

- a stable error code and short explanation;
- the operation ID;
- the exact log path;
- the next safe command, such as `morphir tool repair desktop`;
- the diagnostic-bundle command when more evidence is useful.

The CLI provides:

```text
morphir diagnostics path
morphir diagnostics show --operation <ID>
morphir diagnostics collect --operation <ID> --output <FILE>
morphir doctor
```

Desktop provides matching actions under Help or Troubleshooting:

- Open Logs Folder
- Copy Operation ID
- Run Diagnostics
- Create Diagnostic Bundle

The interface must still expose these actions after a failed startup where the renderer cannot load. A minimal native error dialog may point to the same log path and operation ID.

### Local log contract

File logging is enabled by default for the CLI acquisition and launch path and for Desktop when Morphir Home resolves. If neither Morphir Home nor an explicit log directory can be resolved, the CLI remains console-only instead of writing into the working directory. Console output remains human-readable on standard error, while files contain UTF-8 JSON Lines. Standard output remains reserved for command results and machine-readable output.

Each process writes a separate session file so concurrent CLI and Desktop processes never compete for one rolling file:

```text
logs/
  cli/YYYY-MM-DD/<timestamp>-<pid>-<session-id>.jsonl
  desktop/YYYY-MM-DD/<timestamp>-<pid>-<session-id>.jsonl
  desktop/crashes/<timestamp>-<session-id>/...
```

The default file level is `debug`; the default console level is `info`. Environment variables may raise or lower either level. `MORPHIR_LOG_DIR` may relocate logs for tests or managed environments, but all components receive the same resolved override from the launcher. Discovered configuration-file controls remain planned rather than implemented.

Completed session logs are retained for 14 days with a 100 MiB limit per component. Cleanup removes the oldest completed sessions when either limit is exceeded. It never deletes an active log, an uncollected crash record newer than the retention window, or a file referenced by an in-progress diagnostic bundle.

If Morphir cannot create or write the log directory, it reports one warning to standard error and continues with console diagnostics. Logging failure must not hide or replace the primary operation result.

### Event and span schema

Every structured record includes:

- schema version, timestamp, severity, component, process ID, and session ID;
- operation ID and optional parent operation, launch, and trace IDs;
- stable event name and error code;
- tool identity, requested selection, exact version, platform, and safe source identity when relevant;
- outcome and measured duration for completed spans.

The acquisition and launch path records spans for:

```text
tool.resolve
metadata.fetch
artifact.download
artifact.verify
artifact.extract
tool.probe
catalog.activate
catalog.rollback
desktop.spawn
desktop.ready
desktop.exit
```

Download events may include byte counts, cache use, retry count, and elapsed time. Verification records the expected digest and outcome. Source fields omit credentials, query strings, and fragments.

Stable event names and error codes form a compatibility contract for diagnostic tools. Human message wording may improve without breaking searches or support automation.

### Desktop failures and crashes

Desktop records main-process exceptions, unhandled promise rejections, renderer termination, child-process termination, startup timeouts, and normal exit. Electron crash dumps remain local under the Desktop log directory. Automatic upload is disabled.

The CLI waits for a bounded readiness signal after spawning Desktop. A failed or timed-out readiness handshake reports the launch operation ID and points at both CLI and Desktop session logs. Detached launch does not mean unobserved launch.

Log writers flush completed error and exit events during normal shutdown. Crash handling uses the safest available synchronous or native mechanism and must not attempt complex recovery from a corrupted process.

### Privacy and redaction

Logs and bundles never contain:

- tokens, passwords, authorization headers, cookies, or resolved secret values;
- full environment dumps;
- source documents, Morphir IR contents, generated artifacts, or clipboard contents;
- URL query strings or fragments;
- secret-store files or operating-system keyring contents.

Local logs may contain paths needed to diagnose installation and launch problems. Diagnostic bundle creation normalizes the user-home prefix and provides a manifest of included files. Callers must use typed safe fields for secret references, URLs, commands, and paths instead of relying on a final regular-expression scrub.

Tests inject recognizable secret sentinels through every credential and configuration path and assert that no log, crash metadata file, terminal diagnostic, or bundle contains them.

### Diagnostic bundles

`morphir diagnostics collect` creates a local archive and never uploads it. The user can inspect it before sharing. By default it contains:

- correlated CLI and Desktop logs for the selected operation;
- crash metadata and dumps associated with that operation when present;
- CLI, Desktop, operating-system, architecture, and launch-contract versions;
- sanitized effective acquisition policy and release source identities;
- installed catalog metadata and integrity status;
- Morphir Home path and permission checks with the user-home prefix normalized;
- a bundle manifest listing included files, exclusions, and checksums.

It excludes project sources, IR, generated output, arbitrary environment variables, credentials, and secret stores. Adding project configuration or other potentially sensitive files requires an explicit flag and a preview of what will be included.

External metrics or trace export is opt-in. Enabling an exporter requires an explicit endpoint and configuration. The application reports that telemetry is enabled and applies the same field allowlist and redaction rules used by local logs.

## Failure scenarios

| Scenario | Required behavior |
| --- | --- |
| Offline, Desktop installed | Launch active release |
| Offline, Desktop absent | Fail without changing state and show install command |
| Download interrupted | Remove or retain resumable staging; keep active release |
| Digest mismatch | Quarantine or remove staged bytes; keep active release |
| Archive escapes staging | Reject release; keep active release |
| Probe fails | Do not activate candidate |
| Concurrent install and launch | Launch old active release or wait for a complete catalog transaction |
| Concurrent updates | Serialize by tool identity |
| Active bytes modified | Refuse launch and suggest `tool repair desktop` |
| New Desktop requires newer CLI | Select the newest compatible release or explain the CLI upgrade requirement |
| Desktop process already running during update | Activate new release for future launches without replacing files in use |
| CLI or Desktop cannot write logs | Warn once, continue on standard error, and preserve the primary result |
| Desktop renderer or main process crashes | Keep a local correlated crash record and show the operation ID on the next viable interface |
| Diagnostic bundle contains a secret sentinel | Fail the test and release gate |
| Cache exceeds its size target | Remove least recently used eligible entries and report protected or unknown bytes that remain |
| Cleanup overlaps a download or launch | Respect the active lease and skip that entry |
| Cleanup finds an unknown file or link | Leave it untouched and report it as unclassified |
| Cleanup stops at its runtime budget | Persist progress and resume during a later maintenance run |
| Artifact pruning evaluates the active or rollback release | Mark it protected and do not remove it |

## Delivery sequence

1. Make Morphir Home the unconditional root for cache and global configuration, then add cross-language conformance fixtures for path resolution and ownership.
2. Extract generic selection, authenticated acquisition, content-addressed storage, locking, and atomic catalog operations from the extension-specific implementation.
3. Define tool release records for archives, launch entry points, probes, and CLI compatibility.
4. Replace the metadata-only tool commands and migrate legacy `tools.json` intent safely.
5. Publish signed portable Desktop release artifacts for every supported platform.
6. Implement correlated local instrumentation, stable event schemas, redaction, log discovery, crash capture, and diagnostic bundles.
7. Implement `morphir desktop`, including first-use installation, `--offline`, direct launch, readiness correlation, and `--wait`.
8. Implement cache inventory and manual cleanup, then enable bounded opportunistic cleanup.
9. Implement `tool repair`, update availability reporting, protected-release retention, and `tool prune`.
10. Add the idempotent `morphir setup` workflow after the underlying operations are reliable.

Every implementation step starts with failure-focused tests. Cross-platform acceptance tests use a small signed fixture application before exercising a real Desktop package.

## Non-goals

- Treat Desktop as a Morphir Extension Protocol provider merely to reuse acquisition code.
- Install system packages or require administrator privileges from `morphir tool install`.
- Contact the registry during every launch.
- Apply a moving channel automatically during ordinary launch.
- Store mutable installation state in user-authored configuration.
- Let individual applications invent alternate Morphir Home roots.
- Upload logs, crash dumps, metrics, or traces without explicit user configuration or action.

## Remaining policy decisions

- Decide whether update availability checks are implemented by the CLI, Desktop, or a shared service.
- Define optional OS shortcut and file-association integration without making it part of portable installation.
- Choose the optional telemetry-export protocol and configuration after local instrumentation is proven.
