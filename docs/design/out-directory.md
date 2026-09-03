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

Task ids are path-like: `compile`, `generate/<target>`, `transform/<name>`.
`<task>.dest/` is cleared before each run. `<task>.json` is written only after
the task succeeds, so a `.dest` without a matching `.json` is always treated
as incomplete and rerun.

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

`[workspace].out_dir` only has effect in the workspace root configuration. If
a member's own config sets it, the CLI warns that the setting is ignored and
falls back to the workspace's own `out_dir` (or the default).

## Result record

    {
      "schema": 1,
      "task": "compile",
      "module": "packages/orders",
      "language": "gleam",
      "inputs": [],
      "value": ["morphir-ir"],
      "ir": {"path": "morphir-ir", "layout": "document-tree", "format": "json", "version": "v4"},
      "ejected": {"/abs/dist": ["morphir-ir/manifest.json", "morphir-ir/Module.json"]},
      "completedAt": "2026-09-02T10:00:00Z"
    }

`value` lists the task's product as paths relative to `.dest`. Parse-stage
files and bookkeeping manifests are never in `value`. `ir` is present on
tasks that produce IR; generate reads IR through it, so JSON, YAML, and
document-tree storage all work. `inputs` records provenance. `ejected` maps
each target directory `-o` has ever pointed at to the individual *files* eject
wrote there — not the `value` entry names — because a `value` entry can name
a whole directory (a document-tree IR, for example) and eject must be able to
tell its own files apart from content a user placed in or beside that
directory. Unknown fields are preserved across a read-modify-write cycle.

## Eject

`-o <path>` no longer redirects a task. The task runs to `.dest`, then the
`value` entries are copied to `<path>`. Eject never deletes `<path>`, and
never deletes a directory wholesale — a re-eject only removes the individual
files it wrote earlier that the current run no longer produces, then removes
any directories that are left empty by that. Anything else under `<path>`,
including a directory a user created inside a directory-valued entry before
or after the first eject, is left alone. If `<path>` already exists as a
plain file rather than a directory, eject refuses and names the path in its
error rather than failing on a confusing filesystem error. Before copying
anything, eject also checks every file it is about to write against the
target: if a file already sits there and eject did not write it on a
previous run, eject refuses the whole operation and lists every such
conflicting path, rather than overwriting foreign content and later
deleting it once the task stops producing it. This is the Zig `zig-out`
install step; `.dest` is the cache, and `-o` only ever adds or retires files
it owns there.

## IR storage

    [ir]
    layout = "single-file"   # or "document-tree"
    format = "json"          # or "yaml"

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
