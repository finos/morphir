# Fixed M1/M2 inputs

These assets come from `finos/morphir` revision
`a009be246302cf7705f5ab64572bfdc74a5e5fd8`, under
[`spec/conceptual/model`](https://github.com/finos/morphir/tree/a009be246302cf7705f5ab64572bfdc74a5e5fd8/spec/conceptual/model)
and
[`spec/conceptual/traits`](https://github.com/finos/morphir/tree/a009be246302cf7705f5ab64572bfdc74a5e5fd8/spec/conceptual/traits).
They follow the upstream Apache-2.0 license.

The JSON files are exact copies of the corresponding upstream fixture files.
`traits.json` is the upstream traits `model.json`. `model-unknown.ion` and
`traits-unknown.ion` are the respective `unknown-descriptive.ion` files.
`fixtures.mbt` contains the same literals as portable compile-time strings, with
no filesystem test dependency. JSON whitespace outside strings is immaterial;
source wording inside strings is not changed. The fixture package is imported
only by tests. Expectations are authored literals, never codec output.

| Upstream observations | Local test coverage |
| --- | --- |
| M1 0001, 0003 | Full prose/mixed graphs and semantic IR through actual Ion text and binary codecs; exact identities, revisions and retained wording. |
| M1 0002, 0004, 0006–0009 | Independent gaps/concerns, duplicate identity, built-in relationship direction and missing/wrong-revision references. |
| M1 0010 | Exact integer and decimal scale, symbol, typed null and ordered annotations from the fixed Ion asset. |
| M1 0011, 0012, 0018, 0019 | Required-interpreter, bare-export, neighboring-profile and occupied-owner refusal. |
| M1 0021 | Library signature projection compared with the independently authored `mixed.ir.json`; graph and valid sidecars retained. |
| M2 0024, 0047 | Unknown rich application payloads and members through both actual codecs. |
| M2 0025 | Bare export refuses trait loss. |
| M2 0015, 0016, 0036 | Semantic downgrade diagnostic, competing single-valued assertion gap, and required interpretation refusal while preserving facts. |

Additional local tests cover transitive supplied closure isolation, malformed
known records, mutation isolation, cycle budgets, invalidated sidecar owners,
legacy graph-free profiles, opaque public type projection, retained projection
gaps and provenance. Complete fixture graphs for all entity kinds, independent
concerns, traits and the dictionary also round-trip through the model API.

This is scoped codec/inspection coverage, not a claim to run every upstream case
or qualify interpreter, MCK or MEP conformance. Contract checking, trait payload
typing, artifact binding, evidence assessment and linked-metadata projection
observations remain outside these tests.
