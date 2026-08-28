# Detecting Content Divergence

`morphir kb check` finds mechanical inconsistency — broken links, missing fields, index drift, stale pins. It cannot
find the kind of divergence that actually degrades a knowledge base: two concepts that assert incompatible things, or
a concept that no longer matches the source it claims to summarize.

That needs reading. This is the procedure.

## Start from the mechanical signal

`check` narrows where to look even though it cannot judge content.

```bash
morphir kb check --verbose --json
```

| Finding | What it suggests reading |
| ------- | ------------------------ |
| `source-commit-drift` | The source moved. Diff it against what the concept claims |
| `source-path-missing` | The source was moved or deleted. The concept may describe something that no longer exists |
| `stale-after-passed` | The author expected churn by now. Assume the content is suspect until re-read |
| `index-description-drift` | Someone edited one of the two and not the other — often a sign of a half-finished revision nearby |

## Diff a concept against its source

For each concept with drift, compare the pinned commit to the checkout's HEAD:

```bash
morphir kb show --path /naming.md --bundle morphir-ir-v3 --json | jq -r '.sources[]'
```

```bash
git -C .refs/finos/morphir-elm diff <pinned-sha>..HEAD -- docs/morphir-ir.md
```

For a source in this repository, drop the `-C` and diff against the working tree directly. An empty diff means the
pin is merely old, not wrong — re-pin and move on. A non-empty diff needs reading against the concept's claims.

## Find cross-concept contradictions

There is no command for this; it is a reading task, and these are the shapes worth looking for.

**The same subject in two bundles.** A concept in a specification bundle and one in an implementation bundle
describing the same construct are the most likely pair to drift apart.

```bash
morphir kb search --query "format version"
```

**The same `type` across bundles.** Concepts sharing a type usually make the same *kind* of claim, which makes
conflicting claims easier to spot.

```bash
morphir kb search --type "Specification Section" --json | jq -r '.results[] | "\(.bundle)\(.path)  \(.description)"'
```

**Version-pair claims.** Anywhere one concept says "unchanged in vN" and another documents a change.

**Divergence notes that have gone stale.** A recorded divergence is a claim with a shelf life — the upstream may have
reconciled it since.

```bash
morphir kb search --query divergence --body
```

## What to do with what you find

**Record it; do not silently reconcile it.** If two sources genuinely disagree, that disagreement *is* knowledge, and
flattening it destroys information. Write it into the relevant concept with both positions and, if there is one, the
tiebreak.

**Say which source is authoritative.** Often the rule already exists — for Morphir material, this repository's
`docs/` is authoritative for the specification and `finos/morphir-elm` for how IR v3 actually behaves. A group's
`README.md` records constraints like these.

**Do not let an implementation rewrite a specification concept, or vice versa.** When the code and the spec disagree,
that is a finding about the project, not an error in the knowledge base.

**Log it.** A divergence discovered and recorded is an `**Update**` entry in the bundle's `log.md`.

## After reconciling

```bash
morphir kb check
```

Re-pin any sources you re-read, so the next drift report starts from where you actually looked.
