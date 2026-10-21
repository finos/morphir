# Workspace files capability witness

This independent MCK suite, `workbench-workspace-files` `0.1.0-draft.1`, checks
the new file capability's requests, correlated replies and proposed file edits.
Historical Workbench MCK versions keep their accepted operations and shapes.
The upstream offer is tracked separately in `morphir-ukvn.5.86.18`.

`workspace-files` inventory and path validators are shared with the native file
service. The edit witness observes creates, replacements and deletions, derived
parent directory creation/removal, exact replacement bytes, and preservation of
existing empty directories. Paths are confined relative paths: absolute paths,
traversal, control characters, omitted tool directories and the recovery lock
are refused. Native descriptor, symlink, hardlink, special-file and concurrent
replacement checks run in the real filesystem acceptance suite.

The adapter consumes NDJSON. Requests have `id`, `op`, `suite`, `contractVersion`,
`format: "json"` and `input`; `capabilities` omits `format` and `input`.
`{"id":1,"op":"exit"}` terminates the stream. IDs are positive safe integers.
The adapter accepts compact case lines up to 2 MiB; live inventory transfer
bounds remain in the file capability descriptor.

| Operation | Input |
| --- | --- |
| `validate-request` | `{encoding, source}` containing the complete raw native frame |
| `validate-reply` | `{request, reply}`, each with `{encoding, source}` |
| `observe-file-edit` | `{baseline, candidate, directories}`, with encoded inventory documents and the host's baseline directory paths |

Encoding is `utf8` or canonical `base64`. Inventory documents have
`{"version":1,"files":{...}}`, with UTF-8 strings or explicit base64 file
records. The edit observation returns a map of changed paths to canonical
base64 bytes, deleted paths and created/removed directory paths. Directory
creation sorts by depth, then UTF-16 lexical order; the other path arrays sort
in UTF-16 lexical order. This makes cross-language comparison independent of
the runtime's default string ordering.

Run either adapter:

```sh
moon run apps/morphir-workbench/mck/workspace-files/js --target js
moon run apps/morphir-workbench/mck/workspace-files/native --target native
```

This is an offline observation. The live host owns picker intent, page identity,
grants, baseline revisions and disk effects; an accepted witness supplies none
of those authorities.
