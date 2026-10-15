# Provider snapshot byte contract

This package encodes and checks the one-shot binary Ion 1.0 contract implemented
by `morphir-package/provider-snapshot/0.1.0-draft.1`. A decoded `Snapshot` checks
correlation, profile, policy/lock identities and retained native/context hashes.
It does not authenticate a service or grant access to saved bytes. Its host must
qualify the selected executable and freshly complete the scoped operation before
installing its views.

Requests are capped at 4 MiB and responses at 16 MiB. Binary structure is bounded
before materialization. Closed structs reject unknown/duplicate fields, nested
annotations and wrong types. The graph allows 128 Libraries, 256 contexts per
Library and 1024 contexts in total.

Original native JSON bytes and their revision stay separate from the checked
v4.0 JSON core and raw document metadata. Both remain supported JSON artifacts,
carried as exact Ion blobs. Context resolution uses only the retained inventory,
including relative imports, with no filesystem or network fallback. Returned
semantic views are reparsed so mutation cannot alter the retained response.

`shared_fixture_wbtest.mbt` embeds binary responses emitted by the Rust service
at `af6d3b36cd393c8cc9fa4e5f0ddf0b31674642fa`, from its known-key test fixture.
Those keys are never production defaults. The fixture qualifies byte and naming
interoperability on all targets, not installed authenticated-host behavior.
