# Reporting and measurement

## Normalize the work

Keep a small working dataset. Useful fields are canonical ID, source links, title, initiative/workstream, parent, kind, raw state, completion reason, normalized state, priority, owner, dependencies, readiness evidence, updated time, and delivery evidence. Preserve unknown values. This is a working representation, not a requirement to create a new database.

Choose the counting unit explicitly. Default to distinct deliverable leaf tasks, including bugs, chores, or features that play that role. If the request is specifically about `--type task`, use that scope and name it. A parent with its own independent deliverable needs a separately identified work item before it can count alongside its children.

Deduplicate using explicit mirror links, stable external references, or documented mappings. Similar titles alone are insufficient. A linked PR provides evidence; it is not automatically a mirror or another task. A merged PR does not complete unfinished acceptance criteria. Use documented tracker authority for mirrored state, and retain conflicts in the report. If authority is unresolved, classify completion as unknown and disclose it.

## Define the denominator

Default delivery progress is:

`completed distinct tasks / current committed distinct tasks`

Current committed scope includes completed, active, ready, waiting, deferred-but-still-committed, and unknown tasks. Identify the actual commitment boundary. If only a label or backlog query defines scope, call it "tracked scope" rather than inventing a commitment.

Cancelled, withdrawn, duplicate, and superseded records are not delivered work. List their dispositions separately and exclude them from the delivery denominator when they have left scope. If a duplicate points to a canonical task, count that task once. A closed issue with an unavailable or ambiguous reason needs follow-up; do not silently treat it as delivery. If the repository explicitly uses all closures as an administrative metric, label that separately from delivered work.

All counted tasks must fit exactly one reporting bucket:

| Bucket | Evidence |
|---|---|
| Completed | Authoritative completed disposition; surface contradictory acceptance evidence |
| Active | Work underway, with no known blocker currently stopping it |
| Ready | Not started, eligible now, and dependencies and scheduling constraints checked |
| Waiting | Known blocker or documented deferral; state the reason |
| Unknown | State conflict, missing dependency coverage, or insufficient readiness evidence |

Retain raw tracker state. If an in-progress task is blocked, count it once as waiting and describe it as "in progress, blocked." Absence from a ready list does not by itself prove a dependency blocker. Open is not synonymous with ready. Missing dependency fields are not empty dependency lists.

## Compute and verify

- Percentage = `100 * completed / total`, usually one decimal place. For zero tasks, show `0/0 · N/A` and "no scoped tasks."
- A ten-cell bar uses `floor(10 * completed / total)` filled cells. `██░░░░░░░░ 2/10 · 20.0%`. The exact ratio carries the precision. Never show a full bar before 100%.
- Individual tasks have binary completion unless an agreed, evidenced milestone or estimate model exists. Do not invent 50% for "in progress."
- Sum bucket counts and verify they equal the denominator. Explain any separate withdrawn count.
- Portfolio progress uses the union of canonical tasks. Do not average epic percentages or count shared tasks twice. Disclose overlapping workstreams when their row totals cannot be added.
- Report epic closures separately from child delivery progress. A closed epic with open descendants is a discrepancy, not permission to mark the children complete.
- These percentages measure task counts, not engineering effort, feature coverage, or schedule confidence. Add effort-weighted progress only with consistent estimates and explicit missing-estimate coverage.

## Partial data and trends

Check pagination, query limits, repository coverage, nested child/dependency pages, authentication failures, and source timestamps. When scope retrieval is incomplete, show only "observed records: x/y completed" with an explicitly scoped bar, or omit the percentage. Overall completion remains unknown. Do not rank initiatives by completion when one denominator is missing. Readiness can remain unknown even when issue enumeration is complete.

Distinguish retrieval time from source update time. A newly read stale export is still stale. For mixed snapshots, disclose meaningful timing differences.

Compare snapshots only when their scope and counting rules are compatible. Report additions, removals, completions, and reopenings separately. For example, moving from `1/4 · 25%` to `1/5 · 20%` after one task is added means scope grew; no completed work was lost. Without a prior snapshot or event history, say "completed work," not "completed since last update." Do not infer velocity or delivery dates from one snapshot.

## Choose next work

Honor explicit priorities, urgency, current ownership, and constraints. Within those, favor finishing active work and ready tasks that remove real dependencies. Show priority as stored; use a documented mapping before comparing different trackers' scales.

Keep three kinds of action distinct: finish active work, start a confirmed ready task, and resolve a blocker or missing fact. A high-priority blocked task can warrant an unblock action but is not a ready implementation task.

For "unlocks N tasks," simulate resolving the candidate: count distinct unfinished tasks whose remaining blockers would all clear, including scheduling constraints. Distinguish this from direct dependent count or transitive reach. Incomplete graphs permit only a qualified estimate. No graph means no invented unlock count.

## Report shape

Use this compact form as a guide, adapting the rows to the initiative:

> As of DATE, INITIATIVE has completed 2/10 tracked tasks, 20.0%.
>
> `██░░░░░░░░ 2/10 · 20.0%`
>
> Counts: 2 complete, 1 active, 3 ready, 3 waiting, 1 unknown. One withdrawn task is excluded. Progress measures task counts.

| Priority | Bead / issue | Work | Progress | Short summary |
|---|---|---|---|---|
| P1 | Parent ID or link | Core contracts | `█████░░░░░ 2/4 · 50%` | Parser contract complete; codec acceptance remains |
| P2 | Parent ID or link | Tooling | `░░░░░░░░░░ 0/6 · 0%` | Three ready tasks; one dependency needs verification |

| Priority | Bead / issue | Next work | State | Why now |
|---|---|---|---|---|
| P1 | Task ID or link | Finish codec acceptance | Active | Clears the generator's only remaining dependency |
| P2 | Task ID or link | Add examples | Ready | Contract dependency is complete |

Link completed work to closure evidence and PRs where available. Attribute recorded test results to that evidence; only say you verified tests if you actually ran them. Prefer a few useful rows over dumping the backlog. For large initiatives, group by workstream and state how many items were omitted; save a full report only when requested or useful under repository conventions.
