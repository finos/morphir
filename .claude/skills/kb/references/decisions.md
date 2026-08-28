# `morphir kb decision` — Decision Records

A **Decision Record** is an architectural decision recorded as prose: what was decided, which alternatives were
rejected, and under what condition it should be revisited. It is the knowledge base's third register.

| Register | Tense | Lifecycle | Answers |
| -------- | ----- | --------- | ------- |
| Intent | future | yes | should we do this |
| Capability | present | no | what does the system do |
| **Decision Record** | past | terminal only | why is it shaped this way |

**Records are immutable once published.** After a record reaches the trunk, it is superseded by a later record
rather than edited. That is the whole point: its value is the reasoning that was available at the time, which an
edit destroys. A record still on its authoring branch is a draft, and amending it there is ordinary drafting, not a
violation. Immutability is also what separates a Decision Record from a **Design Note** — a Design Note is *meant*
to be updated as understanding improves.

The reasoning for the register itself is recorded where these conventions were first worked out, in the
morphir-scala knowledge base
(`ecosystem/morphir-scala/kb/bundles/morphir/morphir-scala/decisions/0004-decision-records-are-a-third-register.md`).

---

## Where they live

Anywhere. A decision record is any concept with `type: Decision Record`; there is no bundle marker and no
configuration. The convention is a `decisions/` directory inside the bundle that owns the subject area.

Ids come from the filename prefix — `0004-bridge-nothing.md` is decision `0004` — so the id and the file can never
disagree. **Ids are unique per bundle, not globally**; two bundles may each start at 0001.

## Frontmatter

```yaml
---
type: Decision Record          # required — this is what makes it a decision record
title: Bridge nothing between ZIO and Kyo
description: "One sentence, mirrored into the index."
state: Accepted                # Proposed | Accepted | Superseded | Withdrawn
decided: 2026-07-29            # YYYY-MM-DD
supersedes: ["0002"]           # optional
superseded_by: "0009"          # required when state is Superseded
reason: "…"                    # required when state is Withdrawn
tags: [kyo, architecture]
status: stable                 # OKF document maturity — unrelated to `state`
---
```

`state` and `status` are different axes and both are checked. `state` is where the decision sits; `status` is OKF's
document maturity (`draft`, `stable`, `deprecated`). A Superseded decision may perfectly well still be a `stable`
document.

`supersedes` accepts `4`, `0004` or `0004-some-slug` — all normalize to `0004`.

## Commands

```bash
morphir kb decision list                  # all records, grouped by state
morphir kb decision list --in-force       # excludes Superseded and Withdrawn
morphir kb decision list --state Accepted
morphir kb decision list --bundle morphir-scala
morphir kb decision list --json

morphir kb decision show 0005             # id, slug, or bare number
morphir kb decision show 0005 --body
morphir kb decision show 0005 --json
morphir kb decision show 0001 --bundle morphir-scala
```

Ids are unique within a bundle, not across the knowledge base, so `0001` may name a record in more than one. When it
does, `show` lists the candidates and exits non-zero rather than picking one; `--bundle` narrows it.

There is no `morphir kb decision new`. Use `morphir kb add-concept`, which already handles the file, the frontmatter
and the index entry:

```bash
morphir kb add-concept \
  --bundle morphir/morphir-scala \
  --path decisions/0011-some-decision.md \
  --type "Decision Record" \
  --title "Some decision" \
  --description "One sentence." \
  --section "Runtime and code model"
```

Then add `state`, `decided` and any supersession links by hand — `add-concept` writes OKF fields only.

## Shape of a record

A record opens with the title and the decision statement itself, stated plainly. If the decision is a table (which
stage takes a parameter, which option a policy picks), the table belongs in that opening, because the table *is*
the decision.

Right after the opening, before `## Why`, add a `## Summary` section:

1. One short paragraph giving the reasoning in brief.
2. A table with columns `Option`, `Outcome`, `Why`. `Outcome` is `Chosen` or `Rejected`. `Why` is one clause, not a
   restatement of the full argument. Every option named anywhere in the record's prose gets a row, including the
   chosen one.

The rest of the record follows as before: `## Why` argues the decision at full length, `## Consequences` states
what changed, `## Revisit when` gives the condition that reopens it.

`## Alternatives rejected` keeps its prose but gets one heading per alternative, `### <alternative>`, so a reader
can jump to one directly. The summary table already gives the one-line view, so the section itself needs no lead-in
paragraph before the first heading.

The morphir-scala knowledge base holds the worked examples: its decision 0016
(`ecosystem/morphir-scala/kb/bundles/morphir/morphir-scala/decisions/0016-the-markdown-parser-is-our-own.md`) shows
a short decision statement, a `## Summary` with a three-row options table, then `## Why`, an
`## Alternatives rejected` section with one `###` heading per alternative, `## Consequences`, and `## Revisit when`.
Its decision 0015 shows the same shape where the opening decision statement is itself a table.

## Checks

Run as part of `morphir kb check`. See [checks.md](./checks.md) for the full catalogue.

| Check | Severity | Means |
| ----- | -------- | ----- |
| `decision-no-id` | error | Filename does not start with a numeric id |
| `decision-duplicate-id` | error | Two records in one bundle share an id |
| `decision-state-unknown` | error | `state` missing or not one of the four |
| `decision-superseded-no-successor` | error | `state: Superseded` with no `superseded_by` |
| `decision-superseded-unknown` | error | `superseded_by` names no record in the bundle |
| `decision-supersedes-unknown` | error | `supersedes` names no record in the bundle |
| `decision-withdrawn-no-reason` | error | `state: Withdrawn` with no `reason` |
| `decision-decided-missing` | warn | No valid `decided` date |
| `decision-supersede-not-mutual` | warn | A supersedes B, but B does not name A in `superseded_by` — or B names A in `superseded_by` and A does not list B in `supersedes` |

None of them run on a **mirrored** record. An ADR imported from an upstream repository keeps upstream's conventions —
`ADR-0001-…` for a filename, status and date in the body — and holding it to this register's schema would report four
errors per file that nobody here can fix. It still lists.

The mutuality check is the one that earns its keep, and it runs in both directions. One-way supersession is how a
chain silently breaks: the superseded record still reads as current to anyone who lands on it directly, and nothing
says otherwise.

## Superseding a record

There is no command for it — supersession is two edits and a new document, and doing it by hand keeps the reasoning
in the author's head where it belongs.

1. Write the new record, with `supersedes: ["NNNN"]`.
2. On the old record, set `state: Superseded` and `superseded_by: "MMMM"`.
3. Leave the old record's body alone. Do not "fix" it to match the new conclusion — the stale reasoning is the
   artifact.
4. Run `morphir kb check`; `decision-supersede-not-mutual` catches step 2 if you forget it.
