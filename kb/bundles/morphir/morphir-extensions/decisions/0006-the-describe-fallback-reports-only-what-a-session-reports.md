---
type: Decision Record
title: The describe fallback reports only what a session reports
state: Accepted
decided: 2026-09-23
tags: [extensions, capabilities, mep, protocol, compatibility]
status: stable
description: A refusal before initialize has its own MEP error code, -32014, and a statement the host builds from a fallback session holds only what that session reports, with no requires or critical members.
sources:
  - id: spec
    resource: https://github.com/finos/morphir/discussions/921
    title: "finos/morphir#921: capability statements across the extension lifecycle (working spec)"
  - id: describe-pr
    resource: https://github.com/finos/morphir-rust/pull/223
    title: "finos/morphir-rust#223: morphir.extension.describe with a session fallback"
---

# The describe fallback reports only what a session reports

A guest refuses a request that is not allowed before `morphir.initialize`, or after `morphir.shutdown`,
with the MEP error code `-32014` (not initialized). A host falls back to a session when `describe` fails
with `-32601` or `-32014`. The statement it builds from that session holds only what the session reports:
the identity, the one negotiated protocol version and the capabilities, with no `requires` and no
`critical` members. The result records that it came from the fallback.

This decision refines decision 9 of
[Readers ignore unknown members unless critical](/decisions/0004-readers-ignore-unknown-members-unless-critical.md).
Decision 9 still holds: `describe` is optional, and a host falls back to a session. It does not supersede
0004.

## Summary

Implementing `describe` (source `describe-pr`) found two gaps. First, the MEP draft said a host falls back
when a guest refuses a request "because it came before `initialize`", but assigned that refusal no
error code. A host could only recognize it by matching phrases in the error message. Second, decision
0004 said the host "reads the same information from that session". A session cannot report
`requires` or `critical`, and it reports one negotiated protocol version, not the list a statement
carries. The protocol draft already said the rebuilt statement has less. Decision 0004 said "the same".

| Option | Outcome | Why |
| --- | --- | --- |
| Assign `-32014` and keep message matching only for guests released before it | Chosen | Hosts decide on a code, and released guests still fall back |
| Match refusal messages only | Rejected | The check is fragile, and it can mistake an unrelated error for a lifecycle refusal |
| Reuse `-32600` (invalid request) for the refusal | Rejected | `-32600` also means a malformed request, which must not trigger a fallback |
| A fallback statement holds only what the session reports | Chosen | The host states nothing the guest did not report |
| A fallback statement is treated as equal to a statement from `describe` | Rejected | It would claim `requires` and `critical` answers the session never gave |

## Why

A fallback exists so that released guests keep working. The host must recognize the refusal reliably,
and the result must not claim more than the guest said. A code does the first job. `-32014` is the next
free code after the MEP server errors `-32010` to `-32013`. `-32600` is not suitable, because a host
that fell back on every `-32600` would also fall back on a malformed request. Guests released before
the code exist, so a host may still recognize their refusal messages. It falls back on no other error.

For the second job, the statement records where it came from. A statement from `describe` is the
guest's own. A statement from a session is the part the session reported. The protocol draft already
limits a rebuilt statement to the negotiated protocol with no `requires` or `critical`. This decision
brings the kb record into line with it.

## Consequences

- The MEP draft lists `-32014` (not initialized) with the other server errors. The lifecycle section
  tells an extension to use it before initialization and after shutdown.
- The Rust SDK defines `error_codes::NOT_INITIALIZED`. The daemon's `describe` falls back on `-32601`
  and `-32014`, and also on the refusal messages of guests released before the code.
- A `ProcessDescription` records its source, `Describe` or `SessionFallback`. A later install probe
  that stores a statement keeps that source visible.

## Revisit when

Revisit the message matching once every first-party guest answers `-32014`, and remove it when no
supported released guest depends on it.
