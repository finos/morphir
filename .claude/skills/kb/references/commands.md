# `morphir kb` Command Reference

All commands take `--kb <path>` (auto-detected by walking up from the working directory to a directory containing
`kb/bundles`; the resolved root is its `kb/`) and `--json`.

`--json` writes structured output on stdout; progress goes to stderr. Errors print `error: <msg>` and exit 1. Pipe
freely:

```bash
morphir kb check --json | jq '.findings[] | select(.severity=="error")'
```

---

## `list`

Bundles, their OKF version, concept count and title.

| Flag | Meaning |
| ---- | ------- |
| `--bundle <name>` | List that bundle's concepts instead. Accepts `morphir-ir-v3` or `morphir/morphir-ir-v3` |

```bash
morphir kb list --bundle morphir-ir-v3
```

JSON gives `{root, bundles[{label, name, group, okfVersion, title, description, concepts, subIndexes, hasLog}]}`, or
with `--bundle`, `{bundle, concepts[...]}`.

---

## `show`

One document: frontmatter, outbound links, heading outline.

| Flag | Meaning |
| ---- | ------- |
| `--path <p>` | Required. Bundle-relative (`/naming.md`) or any path suffix (`morphir-ir-v3/naming.md`) |
| `--bundle <name>` | Disambiguates a bundle-relative path when several bundles share it |
| `--body` | Include the document body |

```bash
morphir kb show --path /naming.md --bundle morphir-ir-v3
```

---

## `search`

| Flag | Meaning |
| ---- | ------- |
| `--query <text>` | Matches titles, descriptions, types, tags and paths, case-insensitively |
| `--body` | Also search prose, reporting matching line numbers |
| `--type <t>` | Filter by frontmatter `type` |
| `--tag <t>` | Filter by tag; repeatable, all must match |
| `--status <s>` | Filter by `status` |
| `--bundle <b>` | Restrict to one bundle |
| `--index` | Search through the SQLite index (FTS5) instead of scanning — bodies included, ranked by relevance |
| `--limit <n>` | Row cap when using `--index` (default 20) |
| `--db <path>` | Index location (default `<repo>/.dev/kb/index.db`) |

Filters combine, and any of them works without `--query` — `--status draft` alone lists every draft concept. They
apply to the indexed search too, so `--index --query naming --bundle platform` ranks by relevance within that
bundle. The one thing `--index` insists on is a `--query`; it refuses without one.

```bash
morphir kb search --tag v4 --status draft
```

```bash
morphir kb search --query "format version" --body
```

---

## `check`

Runs every check and exits non-zero when there are errors.

| Flag | Meaning |
| ---- | ------- |
| `--verbose` | Include info-level findings |
| `--strict` | Exit non-zero on warnings too |
| `--allow-dangling` | Dangling links become warnings — OKF's stance that they mark not-yet-written knowledge |
| `--refs <path>` | Reference checkout root (default `<repo>/.refs`) |
| `--no-provenance` | Skip the `.refs/` comparison entirely |
| `--out <path>` | Write the report to a file instead of stdout. Put these under `.dev/` |

```bash
morphir kb check --verbose
```

```bash
morphir kb check --json --out .dev/kb/out/check.json
```

→ [checks.md](checks.md) for what each finding means.

---

## `index`

Builds the SQLite index over the knowledge base.

| Flag | Meaning |
| ---- | ------- |
| `--status` | Report when the index was built and which files changed since, instead of rebuilding |
| `--db <path>` | Database location (default `<repo>/.dev/kb/index.db`) |

```bash
morphir kb index
```

```bash
morphir kb index --status
```

→ [index-db.md](index-db.md) for the schema and worked queries.

---

## `refresh`

Brings derived state back in line with the markdown. There are two kinds of it, and `morphir kb refresh` on its own
does both: rewrites index bullets that have drifted from their concept's `description`, then rebuilds the SQLite
index if anything changed.

```bash
morphir kb refresh
```

```bash
morphir kb refresh --dry-run
```

### Narrowing it

Either a subcommand or a flag. They are the same operation; the subcommands just read better.

| Form | Does |
| ---- | ---- |
| `morphir kb refresh` | Both halves |
| `morphir kb refresh markdown` (alias `md`) | Index bullets only — same as `morphir kb refresh --no-db` |
| `morphir kb refresh db` (alias `index`) | SQLite index only — same as `morphir kb refresh --no-markdown` |

### Flags

| Flag | `refresh` | `refresh markdown` | `refresh db` |
| ---- | :-------: | :----------------: | :----------: |
| `--dry-run` — report, write nothing | ✓ | ✓ | ✓ |
| `--force` — rebuild even when up to date | ✓ | | ✓ |
| `--add-missing` — append entries for unindexed concepts | ✓ | ✓ | |
| `--section <s>` — section for appended entries (default `Orientation`) | ✓ | ✓ | |
| `--db <path>` — database location | ✓ | | ✓ |
| `--no-markdown` / `--no-db` — narrow the scope | ✓ | | |

```bash
morphir kb refresh markdown --add-missing --section "Design rationale"
```

```bash
morphir kb refresh db --force
```

Description drift is fixed automatically because the repair is purely mechanical — the bullet is *supposed* to mirror
the description, so there is only one right answer. Only the trailing text is rewritten; the link is preserved
verbatim, so a hand-written link title survives.

Appending a **missing** entry means choosing which section it belongs under, which is a judgement call, so it is
opt-in via `--add-missing`. Without that flag, unindexed concepts are reported and left alone.

When the markdown changes, the knowledge base is reloaded before the database is rebuilt, so the index always
reflects what ended up on disk.

---

## `query`

Read-only SQL over the index.

| Flag | Meaning |
| ---- | ------- |
| `--sql <sql>` | Required. `SELECT`, `WITH`, `PRAGMA` or `EXPLAIN`; anything else is refused |
| `--db <path>` | Database location |

```bash
morphir kb query --sql "SELECT type, count(*) FROM v_concept GROUP BY type ORDER BY 2 DESC"
```

---

## `new-bundle`

| Flag | Meaning |
| ---- | ------- |
| `--name <slug>` | Required. Slugified if it is not already kebab-case |
| `--title <t>` | Required |
| `--description <d>` | Required. One sentence — it becomes the bundle's `description` |
| `--group <g>` | Grouping directory under `bundles/`, e.g. `morphir` |
| `--okf-version <v>` | Defaults to `0.2` |
| `--date <YYYY-MM-DD>` | Override today's date in the log entry |

```bash
morphir kb new-bundle --group morphir --name morphir-ir-v5 \
  --title "Morphir IR v5" --description "The v5 IR specification."
```

Creates `index.md` and `log.md`. It does **not** update `kb/README.md` or the group's `README.md` — it prints a
reminder instead, because that wording is a judgement call.

---

## `add-concept`

Creates the concept, inserts an index bullet, and appends a log entry.

| Flag | Meaning |
| ---- | ------- |
| `--bundle <b>` | Required |
| `--path <p>` | Required. Within the bundle: `naming.md`, or `design/naming.md` for a subdirectory |
| `--type <t>` | Required. The one universally required OKF field |
| `--title <t>` | Required |
| `--description <d>` | Required. Also becomes the index bullet text |
| `--tag <t>` | Repeatable |
| `--status <s>` | `draft`, `stable` or `deprecated` |
| `--source <s>` | Repeatable. `URL`, `id=URL`, or `id=URL=Title` |
| `--section <s>` | Index heading to file under. Defaults to `Orientation`; the section is created if absent |
| `--generated-by <a>` | Actor for `generated.by`, e.g. `process:kb-seed` |
| `--date <YYYY-MM-DD>` | Override today's date |

```bash
morphir kb add-concept --bundle morphir/morphir-ir-v3 --path naming.md \
  --type "Specification Section" --title Naming \
  --description "Name, Path, QName and FQName." \
  --tag morphir --tag ir --status stable --section "Identity and structure" \
  --source "ir-spec=https://github.com/finos/morphir/blob/<sha>/docs/spec/ir/morphir-ir-specification.md=Morphir IR Specification"
```

A concept whose path is in a subdirectory is filed in that subdirectory's `index.md` when one exists, otherwise in
the bundle root index.

The body is a stub with a `TODO` comment. Write it yourself — → [authoring.md](authoring.md).

---

## `sync …`

Mirrors an upstream repository into a bundle and projects edits back out. The *mechanism* — the manifest, the
lockfile, the fenced frontmatter block, the state model — is documented in [sync.md](sync.md); this is the flag
reference.

All four take these:

| Flag | Meaning |
| ---- | ------- |
| `--bundle <b>` | Bundle to sync. Defaults to the one whose root `index.md` declares `sync: true` |
| `--refs <path>` | Reference checkout root (default `<repo>/.refs`). The upstream checkout is `<refs>/<upstream.refs_path>` |

`pull` and `diff` fail with guidance when that checkout is absent, as does `push` unless `--to` names somewhere
else. `status` does not — it falls back to comparing the mirror against the lockfile alone.

### `sync status`

What has moved, here and upstream. Clean files are omitted unless you ask for them.

| Flag | Meaning |
| ---- | ------- |
| `--no-upstream` | Do not consult the upstream checkout — compare the mirror against the lockfile only |
| `--verbose` | List clean files too |
| `--strict` | Exit non-zero when anything is `diverged`, `unreadable`, or carrying a stale injected block |

A file whose `# kb:begin` block no longer matches `sync.yaml` is listed as `[injection stale]` whatever its state,
and is counted separately in the summary. That comparison needs no upstream checkout, so `--no-upstream` still makes
it.

```bash
morphir kb sync status
```

JSON gives `{files[{path, kind, state, detail, injectionStale}], summary{<state>: <count>}}`.

### `sync pull`

Imports upstream, re-injects any block the manifest no longer implies, rewrites `sync.lock.yaml`, then regenerates
the bundle index below the `<!-- kb:sources -->` marker. `base_commit` is the checkout's current HEAD.

Re-injection is reported under its own verb, `re-injected`, and is what makes a `type_map` edit take effect on files
that are already clean. It rewrites only the fenced region — keys added inside the fence by hand are kept, and the
bytes an export would send are unchanged.

| Flag | Meaning |
| ---- | ------- |
| `--dry-run` | Report what would change without writing anything — no files, no lockfile, no index |
| `--theirs` | Take upstream's version of files that changed on both sides. Without it, those are refused and listed |
| `--prune` | Delete mirrored files upstream has removed, and drop their lockfile entries |
| `--date <YYYY-MM-DD>` | Override today's date in `imported_at` and the generated index |

```bash
morphir kb sync pull --dry-run
```

```bash
morphir kb sync pull --theirs --prune
```

### `sync push`

Projects each locally-edited file back to its upstream form and writes it into a checkout. It writes files and
stops — branching, validating and opening a pull request are separate, explicit steps.

| Flag | Meaning |
| ---- | ------- |
| `--to <path>` | Checkout to write into (default: the reference checkout) |
| `--dry-run` | Report what would be written without writing anything |
| `--include-diverged` | Also export files that changed upstream since the last import |

Exits non-zero if any path was refused. Note that `push` compares the mirror against the lockfile only and never
reads upstream, so a file that moved on both sides presents to it as a local change and is exported regardless of
`--include-diverged`. Run `sync status` first when that distinction matters.

```bash
morphir kb sync push --dry-run
```

### `sync diff`

`git diff` between upstream's copy of a file and the **upstream form** of ours — the bytes an export would send,
with the kb frontmatter block removed.

| Flag | Meaning |
| ---- | ------- |
| `[<path>…]` | Mirrored paths or globs, relative to the mirror root. None means every mirrored file |
| `-` | Read the remaining patterns from stdin, one per line. May appear anywhere among the literal ones |
| `-z`, `--null` | Split what stdin holds on NUL rather than newline, to pair with `find -print0`. Only meaningful alongside `-` |
| `--json` | The comparison as a structured record rather than a diff |
| `--raw` | The patch alone, ready for `git apply`. Mutually exclusive with `--json` |
| `--path <p>` | One mirrored path (accepted for compatibility; prefer the positional form) |

Globs are the `sync.yaml` dialect, so `docs/**` means here what it means there. **Quote them** — an unquoted glob
is expanded by the shell against the working directory first, and mirrored paths rarely exist there, so it usually
survives untouched and occasionally does not.

One literal path prints what it always has: the diff, or `<path>: identical`. Anything else — no argument, a glob,
several patterns — prints one `=== <path> ===` section per differing file and then a tally.

```bash
morphir kb sync diff docs/spec/draft/types.md
```

```bash
morphir kb sync diff 'docs/**'
```

```bash
morphir kb sync diff --raw > /tmp/mirror.patch
```

```bash
find . -name '*.md' -print0 | morphir kb sync diff - -z
```

---

## `intent …`

Intent management. The *vocabulary* — states, kinds, obligations — is in [kb/CONTEXT.md](../../../../kb/CONTEXT.md)
and the Registers section of [kb/AGENTS.md](../../../../kb/AGENTS.md); this is the flag reference.

| Command | Flags |
| ------- | ----- |
| `intent init` | `--name` (default `intent`), `--system <purl>`, `--capability-bundle <label>`, `--stale-after-days` (default 60) |
| `intent new` | `--title`, `--description`, `--kind` (all required), `--breaking`, `--issue`, `--tag` |
| `intent list` (alias `ls`) | `--state`, `--kind`, `--breaking`, `--open`, `--user-visible` |
| `intent show <id>` | — |
| `intent check` | `--strict`, `--date` |
| `intent refine <id>` | — |
| `intent start <id>` | — |
| `intent move <id>` | `--state <State>` |
| `intent release <id>` | `--capability bundle:/path.md`, `--artifact <purl>` (repeatable) |
| `intent cancel <id>` | `--reason` |
| `intent supersede <id>` | `--by <id>` |

Kinds: `feature`, `bug`, `performance`, `security`, `deprecation`, `removal`, `refactor`, `docs`, `test`, `build`,
`spike`. `--breaking` marks a compatibility break — orthogonal to kind. `--open` lists only open intent, excluding
Released, Cancelled and Superseded.

Ids are positional — `morphir kb intent start 0007`, not `--id 0007`. All commands take `--json` and `--date`.

```bash
morphir kb intent new --title "WASM linking" --description "Link Scala.js output as a WASM module." --kind feature
```

```bash
morphir kb intent release 0007 --capability morphir/morphir-scala:/wasm-linking.md
```

The transition verbs refuse up front when the target state's obligation is unmet, rather than letting `check` catch
it later. Run `morphir kb refresh` afterwards to regenerate the intent index.

---

## `decision …`

Reads Decision Records. The register itself — frontmatter, checks, how to supersede — is documented in
[decisions.md](decisions.md); this is the flag reference.

| Command | Flags |
| ------- | ----- |
| `decision list` (alias `ls`) | `--state <State>`, `--in-force`, `--bundle <b>` |
| `decision show <id>` | `--bundle <b>`, `--body` |

`--in-force` lists only decisions that still govern, excluding Superseded and Withdrawn. Ids are positional and
accept `4`, `0004` or a `0004-slug` form; an id that matches records in more than one bundle fails, listing the
candidates, and `--bundle` narrows it. There is no `decision new` — use `add-concept --type "Decision Record"` and
hand-edit the register fields.

```bash
morphir kb decision list --in-force
```

```bash
morphir kb decision show 0004 --body
```
