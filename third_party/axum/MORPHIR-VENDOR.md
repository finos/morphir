# Production Axum upgrade-future patch

This directory contains the published `axum 0.8.9` crate with one narrow API
factor. Axum is a **production dependency** of the Morphir CLI's HTTP/WebSocket
host. This patch is not confined to tests or fixture authoring.

Upstream: https://github.com/tokio-rs/axum

Archive: https://static.crates.io/crates/axum/axum-0.8.9.crate

Archive SHA-256: `31b698c5f9a010f6573133b09e0de5408834d0c82f8d7475a89fc1867a71cd90`

Published VCS revision: `c59208c86fded335cd85e388030ad59347b0e5ae`, directory `axum`.
The original `.cargo_vcs_info.json`, normalized and original manifests, archived
lockfile, sources, tests and MIT `LICENSE` are preserved. `UPSTREAM-SHA256SUMS`
records every original archive file before patching. The archive extraction was
compared with the checksum-verified published archive.

## Patch and ownership boundary

`morphir-owned-upgrade-future.patch` changes only `src/extract/ws.rs`. It factors
the existing `WebSocketUpgrade::on_upgrade` implementation into a new
`into_upgrade_future` method returning the response and the complete connection
future. Existing `on_upgrade` delegates to that method and spawns the future.
The new method spawns no task. Its caller can retain the real task join handle
covering the HTTP upgrade wait, WebSocket construction, callback execution and
final future destruction.

The extractor's handshake checks and rejection rules, HTTP/1 and HTTP/2 response
construction, selected protocol, WebSocket configuration, `on_failed_upgrade`
callback and message implementation are unchanged. To apply the exact reviewed
patch to a fresh archive extraction, run `patch -p2` with this patch as input
from the extracted crate root. Its preserved diff headers name the isolated
upstream and candidate source copies.

This API alone does not implement host task registration, bounded retention,
stopping new upgrades, cancellation-safe draining, capture-worker handoff or source
sealing. A socket callback's return, a counter or an acknowledgement is not a
task join. Actual socket joins and actual capture-worker joins remain separate
requirements.

## Verification lineage

The isolated public API controls first failed on the missing API, then passed
against the factor using the parent-critical locked versions:
Axum-core 0.5.6, Hyper 1.11.0, hyper-util 0.1.20, Tokio 1.53.1 and
tokio-tungstenite 0.29.0. They exercised real HTTP/WebSocket traffic, ownership
before callback entry, actual final-destructor completion, legacy echo and
subprotocol behavior, configured frame refusal and failed-upgrade callbacks.
The maintained controls are `crates/morphir/tests/axum_owned_upgrade.rs`; they
reuse the parent's existing tokio-tungstenite 0.30 dependency. Their maintained
integration gate must run after workspace configuration adopts this patch.

The three unmodified upstream WebSocket tests also passed, including the
HTTP/2 upgrade. That separate compatibility gate used the original archived
crate lockfile, which contains Hyper 1.7.0, hyper-util 0.1.17 and Tokio 1.47.1.
The archived lockfile is provenance, not the production workspace resolution.
These results are local macOS dependency-seam evidence, not full Morphir
campaign qualification, Windows runtime qualification or a claim of complete
feature-graph equivalence. No upstream publication or acceptance is claimed.

Once the workspace patch is configured, verify its actual resolution and
maintained regression controls from the parent checkout:

```sh
cargo tree --locked --package morphir --edges normal --target all
cargo test --locked --package morphir --test axum_owned_upgrade
```

The production dependency graph must resolve Axum to this directory. The
maintained parent workspace lockfile governs the production build.

## Packaging boundary

The root workspace patch applies to source-checkout builds governed by that
root manifest and lockfile. Morphir's release build produces binary archives
from such a checkout; binstall selects those prebuilt archives. A dependency's
root patch is not automatically applied when another project consumes a
registry crate. This preparation makes no claim that an independent crates.io
install, registry publication or downstream crate receives this patched Axum.

## Maintenance and removal

Morphir maintainers own this production patch. Do not edit other upstream code
to silence warnings or introduce Morphir protocol or policy behavior. Keep the
production dependency pinned to the reviewed Axum version while this API is
required. An upgrade must provide an actual caller-owned whole upgrade future,
with equivalent handshake, configuration, failure-callback and message behavior,
and pass the unchanged maintained controls plus affected host regression gates.

Remove this directory, the root `[patch.crates-io]` entry and the workspace
exclude entry together when replacing the patch. Update the production Axum
pin and regenerate the parent lockfile deliberately. Preserve the source
provenance and historical test evidence. No new hidden task, detached reaper or
callback-completion proxy may replace actual task ownership.
