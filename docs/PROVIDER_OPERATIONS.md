---
order: 30
---
# Authenticated metadata providers

The MoonBit engine can consume naming metadata declared by a freshly authenticated
Morphir Library. The embedding host supplies the restore capability. The CLI
binds that capability only when both project configuration and an explicit host
grant select the shared service.

## Configure a project and grant the host

Use the [CLI configuration and grant example](../apps/morphir/README.md#authenticated-metadata-provider).
The project selects a service, policy, complete lock, registry, existing trust
state and authority-qualified naming release. A separate grant authorizes those
paths for one exact workspace and project. Each project needs its own entry.

Paths selected in configuration resolve from that configuration file. Paths in a
grant resolve from the supplied grant file. CLI paths resolve from the invocation
directory. Keep the grant outside untrusted model inputs and accept its pins
through your normal installation review.

```shell
morphir run . --all --metadata-grants /host/grants.ion --json
```

For a single project, use `--project NAME` instead of `--all`. Grant files support
Ion text, binary Ion and an explicit JSON option through `.ion`, `.ionb` and
`.json` extensions. Process requests and responses use binary Ion. Native JSON
payloads remain exact byte blobs inside that exchange.

The service protocol is `morphir-package/provider-snapshot/0.1.0-draft.1`.
Its `local-library-mvp` profile version `0.1.0-draft.1` provides portable
filesystem assurance. A successful probe alone does not establish authentication.
Each consumption operation performs a fresh restore. A saved snapshot or audit
receipt cannot authorize a later operation.

## Prepare executable identities and trust

The grant pins the raw Node executable, raw shared-service executable and fixed
installed helper bundle. The bundle digest is SHA-256 of the compact JSON array
of `[filename, raw-SHA256]` pairs in this order:

1. `WindowsJob.cs`
2. `metadata.mjs`
3. `supervision.mjs`
4. `windows-job.mjs`
5. `windows-job.ps1`

Use the installed package's files, including when the native CLI invokes the
Node transport helper. Embeddings can call
`host.metadata_helper_bundle_sha256`. Accept changed pins only after reviewing
the new installation. An executable mismatch is an installation failure to
investigate, not a reason to disable pin checking.

Trust initialization belongs to the operator and shared restore component.
The MoonBit CLI does not initialize trust, discover a registry, install a service
or install publisher keys. Supply an already provisioned state directory that
matches the selected policy.

The qualification gate explicitly provisions disposable test trust using the
shared Rust example:

```shell
cargo run --locked -p morphir-package --example provider-snapshot-fixture -- \
  /new/test-fixture --provision-test-trust
```

The destination must be new. This example uses known test keys and is only for
development acceptance. It must never provision production trust. Its default
mode omits destination trust initialization. Re-exporting over an existing
destination refuses before writes.

## Inspect logs and refusals

```shell
morphir run . --all --metadata-grants /host/grants.ion --log --json
morphir run . --all --metadata-grants /host/grants.ion \
  --log-file /diagnostics/provider.jsonl --log-format json-lines --json
```

`--log` defaults to `.morphir/logs/frontend.ionb` under the discovered workspace
or project. An explicit destination is honored, including outside `.morphir/`.
Create its parent directory first. Logging is optional and does not change
generated artifacts or authentication decisions. Dry runs and project listing
do not acquire a provider or create logs.

Binary Ion audit records carry annotation `morphir_metadata_invocation_v1` and
profile `morphir-metadata-invocation-v1`. JSON Lines uses that profile field.
Filter it to inspect acquisition, probe, restore, decode, context, admission and
cleanup records. Correlate `run_id`, `operation` and `project` before comparing
phases from different projects.

A selected executable digest can appear before it has been checked.
`service_verified` and `profile_verified` state what the current operation has
verified. `native_revision` is absent until the retained native snapshot has
passed decoding and digest checks. That revision identifies original native
bytes, independently of the checked core projection. Logs exclude policy and
lock bodies, provider payloads and context documents. External OTEL export of
this audit profile is not qualified by the local-sink tests.

| Diagnostic | Next action |
| --- | --- |
| `metadata.restore_host_grants_required` | Supply the reviewed grant explicitly. |
| `metadata.restore_project_not_granted` | Check the discovered project root and its grant entry. |
| `metadata.restore_path_not_granted` | Compare selected paths and their configuration origins with the grant. |
| `metadata.restore_executable_changed` | Compare the installed Node, helper bundle and service with accepted pins. |
| `metadata.restore_authentication_failed` | Investigate policy, full lock, signed registry metadata, publisher authorization, expiry, rollback and trust-state status in the shared component. |
| `metadata.provider_revision_mismatch` | Compare the authored predicate pin with the freshly admitted native payload revision. |
| `metadata.restore_invalid_response` | Inspect the selected wire/projection profile and retained context inventory. |
| `data.lossy_conversion` | Retain the rich metadata in an Ion checkpoint or choose a supported checked JSON conversion. |

`--metadata-timeout` sets a project operation budget, including probe and cleanup,
between 6001 and 600000 milliseconds. The default is 120000. `--cancel-file PATH`
cancels when that path exists. The host disposes acquired sessions before
publication. Unconfirmed process termination retains owned scratch and blocks
publication. Cancellation does not promise to undo a trust update already
finalized by the shared verifier.

After an authentication or interrupted-operation refusal, follow the shared
component's recovery procedure. Do not copy an old trust database over current
state or restore older timestamp files to make an operation pass.

## Reproduce installed qualification

Check out shared Rust source revision
`2cf4be235a2bf6cff6dbfb1b677023fe9d91032b` into a separate, clean directory.
Install Rust 1.98.1 and the repository's complete pinned MoonBit toolchain.
Then run from this repository:

```shell
MORPHIR_PROVIDER_RUST=/absolute/path/to/morphir-rust \
MORPHIR_PROVIDER_RECEIPTS=.dev/installed-provider \
mise exec rust@1.98.1 -- mise run test:installed-provider
```

Set `MOON_HOME` to that complete MoonBit installation. The gate checks the clean
shared source revision, builds its locked service and fixture exporter, packs
and installs the npm CLI without repository scripts, and copies a freshly built
native CLI into the temporary installation. Each adversarial case receives
fresh explicitly initialized test trust. Previously published artifacts serve
only as the byte-preservation oracle; trust databases and retained responses
are never copied between cases.

The primary success receipt is `summary.ionb`, annotated
`morphir_installed_authenticated_v1`. `summary.json` is an explicit inspection
view. Success receipts are removed before a new attempt and written only after
all assertions, including decoding actual binary Ion audit logs and comparing
rich Ion values, pass. A receipt identifies the tested package, client, service,
Node, helper bundle, compiler, core, OS, architecture and assurance profile.

CI selects Ubuntu 24.04 and macOS 15 npm/native host lanes. A platform row is
qualified only after that exact job passes; adding it to the matrix does not
establish qualification. The receipt's `remaining` field lists coverage still
required for Task 6. Windows authenticated installation, pure Wasm/WasmGC process
hosting, hardened filesystem assurance, extension packaging and a production
signed naming-provider release are outside this gate's qualification claim.

Morphir JSON remains supported. Ion is preferred for engine processing and rich
metadata checkpoints. Conversion that would discard unsupported metadata refuses
before replacing published output.
