# Connected original-model consumer

The connection implementation is shared with Workbench's inactive
`model-originals-session` entry point. It retains actual discovery selections,
connection generations, monotonic literal request IDs and one owned socket.
Original transfer extends that socket after capture without activating a browser
UI action or advertising a host capability.

`originals.ts` verifies complete/none capture metadata, declared inventory coverage,
portable names, deterministic pages, exact numeric counts, inventory and byte
hashes, read progression and release correlation. Files flow to an injected sink;
publication belongs to the caller. It reuses the pinned literal JSON reader,
Unicode tables and filename component validation from the existing artifact
consumer, with the model profile's distinct path and inventory bounds.

The Node boundary is `apps/morphir/build-provider/originals.mts`. The primary CLI
uses the existing `ContentPublisher` after verification and acknowledged release.
Its private file carrier is also rechecked before the destination is committed.
The independent compatibility checker remains the maintained parent Rust MCK.
These consumer tests do not replace its connected-profile qualification.

Run `bun test pkgs/morphir-host/model-originals-client/originals.test.ts` and
`bun test apps/morphir-workbench/browser/model-originals-session.test.ts`.
Actual-host CLI acceptance lives in `apps/morphir/scripts/test-headless-originals.ts`.
