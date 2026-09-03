---
title: Out directory
sidebar_label: Out directory
status: implemented
---

# Out directory

Every task writes under one out root per workspace, following [Mill](https://mill-build.org/)'s
`out/` convention: each task gets its own scratch directory and a small record
of what it produced.

## Layout

```text
<workspace>/.morphir/out/
├── compile.dest/            # root module scratch: IR plus parse stage
├── compile.json             # root module result record
├── generate/
│   ├── scala.dest/
│   └── scala.json
└── packages/orders/         # member module, path relative to the workspace root
    ├── compile.dest/
    ├── compile.json
    └── generate/…
```

Task ids are path-like: `compile`, `generate/<target>`, `transform/<name>`.
A run also takes an exclusive lock on `<task>.lock` beside the other two,
held from the moment `.dest` is cleared until the record is written and any
`-o` install is finished. Two runs of the same task in one workspace share
one `.dest` and one `.json`, so the second waits for the first — it prints
one line saying so — rather than deleting a directory the first is still
writing into. A command that only *reads* a finished task takes the same
lock shared rather than exclusively: `generate` holds `compile.lock` from
before it reads `compile.json` until it has read the IR out of
`compile.dest`, so a compile starting in between cannot clear that directory
under it. Several readers may hold the shared lock at once. The lock file
stays on disk between runs and is empty.

`<task>.dest/` is cleared before each run. `<task>.json` is written in full
only after the task succeeds; a run that fails instead leaves a tombstone
(see [Result record](#result-record)), a record marked `"tombstone": true`
that keeps no product, so the task's output is treated as missing either
way — nothing reruns it automatically, and the user must run the task
again.

## Root resolution

1. `--out-dir <path>` (relative to the current directory)
2. `MORPHIR_OUT_DIR` (relative to the current directory)
3. `[workspace].out_dir` in the workspace root config (relative to the workspace root)
4. `<workspace_root>/.morphir/out`

## Workspaces and members

`[workspace].members` takes glob patterns, for example `members = ["packages/*"]`.
Running a command from inside a member directory — or pointing it at the
member's own `morphir.toml` directly — still resolves the enclosing
workspace: the out root always sits at `<workspace>/.morphir/out`, and the
member's task records live under `<workspace>/.morphir/out/<member path>/`,
where `<member path>` is the member's directory relative to the workspace
root. A member never gets an out root of its own.

`[workspace].out_dir` only has effect in the workspace configuration. A
member may not set it, in its own `morphir.toml` or in a `morphir.user.toml`
beside it: the out root is shared by the whole workspace, so one member
setting it would move every other member's output too. The CLI warns and
names the file, and the workspace's own `out_dir` (or the default) stands.
A `morphir.user.toml` next to the *workspace* configuration may still set
it, since that speaks for the whole workspace.

A `members` entry or a `default_member` that leaves the workspace directory
— `../outside`, an absolute path, or one written with backslashes — is
skipped with a warning naming it, rather than pulling a configuration in
from outside the workspace.

## Result record

```json
{
  "schema": 1,
  "task": "compile",
  "module": "packages/orders",
  "language": "gleam",
  "inputs": [],
  "value": ["morphir-ir"],
  "ir": {"path": "morphir-ir", "layout": "document-tree", "format": "json", "version": "v4"},
  "installed": {"/abs/dist": ["morphir-ir/manifest.json", "morphir-ir/Module.json"]},
  "completedAt": "2026-09-02T10:00:00Z"
}
```

`value` lists the task's product as paths relative to `.dest`. Parse-stage
files and bookkeeping manifests are never in `value`. `ir` is present on
tasks that produce IR; generate reads IR through it, so JSON, YAML, and
document-tree storage all work. `inputs` records provenance. `installed` maps
each target directory `-o` has ever pointed at to the individual *files* install
wrote there — not the `value` entry names — because a `value` entry can name
a whole directory (a document-tree IR, for example) and install must be able to
tell its own files apart from content a user placed in or beside that
directory. Unknown fields are preserved across a read-modify-write cycle.

Starting a task does not delete its previous record outright: if one exists
and can be read, it is overwritten with a TOMBSTONE — the same record with
`value` and `inputs` emptied, `installed` and `completedAt` left exactly as
they were, and `language` and `ir` omitted (both are `skip_serializing_if =
"Option::is_none"`, so setting them to `None` drops the keys from the JSON
entirely rather than writing `null`). `extra` — the catch-all for fields
this version does not know, such as a future `inputsHash` — is cleared too,
since it may hold values computed from the previous `.dest`, which a
tombstone no longer has. If the run succeeds, it overwrites the tombstone
with a real record. If it fails, the tombstone is what stays on disk. This
keeps the install ledger available across a failing run: without it, a
failed `compile` between two `-o` installs would lose track of what an
earlier successful run had put at the target, and the next `install` would
see its own earlier output as foreign content it never wrote and refuse to
run.

A tombstone says so outright, through `"tombstone": true`. The flag is
omitted from an ordinary record, so records written before it existed read
back as ordinary results. Readers go by the flag and not by the shape,
because an empty `value` means something quite different on a record that
succeeded: the task ran and had nothing to emit this time. `generate`
treats a tombstone the same as a missing record, while a successful record
with no `ir` gets its own "produced no IR descriptor" error. `install`
refuses a tombstone, since installing one would mean "copy nothing, and
remove everything previously installed"; a successful record with an empty
`value` installs normally, which retires the files the last run put at the
target and leaves an empty ledger for it. A record that fails to decode
(hand-edited, truncated, or written by an incompatible version) is removed
outright instead of being turned into a tombstone, since there is nothing
reliable to preserve from it.

## Install

`-o <path>` no longer redirects a task. The task runs to `.dest`, then the
`value` entries are copied to `<path>`. Install never deletes `<path>`, and
never deletes a directory wholesale — a re-install only removes the individual
files it wrote earlier that the current run no longer produces, then removes
any directories that are left empty by that. Anything else under `<path>`,
including a directory a user created inside a directory-valued entry before
or after the first install, is left alone. If `<path>` already exists as a
plain file rather than a directory, install refuses and names the path in its
error rather than failing on a confusing filesystem error. Before copying
anything, install also checks every file it is about to write against the
target: if a file already sits there and install did not write it on a
previous run, install refuses the whole operation and lists every such
conflicting path, rather than overwriting foreign content and later
deleting it once the task stops producing it. A destination the ledger does
not name by string may still be a file install wrote under a different
spelling: on a case-insensitive filesystem a generated `Foo.gleam` that comes
back as `foo.gleam` is the very same file. Install compares such a
destination against its ledger by filesystem identity, keeps it as its own,
and records the new spelling in place of the old one. It resolves every destination
against the filesystem in that same pass: a symlink already in the target
that leads out of it — `dist/morphir-ir` pointing at `/outside`, say — is
refused by name, because `create_dir_all` and a file copy would otherwise
follow it and write outside the target.

A symlink that lands back inside the target is an ordinary part of a user's
layout — `dist/morphir-ir` pointing at `dist/real` — and keeps working, on
every install and not just the first. Install owns a path by where it
*resolves*, not by how it is spelled: the ledger records each file relative to
the canonical target with the links between them followed, so the example
above is recorded as `real/manifest.yaml`.

That is what tells a supported layout apart from a directory install created
and the user later replaced with a link. A link that was already there
resolves the same way on the next run, so its ledger entries still match and
the install proceeds. A real directory swapped for a link to somewhere else
under the target resolves somewhere new, its entries no longer match, and the
files at the new location are the user's — so install refuses, naming the
link, rather than deleting or overwriting through it.

Resolving every destination also catches two differently spelled outputs
landing on one file: `dist/a` and `dist/b` both linking to `dist/real` makes
`a/config` and `b/config` the same destination, `real/config`. Install checks
for that collision before writing anything and refuses the whole run, naming
every colliding spelling and the destination they share, rather than letting
the second copy silently overwrite the first.

If a copy fails partway through — the disk fills up, say — install does not
leave the target in a state the next install cannot make sense of. Every
file this run added, including a partially written file the failing copy
itself left behind, is removed; a file this run merely overwrote, which was
already owned from an earlier install, is left as it is rather than deleted.
The ledger is then rewritten so it matches whatever is actually left on disk
— previously owned files that are still there, minus any this run correctly
retired, plus anything this run added that could not be cleaned up — and the
original copy failure is returned. Cleanup itself is best-effort: one file
that cannot be removed does not stop the rest from being cleaned up, and does
not stop the ledger from being written; it is just kept in the ledger,
since it is still really on disk.

The whole install — the conflict scan, the removals, the copies, and the
ledger write — runs under an exclusive lock on the install target. The task
lock is not enough here: `compile -o dist` and `generate -o dist` hold
different task locks, so without a target lock both can find one destination
absent, both write it, and both record themselves as owning it. The lock is
keyed on the canonical target alone, not on the out root as well, so two
spellings of one directory are one directory, and two different workspaces
(two different out roots) that both name the same `-o` target share the one
lock too, rather than each believing it holds an uncontested lock of its own.
The lock file lives at `<Morphir home>/locks/install/<hash>.lock` — the
user-global Morphir home directory, not inside the target, where the
conflict scan would read it as foreign content. If the Morphir home
directory cannot be resolved, install falls back to
`<out root>/install-locks/<hash>.lock` and says so on stderr; that fallback
is per out root again, which is the tradeoff of not having a home directory
to key off.

This is the Zig `zig-out`
install step; `.dest` is the cache, and `-o` only ever adds or retires files
it owns there.

## IR storage

```toml
[ir]
layout = "single-file"   # or "document-tree"
format = "json"          # or "yaml"
```

Names inside `.dest`: `morphir-ir.json`, `morphir-ir.yaml`, `morphir-ir/`.

`ir.mode` (`classic`/`vfs`) is still accepted as a deprecated alias for
`ir.layout` for one release: `classic` maps to `single-file` and `vfs` maps to
`document-tree`. Setting `ir.mode` prints a warning. An explicit `ir.layout`
always wins over `ir.mode` when both are set.

The single-file Elm compile path (`morphir compile --input <file>` without a
project config) always writes classic v3 JSON and ignores `[ir]` entirely; if
a `--config` was given whose `[ir].layout` or `[ir].format` asks for
something else, it prints a warning that those settings do not apply.

`generate -i <path>` accepts any of:

- a single IR file (`morphir-ir.json` or `morphir-ir.yaml`)
- a document-tree directory (one with `manifest.json` or `manifest.yaml` at its root)
- a compile-output directory — a `.dest` directory or any directory that
  holds `morphir-ir.json`, `morphir-ir.yaml`, or a nested `morphir-ir/`
  document tree, without a manifest of its own

## Configuration keys

Removed and renamed keys each produce one warning line when present:

| Old key                       | New key                | Notes                                   |
| ------------------------------ | ----------------------- | ---------------------------------------- |
| `project.output_directory`     | *(removed)*             | all task output lives under `workspace.out_dir` |
| `workspace.output_dir`         | `workspace.out_dir`     | rename only                              |
| `ir.mode`                      | `ir.layout`             | deprecated alias for one release         |

## Extension point

`resolve_ir_task` in the CLI decides which task's IR generate consumes. It
returns `compile` today and will return the last `[pipeline].transforms`
entry once transform stages exist ([finos/morphir#786](https://github.com/finos/morphir/issues/786)).
Incremental execution will add `inputsHash` to the record
([finos/morphir#785](https://github.com/finos/morphir/issues/785)).
