---
title: WASM host qualification reports
---

# WASM host qualification reports

A qualification report records the observations needed to check one host
executable, offering and platform. The same shared runner that compares the
crafted corpus checks this report. JSON Schema validates its structure;
it does not compute qualification. There is no parent TypeScript qualification
checker.

This is the `wasm-host-reports` family at `0.1.0-preview.1`. Its required first
member is `$schema`, with the exact value
`https://morphir.finos.org/schemas/wasm-host-reports/0.1.0-preview.1/report.schema.json`.
Readers accept that URL exactly. There is no `reportVersion`, `schemaVersion`,
implicit prerelease conversion or network schema lookup. Reports are closed
documents at every named level. Duplicate names, non-I-JSON numbers and unknown
members are invalid. Object order after `$schema` is insignificant; array order
is significant. All byte digests are lowercase SHA-256 hex strings.

The old experimental `morphir/mck-wasm-host-report` documents at
`0.1.0-draft.2` remain historical observations. They explicitly have no verdict.
Adding a verdict or replacing their version member does not convert them to
this family. The new family is not adopted until the shared .NET runner reads,
writes and checks it against the fixed report cases.

## Members

| Member | Meaning |
| --- | --- |
| `$schema` | Exact schema URL above, written first. |
| `suite` | Corpus identity, profile contract identity, and timing margin. |
| `runner` | Name, SemVer version, executable path and digest of the runner that made the observations. |
| `host` | Executable path and digest, arguments, build identity, declared profiles, offering, platform and engine. |
| `artifact` | Acquired archive or package path and digest, its source classification, and the host's path within it. |
| `limits` | Actual worker call deadlines, runner margin and help timeout, in milliseconds. |
| `bounds` | Exactly one declaration each for `memoryCeiling`, `instructionBudget` and `callDeadline`. |
| `guestKitCitations` | Generic guest reports for the declared profiles, each bound to its report bytes, kit bytes, guest module and this host. |
| `cases` | Every authored corpus case once, in corpus order, with module identity, recorded observations and claimed outcome. |
| `verdict` | Claimed `qualified` or `not_qualified`, independently recomputed by the checker. |

Paths in a report identify local input files. Relative paths resolve against
the report's directory, never the caller's current directory. A checker takes
an explicit allowed evidence root, refuses paths outside it and linked escapes,
and does not fetch a path or URL. A report is untrusted input, not permission to
execute its runner, host, artifact, guest or a cited command. Checking reports
does not install, extract or launch anything.

`suite` has `kit`, `kitVersion`, `corpus` and `contract`.
`corpus` has `path`, immutable source `commit` and `sha256`.
`contract` has `id`, SemVer `version`, `path` and `sha256`.
The checker uses its explicitly selected, digest-pinned corpus and contract;
a report cannot select weaker expectations by naming other files.
`deadlineMarginMs` is the corpus's fixed margin, not a writer-selected tolerance.

`runner` has `name`, `version`, `executable` and `sha256`.
`host` has `executable`, `sha256`, `arguments`, `buildIdentity`, `profiles`,
`offering`, `platform` and `engine`. Offering, platform and engine are required
runner inputs. No path, filename or operating system inference fills them in.
`profiles` includes `extism-kernel-v1`; `morphir-bytes-v1` is optional.
Other profile names are not accepted by this report version.

`artifact` has `path`, `sha256`, `hostPath` and `origin`. `hostPath` is a portable
relative path within the acquired archive or package. `origin` is `acquired`,
`source-built` or `synthetic`. Only `acquired` can support released-artifact
qualification. An acquisition record supplied independently by the release
qualification harness must bind the artifact digest, extracted executable
digest, offering, platform and build identity. Merely writing `acquired` in a
report is not evidence of acquisition. A checker verifies that binding; it does
not recreate an extraction from an untrusted report. The checker also requires
the cited runner, host, corpus, contract and artifact files to exist and match
their recorded digests.

`limits` has positive integer `extismCallDeadlineMs`, `bytesCallDeadlineMs`,
`marginMs` and `helpTimeoutMs`. The deadlines and margin must agree with the
selected corpus and profile contract. A larger recorded deadline cannot make
an otherwise late observation pass.

## Bounds and case observations

Each `bounds` entry has `bound` and `declaration`. `enforced` has no extra
member. `not_enforced` has a nonempty `reason` from the profile contract.
`undeclared` has no extra member. `inconsistent` has `declarations`, a list of
the distinct conflicting worker declarations. The checker reconstructs these
declarations from every applicable worker `started` event; the summary cannot
override an observed declaration. Missing and inconsistent required bounds
prevent qualification. Cases that start no worker cannot establish enforcement.

Each `cases` entry has `caseId`, `module`, `runs` and `outcome`.
`module` has `path`, expected `sha256`, and nullable `observedSha256`.
The expected identity comes from the pinned corpus. A digest mismatch is
`refused`, never a passing ABI-refusal observation. Missing module bytes are
`error`. A case may also carry `deviation`, containing `tracking` and `note`;
it explains an outcome and never changes it.

Each run records `arguments`, `framesWritten`, nullable `lastFrameWrittenMs`,
`end`, `endMs`, `stdoutBase64` and `stderr`. `framesWritten` counts complete
frames written. Times are nonnegative integer milliseconds relative to this
run's launch attempt. Each stderr entry has `atMs` and the exact decoded `line`,
including worker output unrelated to MEP. A truncated or undecodable capture
is an operational error, not silently shortened evidence. Stdout is canonical
base64 of all captured bytes and is decoded before framing/comparison.

`end` is an object with one of these shapes:

| `kind` | Other required members | Meaning |
| --- | --- | --- |
| `exited` | `exitCode`, a signed 32-bit integer | The worker exited and its output capture settled. |
| `stopped_by_runner` | `processTreeStopped: true` | The runner's deadline or cancellation stopped the owned process tree and capture settled. |
| `not_started` | `reason`, nonempty text | No worker was launched. |
| `cleanup_incomplete` | `reason`, nonempty text | Process or capture ownership did not settle. This cannot pass a case. |

The checker derives the case outcome from these observations through the same
corpus comparison used while running cases. `outcome` is one of `passed`,
`failed`, `error`, `refused`, `not_applicable` or `not_enforced` and must equal
that derived outcome. It does not trust a supplied pass count, exit status,
diagnostic, deviation, bound summary or previous verdict. No total is stored;
display totals are derived from the checked cases.

An undeclared byte profile permits `not_applicable` only for cases whose corpus
applicability names that profile. The case refusing a byte module on an
Extism-only host still runs. A case exercising an unenforced instruction
budget is `not_enforced`, not `passed`. That exception does not excuse a
different failing case or an unenforced memory ceiling or call deadline.

## Published guest evidence

Each `guestKitCitations` entry has `profile`, `kit`, `kitVersion`, `kitPath`,
`kitSha256`, `report`, `reportSha256`, `hostSha256` and `guestModuleSha256`.
Paths and digests identify both the exact generic kit and its report bytes.
The checker must parse and check the cited report with the existing shared
generic runner. A well-formed digest citation alone does not prove success.

At least one successfully checked, published Extism guest is required. A host
declaring the byte profile also needs one successfully checked published guest
of that profile. The citations must bind the same host executable digest,
worker arguments, build identity, offering and platform as the crafted report.
The guest module digest must equal an explicitly selected published bundle pin,
and the generic kit must be the explicitly selected approved kit. Passing only
initialize, an unsupported operation or a strict subset of the kit is insufficient.
Guest failures, skipped required cases, missing report bytes, changed hashes,
unknown report schemas and a report for a different host prevent qualification.

## Recomputing the verdict

The checker first validates structure and all evidence bindings, then compares
every case and checks every required guest citation. It reports `invalid` when
the document lies about an outcome or verdict, has a duplicate/missing/unknown
case, lacks identity, names different evidence, or uses an unsupported schema.
It does not rewrite such a document into an honest report.

For an honest complete report, the verdict is `qualified` only when:

1. The independently bound artifact is acquired for this exact offering/platform.
2. `memoryCeiling` and `callDeadline` are consistently enforced.
3. Every applicable crafted case passes, except the explicitly allowed
   unenforced instruction-budget cases. Only the allowed byte-profile cases
   may be `not_applicable`.
4. Every required published-guest proof above passes through the shared checker.

Otherwise the honest verdict is `not_qualified`. A command that validates
honesty must distinguish this result from qualification. The qualification
report-check command exits 0 only for `qualified`, 1 for honest
`not_qualified`, and 2 for `invalid` or unavailable evidence. Release gates
require the 0 result and bind the report to the exact cited artifact,
executable, offering and platform. An AOT report cannot qualify a dotnet tool.

The fixed inputs in
[`wasm-host-report.cases.json`](https://github.com/finos/morphir/blob/main/spec/mep/mck/wasm-host-report.cases.json)
are synthetic test documents, not qualification evidence. Their schema results
are checked as data here. Their semantic results must be exercised by the .NET
report checker before task 1.4 is complete. A successful schema check or
source-built host run cannot close released-artifact task 6.1 or support-table
task 6.3. The Rust workspace-info signature deviation remains open.
