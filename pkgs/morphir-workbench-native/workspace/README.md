# Read-only native workspace grants

The native picker supplies the sole absolute root. `Service` holds one opaque,
page-session-scoped grant and at most one captured model. Renderer requests use
grant/project identities, never filesystem paths. Closing the session closes the
directory descriptor and discards pending pickers and captured bytes.
Deferred picker cleanup checks its original ticket, so a late completion cannot
cancel a newer picker. Explicit cancellation still cancels the current picker.

On qualified POSIX platforms, every path component opens relative to held
directory descriptors with `O_NOFOLLOW`. All descriptors close on exec. Reads
reject symlinks, hard-linked files, special files, traversal and changed file or
ancestor identities. Root-path replacement and revocation reject later requests.
Namespace/file changes detected during capture fail rather than returning a torn
or substituted result. Discovery is a bounded observation, not an atomic snapshot
of the whole filesystem. Native filesystem latency depends on the selected mount.

Limits: 4,096 entries, 256 directories, depth 16, 256 KiB per configuration file,
2 MiB aggregate configuration, 128 project/model entries, 512 KiB offers and
16 MiB per captured model. Chunk replies contain at most 192 KiB of original
bytes encoded as base64. Release drops the capture; revoke closes the grant.
Transfers have monotonically increasing identities. Release retires an identity
even before capture acceptance, so a late open cannot recreate a cancelled capture.
A stale release cannot clear a newer capture. Ion binary version markers identify
binary `.ion`/`.10n` checkpoints without parsing their business values in the host.
Discovery prunes `.git`, `node_modules`, `_build`, `.mooncakes`, `.idea`, `.vscode`.

Project discovery uses `morphir-engine/workspace`, including `morphir.json`,
canonical configuration precedence, workspace membership and diagnostics. Opening
is read-only: conventional `morphir-ir.json/.ion/.10n/.ionb` checkpoints and model
files under the engine's configured `compile.dest` are available. Compilation,
scripts, writes, watches and persistent grants are not offered by this older
read-only mapping.

## Workspace editing

The separate `FileService` implements the
[`workspace-files` boundary](../../morphir-workbench-native-session/workspace-files/README.md).
The explicit **Open Morphir workspace for editing** picker creates a `WriteRoot`;
an older read-only `Root` grants no write access. `FileOwner` revalidates the
trusted page after the picker returns, owns up to eight folder grants, and closes
them on navigation or shutdown.

Snapshots retain original bytes, including binary model files. Before a commit,
the host compares the current full inventory against its own baseline. Edits
use descriptor-relative, no-follow operations, the shared
`.morphir-workspace-edit.lock`, staged files and no-replace renames. Existing
files/directories move into backups before replacement; installation failure
rolls back the batch. File mode and ownership survive replacement. A concurrent
change refuses the edit or yields an explicit unknown effect if rollback cannot
be confirmed. No command runs project configuration or scripts.

An uncertain rollback retains the lock directory and its `manifest.tsv`, which
maps `old-N` file and `dir-N` directory backups to their original relative paths.
Inspect those retained files and restore needed originals before removing the
lock. Do not delete the lock merely to bypass a failed save. Its presence blocks
new snapshots and saves until recovery is deliberate.

The browser saves through a separate, serialized file lane. Lost commit replies
query the same sequence's status rather than resubmitting it. A stale or unknown
save blocks later disk writes while preserving the local draft. Browser storage
retains only a folder name, never an OS grant; reopening a saved draft makes its
detached state visible and requires a new picker grant to reconnect.

Build the native test owner, then run the Chromium-to-native filesystem workflow:

```sh
moon build pkgs/morphir-workbench-native/files-acceptance --target native
bun run --cwd apps/morphir-workbench build
node --test apps/morphir-workbench/browser/workspace-files-browser.test.ts
```

This test host receives a temporary folder from its parent process. It does not
qualify the packaged OS picker or enable native capabilities on other platforms.

The explicit packaged test uses the real OS dialog. Launch the owned package
with `PROTON_REMOTE_DEBUGGING_PORT`, provide its loopback CDP endpoint and an
empty disposable folder, then select that folder in the **for editing** picker:

```sh
MORPHIR_WORKBENCH_NATIVE_CDP=http://127.0.0.1:9347 \
MORPHIR_WORKBENCH_NATIVE_FOLDER=/absolute/empty/test-folder \
node --test apps/morphir-workbench/browser/workspace-files-packaged.test.ts
```

The test supplies the folder path only to disk assertions. The application
receives the folder solely through the native dialog, then the test creates a
project through the production UI and checks its saved configuration and source.

Run `mise run test:workbench-native-workspaces` for actual filesystem acceptance,
including another native process racing directory/symlink replacement. Packaged
picker/context qualification is separate from this CEF-free acceptance.
