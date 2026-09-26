# Ion case exchange, 2026-09-26

`values-0023-rust.ndjson` is an append-only capture of the native MCK runner's
`^values-0023$` selection against the Rust adapter at
`b87dc0d210a5695a10f9b2d55b2cf6e10876eb78`. It contains the v2
capabilities exchange, six decode requests and responses, and exit. The run
reported six passes, no failures, kit errors or skips.

The proxy was `bun run tools/record-mck-transcript.ts`. The live kit and driver
were on the `feat/mck-ion-value-cases` branch after removing the duplicate
`values-0003` case. The exchange has no machine-specific paths and was
byte-identical when captured again with the adapter built in this worktree. It
checks embedded-kit materialization with a real adapter exchange while the older
802-record reports and transcripts remain frozen under `baseline/` and replay
against `kit-2026-09-26/`.

`values-atoms-rust.ndjson` is a separate append-only capture of the eight
`values-0001`, `0002`, `0010`, `0011`, `0025`, `0026`, `0027` and `0028` cases
after the variable, unit, integer and boolean spelling/semantic split. The
same pinned Rust adapter reported 66 passes, no failures, kit errors or skips.
The exchange was captured with `tools/record-mck-transcript.ts` and matched a
second capture byte for byte. It leaves the earlier reference exchange intact.
