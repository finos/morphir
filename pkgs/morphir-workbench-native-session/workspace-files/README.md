# Workspace files boundary

`morphir/workbench/workspace-files` `0.1.0-draft.1` is a separate page-bound
capability for writable workspace folders. The existing native execution and
read-only workspace mappings retain their versions and closed shapes.

The codec accepts no native pathname. A trusted native picker creates a grant
only after the person chooses **Open for editing**. Session descriptors report
support and bounds; their presence does not grant filesystem authority.

Requests start with `session.open`. Other requests carry that page's session ID.
`workspace.choose-write` opens the explicit picker. Snapshot and edit transfers
carry opaque grant IDs and monotonic transfer sequences. Snapshot bytes are
bounded workspace-file JSON with typed text and binary content. Edits send a
complete candidate tree with the grant's expected base revision. The host owns
the disk baseline and applies a checked difference; a renderer cannot provide a
trusted baseline or host locator.

| Operation | Purpose |
| --- | --- |
| `workspace.snapshot` | Capture current files and return transfer size and revision. |
| `workspace.read` | Download the next captured byte chunk. |
| `workspace.begin-edit` | Start an upload for a captured base revision and byte size. |
| `workspace.write` | Upload the next canonical base64 chunk. |
| `workspace.commit` | Validate and apply the complete candidate tree once. |
| `workspace.status` | Reconcile an uncertain upload or commit without resubmitting it. |
| `workspace.release` | Retire a transfer after its outcome is known. |
| `workspace.revoke` | Release the folder grant. |

Frames are at most 1 MiB. Chunks contain at most 192 KiB of decoded bytes;
nonterminal download chunks have that exact length. A serialized workspace
transfer is at most 24 MiB, and its decoded files retain the Workbench's
2,000-file and 16-MiB aggregate bounds. A page may retain eight folder grants.
Inventory traversal admits at most 256 directories and relative paths at most
16 components deep. Transfers carry `{ "version": 1, "files": { ... } }`;
each file is UTF-8 text or `{ "encoding": "base64", "content": "..." }`.
The host preserves pre-existing empty directories and derives directory cleanup
from removed file parents. The inventory never includes a native locator.

Replies bind to the captured operation and session. Transfer replies also bind
the sequence and offset. Upload acknowledgements identify the next offset.
Status uses closed `idle`, `uploading`, `committed` and `failed` states. A failure
reports `none` or `unknown` effect separately from its diagnostic. An uncertain
commit is queried, not submitted again. The native owner must preserve recovery
data when it cannot confirm rollback.

This package validates data and makes no OS calls. Native ownership, filesystem
confinement, transfer state and application wiring supply the actual capability.
`RelativePath` and `Inventory` provide the shared path, byte and directory-bound
validation. `Inventory.difference` derives the file/directory batch used by the
native owner and the [offline MCK witness](../../../apps/morphir-workbench/mck/workspace-files/README.md).

The proposed connected mapping carries these same raw frames through
`morphir.workspace-files.exchange`, bound separately to an authenticated v1
session, provider and advertised source. The file connection owns its grants
and closes on unexpected or invalid RPC replies. Complete JSON-RPC envelopes
are bounded to `CONNECTED_FRAME_LIMIT` (2 MiB plus 64 KiB), and
`decode_connected_reply` checks their exact shape and pending call ID before
the inner file reply is validated. Host adoption is external work; see the
[client binding](../../../apps/morphir-workbench/README.md#connected-host-compatibility).
