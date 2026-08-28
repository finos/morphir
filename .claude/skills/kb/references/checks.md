# `morphir kb check` — Findings and Fixes

Two families. **Structural** checks ask whether the knowledge base obeys OKF and the conventions in
[kb/AGENTS.md](../../../../kb/AGENTS.md). **Provenance** checks ask whether commit-pinned sources still line up with
the reference checkouts under `.refs/`.

Everything is offline. Provenance runs `git` against local checkouts; it never reaches the network. If `.refs/` is
absent, provenance checks are skipped silently.

Exit code is non-zero when there is at least one error, or with `--strict`, at least one warning.

---

## Errors

| Check | Means | Fix |
| ----- | ----- | --- |
| `concept-missing-type` | A concept has no `type` — the one universally required OKF field | Add `type:`. Reuse a type already used in the bundle rather than coining a near-synonym |
| `concept-no-frontmatter` | A `.md` file inside a bundle has no frontmatter block at all | Add frontmatter, or move the file out of the bundle if it is not a concept |
| `frontmatter-invalid` | The YAML did not parse | Read the message; usually an unquoted `:` in a title or description, or a duplicate key |
| `subindex-has-frontmatter` | A non-root `index.md` carries frontmatter | Delete it. Only the bundle-root `index.md` has frontmatter |
| `link-broken` | A link target does not exist | Fix the path. Bundle-relative links start at the **bundle** root, not the kb root |
| `readme-in-bundle` | A `README.md` sits inside a bundle, where it parses as a concept | Move its content into `index.md`. `README.md` belongs to grouping directories |
| `stray-markdown` | A `.md` file under `bundles/` belongs to no bundle | Either its directory is missing `okf_version` in `index.md`, or the file is misplaced |
| `link-escapes-bundle` | A bundle-relative link climbs above the bundle root with `..` | Use an ordinary relative path to reach another bundle. Such a link often still resolves on disk — the filesystem collapses the `..` — so `link-broken` stays silent while the link means something other than it says |
| `decision-no-id` | A decision record's filename does not start with a numeric id | Rename it `NNNN-slug.md` |
| `decision-duplicate-id` | Two decision records in one bundle share an id | Renumber one. Ids are unique per bundle, not globally |
| `decision-state-unknown` | A decision record has no `state`, or one that is not recognized | One of `Proposed`, `Accepted`, `Superseded`, `Withdrawn` |
| `decision-superseded-no-successor` | `state: Superseded` with no `superseded_by` | Name the record that replaced it, or a reader has nowhere to go |
| `decision-superseded-unknown` | `superseded_by` names no record in the bundle | Fix the id |
| `decision-supersedes-unknown` | `supersedes` names no record in the bundle | Fix the id |
| `decision-withdrawn-no-reason` | `state: Withdrawn` with no `reason` | Say why. A withdrawal without a reason is worthless six months on |
| `intent-duplicate-id` | Two intent records share a numeric id prefix | Renumber one. Reported by `morphir kb intent check`; this check is new in the Rust port — the Scala tool lacks it |
| `sync-projection-broken` | A mirrored file cannot be reduced to its upstream form — its `# kb:begin` … `# kb:end` region is damaged | See below |
| `sync-lock-drift` | `sync.lock.yaml` lists a mirrored file that is not in the mirror | See below |
| `sync-manifest-invalid` | A bundle has a `sync.yaml` this tooling refuses — most often a `type_map` naming a type one of the registers owns | See below |

A broken link is an error here even though OKF treats dangling links as "not-yet-written knowledge" — because OKF is
describing *consumers*, and this is a producer-side linter. Nothing reading a bundle should fail on a dangling link;
a linter may still complain about one. Within a single repository a dangling link is nearly always a typo, and the
cost of the occasional false positive is lower than the cost of silent rot.

Where a knowledge base genuinely links forward to unwritten work, `morphir kb check --allow-dangling` downgrades it
to a warning. Otherwise, if you mean to point at something unwritten, say so in prose rather than linking.

---

## Warnings

| Check | Means | Fix |
| ----- | ----- | --- |
| `concept-missing-title` | No `title` | Add one. Consumers otherwise fall back to the filename |
| `concept-missing-description` | No `description` | Add one sentence. Index generators and search snippets read it |
| `concept-not-indexed` | A concept is not linked from any index in its bundle | Add the suggested bullet to an index |
| `index-description-drift` | An index bullet's text differs from the target concept's `description` | Make them match. The hint prints what the concept says |
| `status-unknown` | `status` is not `draft`, `stable` or `deprecated` | Use one of those, or drop the field |
| `stale-after-passed` | `stale_after` is in the past | Re-read the source, refresh the content, and push the date out — or drop the field if the content has settled |
| `duplicate-title` | Two concepts in a bundle share a title | Retitle one. Duplicate titles make search results ambiguous |
| `figure-caption-missing` | A Mermaid figure or standalone image has no `**Figure N:** …` caption paragraph after it | Add one, per the `diagrams.md` style card — a reader should know why the figure is there without decoding it |
| `figure-number-out-of-sequence` | Figure captions are not numbered 1..N in document order | Renumber them in document order |
| `source-commit-drift` | A source is pinned at one commit but the `.refs/` checkout is at another | See below |
| `source-path-missing` | A pinned source path no longer exists at the checkout's HEAD | The file moved or was deleted upstream. The pinned URL still resolves on GitHub |
| `decision-decided-missing` | A decision record has no valid `decided` date | Add `decided: YYYY-MM-DD`. Without it the records cannot be read in sequence |
| `decision-supersede-not-mutual` | A supersession link points only one way — either a record supersedes another that does not name it in `superseded_by`, or a record names a successor that does not list it in `supersedes` | Write both halves. One-way supersession is how a chain silently breaks — the old record still reads as current |
| `link-broken-upstream` | A link in a **mirrored** document does not resolve | Upstream's own link rot. Fix it upstream and export, or leave it |
| `sync-untracked` | Upstream has a file a manifest mapping selects, and `sync.lock.yaml` does not list it | `morphir kb sync pull` imports it |
| `sync-upstream-drift` | Upstream has moved on since the last import, and the local copy has no edits | `morphir kb sync pull` takes it. Nothing here is lost — that is what "no edits" means |
| `sync-diverged` | A mirrored file changed both here and upstream since the last import | Reconcile by hand; `morphir kb sync diff <path>` shows both sides. `morphir kb sync pull --theirs` discards the local side |
| `sync-deleted-upstream` | A mirrored file is no longer present upstream | `morphir kb sync pull --prune` removes it here too, if that is what you want |
| `sync-deleted-upstream-edited` | Gone upstream, but carrying local edits — an **error**, because the edit is unrecoverable if discarded | Restore the file upstream and export, or revert the edit. Nothing prunes or overwrites it in the meantime. |
| `sync-injection-stale` | A mirrored file's `# kb:begin` block does not say what `sync.yaml` now implies — usually a `type_map` edit that was never applied | `morphir kb sync pull` rewrites the block in place. Keys you added inside the fence are kept |

### On `index-description-drift`

This is the check that fires most, and it is worth understanding rather than suppressing. An index is a
progressive-disclosure surface: a reader decides whether to open a concept based on the bullet. When the bullet and
the concept's own `description` say different things, one of them is stale — and there is no way to tell which from
the outside. Keeping them identical makes the index mechanically derivable and the drift detectable.

Comparison is lenient about case, surrounding whitespace and a trailing full stop. It is not lenient about wording.

### On `source-commit-drift`

Drift is **not** automatically a problem. A concept records what a source said at a particular commit; that remains
true even after the source moves on. Drift means "the upstream has changed since this was written", which is a prompt
to check whether the change affects the concept — not an instruction to rewrite it.

Two legitimate responses:

- Re-read the source at the new HEAD and update the concept, re-pinning to the new commit.
- Leave the pin alone and accept it as historical, if the concept is explicitly about what the source said then.

### On the `sync-*` checks

These run for every bundle carrying a `sync.yaml` — → [sync.md](sync.md) for the mechanism. They take the same
stance as `source-commit-drift`, for the same reason: drift is a prompt, not a failure. A mirror that has moved
apart from upstream is the normal state of anything being worked on, and the tooling's job is to tell you *which
way* it moved, not to insist you reconcile it now.

Two are errors because they are the states in which an export would send the wrong bytes, and a third because it is a
manifest no command will accept:

- **`sync-projection-broken`.** The `# kb:begin` … `# kb:end` region is the only part of a mirrored file the
  knowledge base owns, and removing exactly that region is what recovers upstream's bytes. When the fence is
  damaged — unmatched, or closing before it opens — that removal cannot be trusted, so it is refused rather than
  guessed at. Restore the fence by hand, or re-run `morphir kb sync pull --theirs` for the bundle to take upstream's
  copy and re-inject. Any local edit to that file is lost by the second route, so check
  `morphir kb sync diff <path>` first.
- **`sync-lock-drift`.** The lockfile names a file the mirror does not have, so the two disagree about what is
  vendored. `morphir kb sync pull` restores it from upstream. If upstream dropped the file deliberately,
  `morphir kb sync pull --prune` removes the entry instead.
- **`sync-manifest-invalid`.** The manifest itself is refused, so no sync command will run — this finding is how you
  see that from `morphir kb check` rather than only from `morphir kb sync`. The usual cause is a `type_map` entry
  naming a type a register discovers by, such as `Decision Record`: a mirrored document injected with one is pulled
  into that register and judged against a schema it was never written to. Type a mirrored file by what it *is* —
  `Decision Source` — and → [sync.md](sync.md#type_map-may-not-name-a-register-owned-type) for why the constraint is
  general.

`sync-injection-stale` also fires without a checkout: it compares the file on disk against what the manifest implies,
which needs nothing from upstream. That is the point — a `type_map` edit that was never applied is otherwise invisible,
because status compares projected forms and the injected block is stripped before the comparison.

Without a reference checkout under `.refs/` — or with `--no-provenance` — only those four can fire. The other four
are all comparisons against upstream, and there is nothing to compare against.

Mirrored documents are also held to a *looser* structural standard than authored ones, because their frontmatter
belongs to upstream. `concept-missing-title`, `concept-missing-description`, `status-unknown`, `stale-after-passed`,
`duplicate-title` and `frontmatter-unknown-key` are all suppressed for them; demanding OKF's vocabulary of somebody
else's Docusaurus keys would bury the findings that are actually yours to fix. `concept-missing-type` still applies,
with a different message: `morphir kb sync pull` injects `type`, so its absence means the injection failed.

What is *not* relaxed is `concept-not-indexed`. Mirrored concepts must still be reachable from an index, which is
why `morphir kb sync pull` regenerates the bundle index below its `<!-- kb:sources -->` marker.

---

## Info

| Check | Means |
| ----- | ----- |
| `frontmatter-unknown-key` | A frontmatter key recognized by neither OKF v0.2 nor this tooling. Keys this tooling defines — the intent and decision registers' — are known and are not reported; anything else is a heads-up, not a complaint |
| `source-ref-missing` | No reference checkout exists for a pinned GitHub source, so it could not be verified. Clone the repository under `.refs/<org>/<repo>` |

Info findings are hidden unless you pass `--verbose`.

---

## What `check` cannot do

It finds *mechanical* inconsistency. It cannot tell you that two concepts assert contradictory things, that a concept
is misleading, or that a bundle is missing knowledge it ought to have. Those need reading.

→ [divergence.md](divergence.md)
