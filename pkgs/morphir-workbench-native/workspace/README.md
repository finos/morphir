# Read-only native workspace grants

The native picker supplies the sole absolute root. `Service` holds one opaque,
page-session-scoped grant and at most one captured model. Renderer requests use
grant/project identities, never filesystem paths. Closing the session closes the
directory descriptor and discards pending pickers and captured bytes.

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
even before admission, so a late open cannot recreate a cancelled capture. A
stale release cannot clear a newer capture. Ion binary version markers identify
binary `.ion`/`.10n` checkpoints without parsing their business values in the host.
Discovery prunes `.git`, `node_modules`, `_build`, `.mooncakes`, `.idea`, `.vscode`.

Project discovery uses `morphir-engine/workspace`, including `morphir.json`,
canonical configuration precedence, workspace membership and diagnostics. Opening
is read-only: conventional `morphir-ir.json/.ion/.10n/.ionb` checkpoints and model
files under the engine's configured `compile.dest` are available. Compilation,
scripts, writes, watches and persistent grants are not offered.

Run `mise run test:workbench-native-workspaces` for actual filesystem acceptance,
including another native process racing directory/symlink replacement. Packaged
picker/context qualification is separate from this CEF-free acceptance.
