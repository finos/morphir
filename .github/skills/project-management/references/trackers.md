# Collecting tracker evidence

Read repository instructions before choosing the tracker or synchronizing it. Use existing authentication and installed tools. Never print credentials. Check local CLI help or available connector schemas for supported fields and flags; versions and permissions vary.

## Beads

Use the beads skill if available. Identify the configured database, which may be shared across repositories. Check its location before running commands that could initialize a new database. Follow the repository's bootstrap and sync workflow. Refresh before reporting when configured; a failed refresh means the snapshot may be stale. Reporting does not require a push when nothing changed.

Typical read commands, with example selectors to replace:

```bash
bd list --label campaign:example --all --limit 0 --json
bd ready --label campaign:example --type task --limit 0 --json
bd show BEAD_ID --json
```

`list` supplies the denominator; `ready` supplies readiness evidence. A ready-only query cannot measure overall completion. Match type filters to the chosen counting unit. In the installed CLI, list defaults to a limited number of rows and `--limit 0` removes that limit; verify with local help on another installation.

Collect full issue details when closure reasons, dependencies, notes, or acceptance evidence matter. Distinguish parent-child, related, and blocking edges. Do not infer hierarchy from ID punctuation alone. Label queries can miss unlabeled descendants: reconcile against actual parent membership and disclose whether the chosen scope is the label, the descendant set, or their union.

For a repository slice of an ecosystem campaign, show its own denominator. Keep external blockers visible without counting their work as part of that repository. Reconcile the slice with the broader initiative when requested.

## GitHub Issues and Projects

Identify the host, repository set, and scope selector. A label, milestone, parent issue, and Project can define different populations. Record which one is authoritative. Use connectors when available, or `gh` with existing authentication.

For an initial bounded fetch:

```bash
gh issue list --repo OWNER/REPO --state all --label initiative:example --limit 1000 \
  --json number,url,title,state,stateReason,labels,assignees,milestone,updatedAt,closedAt
```

The limit is a cap, not proof of completeness. Verify enumeration using API pagination or a reliable total and account for search result ceilings. Use local `gh api --help` for pagination mechanics. GraphQL nested collections, including children and dependencies, require their own pagination; fetching every top-level page does not guarantee those are complete. If completeness cannot be established, label the report partial.

Fetch parent/sub-issue relationships, blocking relationships, Project fields, bodies, or closure events when needed and supported. Missing fields can reflect permissions or API limitations. Do not interpret them as no relationships. When using repository REST issue listings, filter out pull request records before counting issues.

Preserve `stateReason`: a closed `NOT_PLANNED` issue is not a completed deliverable. If the reason is missing, inspect closure evidence or report ambiguity. A Project "Done" field and an open issue can disagree. Use the team's workflow policy to decide authority; otherwise surface the conflict. A Project draft item is not necessarily a GitHub Issue, and an archived item is not necessarily complete.

Priority may come from labels or Project fields. Keep an unknown value when no mapping exists. Assignment alone does not mean work has started. Readiness requires the team's explicit ready state or verified dependencies and eligibility; ordinary GitHub open state supplies neither.

## Mixed and other sources

Build the canonical work list before aggregating. Maintain explicit mirror mappings and use the designated authority per field if needed, for example beads for workflow and GitHub for PR evidence. Synchronizing two trackers is a separate authorized change, not an automatic consequence of finding disagreement.

For another tracker or an export, map identity, scope, hierarchy, state/reason, priority, dependencies, and evidence into the same reporting rules. Preserve provenance and unknowns. Do not require users to migrate systems to receive a report.

Keep a compact snapshot outside committed source files unless repository conventions say otherwise. Record selectors, source times, coverage, canonical IDs, state mappings, and totals if a later comparison is needed. Respect private tracker data in saved artifacts and publish only to authorized destinations.
