# Synthetic host report inputs

`host.txt`, `runner.txt` and `artifact.txt` are inert, independently authored
byte identities for `../../wasm-host-report.cases.json`. Never execute them or
treat them as acquired release artifacts. Paths in those embedded reports use
`spec/mep/mck` as their report directory, as the case manifest states.

The complete case lists refer to the unchanged crafted corpus. The baseline
deliberately starts no worker, declares bounds undeclared, has no guest proof,
and records `not_qualified`. Its outcome must not be promoted by a schema pass.
The two edited bound-summary inputs are invalid because they invent enforcement
declarations absent from the raw observations, even for optional metering.

The parent test validates JSON Schema results and file/corpus identity only.
Every semantic `expected.reportCheck` still needs the shared .NET checker.
Before task 1.4 closes, extend these fixed data with a fully qualified positive
control and isolated honest required-bound, optional-budget and guest-proof
controls. Do not record live host output as an expectation to fill those gaps.
No test here establishes support for an offering, platform or guest.
