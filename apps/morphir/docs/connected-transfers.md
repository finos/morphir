# Save connected artifacts and model originals

Select an authenticated Workbench host that advertises the exact
`morphir/workbench/artifacts` `0.1.0-draft.1` service. Use Node 24 on POSIX, or a
native POSIX CLI with its maintained Node 24 helper. Windows private credential
protection is unavailable in this binding. Portable Wasm and Wasm GC explicitly refuse it.
Terminal setup uses the host's one-use launch URL through a private input file or
stdin; it does not need a browser or UI assets.

```sh
morphir connected connect launch.txt --provider workbench-http \
  --connection connection.json --connection-scope artifacts --json
morphir connected artifacts request.json --provider workbench-http \
  --connection connection.json --output saved --json
```

The connection file is private to its owner. Protect it as a credential. The CLI
never places its cookie or the one-use launch token in process arguments or
reports. The destination connection file must not already exist. Artifact setup
selects exactly one advertised provider; execution setup remains the default
`--connection-scope executions` and has its separate descriptor.

The request has exactly these fields:

```json
{
  "providerId": "playground",
  "target": "your-negotiated-target",
  "irVersion": "4.0.0",
  "ir": {},
  "options": {}
}
```

Supply the actual IR accepted by that selected producer. This command consumes
generated artifacts; it does not silently compile source, select another
provider, or use a legacy artifact representation. A file or `-` for stdin is
bounded to a complete 1 MiB UTF-8 request.

Every file in the captured inventory must pass its exact length and SHA-256
checks, and the owning generation must be released, before any bytes become
eligible for publication. The limits are 256 files, 16 MiB per file and 64 MiB
per generation. Empty files and binary/NUL bytes retain their exact content.

The CLI saves the complete verified inventory to `saved/artifacts` using its
current content publisher. It refuses an existing artifact destination and
checks again under the publication lock. A successful report says
`"publication":"cli"`; it does not claim the host published files. Remote
retention, local scratch and local publication have separate owners.

`--timeout` bounds acquisition in milliseconds (default 120000, maximum 600000).
SIGINT or `--cancel-file` discards the attempt. Closing the dedicated connection
cleans only its owning remote retention; a missing reply is reported as a closed
connection with uncertain retention identity rather than a confirmed release.
There is no implicit resubmission, reconnect to another owner, or profile
fallback. Each invocation freshly authenticates and checks the pinned session
and exact provider offer.

Exit status 0 means publication succeeded after verification and release; 1
means a transfer, publication, cleanup or timeout failure; 2 means a refused
request/setup; and 130 means interruption. Reports retain the cleanup outcome.

Original-model access uses its separate exact service negotiation described
below. Artifact bytes, model projections and MEP generation capabilities do not
grant that access. Local model commands retain their captured-original behavior.

## Connected model originals

`connected originals` downloads complete declared original-model inventories through
`morphir/workbench/model-originals` at exactly `0.1.0-draft.1`. The initial consumer
requests `scope: complete` and `semantic: none`. It preserves original bytes without
requiring semantic conversion or treating a projection as an original.

Launch the draft host preview explicitly:

```sh
morphir ui --no-open --preview-model-originals WORKSPACE
```

The flag grants and advertises the preview originals service; default `ui` leaves
it disabled. Establish a separate model connection using that host's one-time
launch URL:

```sh
morphir connected connect launch.txt --provider workbench-http \
  --connection session.json --connection-scope models --json
```

The result lists actual offered sources without printing the session cookie. Copy
one source's `providerId` and `locator` into `selection.json`, then discover its
actual project IDs:

```json
{"source":{"providerId":"COPY_FROM_CONNECT","locator":"COPY_FROM_CONNECT"}}
```

```sh
morphir connected originals selection.json --list --provider workbench-http \
  --connection session.json --json
```

Add the selected `projectId` from that result to the same selection document:

```json
{"source":{"providerId":"COPY_FROM_CONNECT","locator":"COPY_FROM_CONNECT"},"projectId":"COPY_FROM_LIST"}
```

```sh
morphir connected originals selection.json --provider workbench-http \
  --connection session.json --output saved --json
```

The CLI saves to `saved/originals` through the existing confined transactional
writer. It preserves source-relative paths, binary sidecars and empty directories.
Its create-only commit reserves a previously absent destination with a private
empty directory, then renames the fully staged tree into that reservation.
The empty reservation may be briefly visible. A pre-existing destination refuses,
and a reservation populated by another writer is never replaced or recursively
removed. Cleanup failure identifies the retained reservation for recovery.
This does not promise an atomic transition from absent to full against another
same-user actor replacing an empty reservation. Compiler bookkeeping outside the declared
roots is not downloaded. A complete capture with undeclared companions refuses
instead of inferring them by scanning a directory.

The consumer checks the selected session/provider/source/project, exact profile,
complete contiguous inventory, deterministic pagination, portable paths, inventory
digest, original lengths, canonical base64 and every file digest. All originals
must verify and the owning host must acknowledge release before local publication.
The writer rechecks private file bytes and stages them before committing the whole
destination. A failed later file cannot publish an earlier prefix.

The profile permits up to 64 MiB of original bytes and 100,064 inventory entries.
Its path bounds are separate from the smaller generated-artifact and local model
bounds. Inventory metadata has a separate 64 MiB consumer ceiling. The report
contains counts and the inventory digest rather than printing the whole inventory.
`sourceFormatVersion: not-reported` is preserved honestly; it does not prevent
saving verified original bytes.

Each original-model RPC has the profile's 30-second exchange deadline.
`--timeout`, `--cancel-file` and SIGINT remain active through local staging and the
final commit guard. An uncertain exchange
closes the attempt's own socket without automatically retrying capture. A
`connection-closed` cleanup result records teardown of that connection; it is not
a confirmed remote release or proof that an outstanding host worker has exited.
Only `released` permits publication. No host process is terminated by the CLI.

The installed Node launcher locates its packaged helper automatically. A native
binary also requires `--originals-helper PATH` or `MORPHIR_ORIGINALS_HELPER`, and a
Node executable through `--node` when needed. Connected effects currently refuse
explicitly on Windows and portable Wasm/Wasm GC. POSIX Node/native integration is
exercised against an explicitly selected service binary with
`MORPHIR_MODEL_ORIGINALS_HOST`; this does not qualify every platform or the full
connected profile. Semantic projection, browser/desktop adoption and the broader
service campaign retain their separate qualification requirements.
