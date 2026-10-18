# Native owner corpus

This is the exact offline `0.1.0-draft.18` corpus for `run-native-owner`, executed
by the existing shared Rust MCK with an explicit independent adapter. See the
[contract](../../draft.18/README.md) for bounded inputs, projections, fixed effect
choices, and the scope of evidence. Inputs and fixed expectations are inline in
`cases.json`; their original bytes determine the corpus hash.

The first scenario isolates wrong-window authority. With the `other` window,
`app` origin, and `page-X` page, one `session.open` attempt must return
`unauthorized` with effect `none`, without invoking any dependency. Executions and
workspace are available, so service availability cannot explain the rejection.
There are no roots, pickers, or cleanups and all dependency counters remain zero.
This expectation follows the frozen native draft.1 authority contract.

The immutable evaluation asset is the complete draft.17 v4 Library model defining
public `client:main#answer`, with zero arguments and Int literal 42. JSON arguments
are `[]`. Model text remains opaque to the runner; production import/evaluation
requires separate adapter evidence.

Fixed expectations are authored from the accepted contract before implementation
comparison. Replay checks the runner, and controlled owner dependencies do not
establish filesystem containment, actual worker exit, OS provenance, or packaged
platform conformance.
