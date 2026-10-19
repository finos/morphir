---
name: project-management
description: Use when reporting initiative, campaign, epic, milestone, or portfolio progress; reviewing priorities, blockers, or ready work; or organizing and maintaining tracked work in beads, GitHub Issues, or other issue trackers. Includes progress bars, ratios, and percentages. Not for implementing the underlying feature or merely explaining project-management terminology.
---

# Project management

Make tracked work understandable and actionable. Show what is complete, what remains, and what can move next, with evidence behind every total.

## Use in any coding agent

Use the host agent's file, terminal, and connector tools. Read relative references from this skill's directory,
and run tracker commands in the target project's workspace. No particular model, personal skill directory,
or vendor tool name is required. `agents/openai.yaml` supplies optional Codex display metadata; the workflow
is fully defined in this file and `references/`. If a companion skill is unavailable, use the repository's
instructions and the bundled tracker reference. Access and authorization follow the host and the user's request.

## Choose the scope and mode

Infer the initiative and repositories from the request and current context. Read applicable repository instructions and tracker configuration. Use existing labels, parents, milestones, Projects, or explicit issue lists as the scope. Ask only when materially different scopes remain plausible; continue useful independent reads.

- **Report or recommend:** read the trackers and produce the report. Recommendations do not change priorities, ownership, or status.
- **Organize or maintain:** make the tracker changes authorized by the request and existing instructions. Read [work-management.md](references/work-management.md).

Use the beads skill when available for beads-specific lifecycle and synchronization rules. Read [trackers.md](references/trackers.md) for collection from beads, GitHub, and mixed sources. Adapt to installed tools; a connector or exported snapshot can substitute for a CLI.

## Establish the evidence

Collect open and closed work, parent relationships, completion reasons, priorities, dependencies, and relevant delivery evidence. Record the scope, retrieval time, freshness, source authority, and whether pagination and dependency retrieval completed. An unavailable tracker is missing coverage, not an empty backlog.

Normalize one record per distinct deliverable. Deduplicate explicit mirrors; preserve their links. Parent epics, implementation PRs, and their child tasks serve different purposes and must not inflate the same denominator. Resolve conflicting states using documented source authority; disclose unresolved conflicts.

Read [reporting.md](references/reporting.md) before calculating progress. Its rules cover cancellation, unknown state, partial retrieval, dependency readiness, scope changes, and aggregation. Use tools for nontrivial arithmetic. Verify totals reconcile before writing the report.

## Produce the report

Lead with the main finding, snapshot date, and scope. Default to these elements, sized to the request:

1. Overall completion bar, completed/total ratio, percentage, and counting basis. Include active, ready, waiting, and unknown counts when useful.
2. A workstream or epic table with **Priority | Bead / issue | Work | Progress | Short summary**. Show task rows for a small backlog. Parent progress uses its counted descendants.
3. Recent completions with issue and delivery links, when change history supports "recent."
4. A short prioritized next-work table with IDs, readiness, and the concrete reason each action matters. Separate continuing active work from starting ready tasks and resolving blockers.
5. Material gaps or changes in scope, placed near the affected figures.

Use brief summaries of outcomes or blockers. Expand IDs when shorthand would be ambiguous. Show unknown priority as unknown. Keep effort, test coverage, and elapsed time separate from task completion.

For a saved report, follow the repository's format and location rules, including HTML templates when required. Return a link to the artifact and a concise summary. Publish reports or send notifications only when explicitly authorized.

## Finish with an accurate handoff

For mutations, re-read changed records, verify dependencies, and perform required tracker synchronization. Report actual changes, IDs, and any partial failures. Reuse existing authorization; this skill adds no blanket approval step. A reporting request alone does not authorize tracker edits, assignments, closures, or posting comments.
