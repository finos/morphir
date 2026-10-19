# Organizing and maintaining work

## Match the requested action

"Report," "what's ready," and "recommend priorities" authorize reads and recommendations. "Create tasks," "reorganize this epic," or "update these issues" authorize the corresponding tracker changes within the stated scope. Use existing authorization without repeatedly asking. This skill itself does not authorize posting reports, messaging people, assigning other people, merging, or releasing.

Before writes, discover repository rules, tracker authority, existing issue conventions, and matching work. Search open and closed items by labels, parent, external references, and intent. Reuse or update existing items where appropriate. Similar titles need inspection, not automatic deduplication.

## Decompose an initiative

Use epics for distinct outcomes or workstreams and leaf tasks for independently verifiable deliverables. Each task should contain:

- A concrete result and bounded scope.
- Acceptance criteria and the evidence that will establish completion.
- The owning repository or component, relevant spec links, and source requirements.
- Priority using the existing scale, proposed explicitly if not yet agreed.
- Real blockers with the artifact or decision each dependency supplies.

Add estimates, owners, and dates only when supported by the request or existing commitments. Represent uncertainty as a research or decision task with a specific output instead of inventing an implementation estimate.

To support parallel work, isolate shared contracts into small enabling tasks. Give downstream tasks stable inputs, fixtures, or an agreed interface so they can proceed independently where feasible. Parent-child membership does not imply a blocking dependency. Avoid making every task depend on a whole epic or on unrelated workstreams. Check for cycles and accidental serialization.

Name proposed workstreams, each task's handoff, and the initial ready set. Shared files, unsettled interfaces, and scarce reviewers can constrain parallelism even when the tracker graph is clear. Report those constraints without fabricating dependency edges.

## Apply changes and verify

Perform dependent writes sequentially: create or identify the parent, create missing children, then add links using returned IDs. Read installed tool help or connector schemas before mutation. Use structured text fields or body files so descriptions retain their intended newlines and literal content.

Use labels and external references consistently so the next report can reconstruct scope. Preserve provenance when moving work between systems. Link mirrors deliberately; do not create a second authoritative copy by accident.

For reprioritization, keep recommendations distinct from applied values. For closing work, check acceptance evidence and use the correct completion or withdrawal reason. For duplicates, preserve the canonical reference. A related merged PR is insufficient when acceptance work remains.

Re-read changed records and dependency links. Recompute readiness after graph changes. Follow configured synchronization, including a beads push after issue changes where required. If some writes or synchronization fail, report exactly what succeeded and what remains; inspect existing IDs before retrying to avoid duplicate creation.

Finish with a compact change summary, issue links or bead IDs, and the newly ready tasks. Leave a durable handoff in the authorized tracker or local artifact when the task calls for it. Avoid creating an extra tracking system merely to track the tracker.
