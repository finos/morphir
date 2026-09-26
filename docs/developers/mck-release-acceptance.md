---
title: Published MCK release acceptance
---

The manually dispatched **Published MCK release acceptance** workflow qualifies an
existing CLI release on all six supported native targets. Run it after the release
assets are published, with a tag containing the acceptance harness. It does not
publish a release or change consumer version pins.

The workflow checks out that tag as its source and loads preparation tooling from
the workflow's own commit in a separate directory. This lets qualification fixes
test an existing release without moving its tag or rebuilding its binaries.
The preparation verifies the native archive against its
published SHA-256 file. It compiles the existing `mck_run` integration harness,
which also provides a native adapter replaying fixed protocol answers. The installed
CLI acquires a kit from the tag's exact full source commit. A fresh consumer Git
repository records `kit/`, its manifest, and an attribute rule preserving every byte.
The acquisition home, temporary files, and downloaded archive are removed before
runtime acceptance.

Before isolation, every matrix target runs `transport` and the kit test available
in that source tag: historical tags use `runner_parity`; Gherkin-only tags use
`kit_steps`. Tags with package support, starting at beta.3, also
run `package_corpus`, `package_protocol` and `package_runner`. Preparation selects
these targets from the checked-out tag's Cargo metadata and rejects a partial
package test inventory. Older tags retain their original IR-only qualification.
These source tests exercise kit steps and hostile adapter behavior on each
platform; historical tags also replay transcripts in `runner_parity`. Their
log is retained separately from the
published executable's runtime evidence.

The runtime copies the installed CLI, replay adapter, transcript and acquired kit
into another temporary directory. It uses an empty tool path and a fresh home. The
selected snapshot is mandatory: missing or malformed inputs never fall back to the
embedded kit. No package manager, Cargo, Bun or external schema validator runs in
this phase.

Operating-system network denial applies to the test process and its children:

- Linux runs the native test in an isolated network namespace.
- macOS runs it with a sandbox profile denying network operations.
- Windows adds an outbound block rule only on a disposable GitHub-hosted runner,
  executes the native test with a ten-minute limit, and removes the rule in a
  `finally` block. Never apply that workflow step to a workstation or persistent runner.

Preparation first proves that a direct TCP connection to the configured external
probe works. The native test requires that same connection to fail under isolation.
An unavailable isolation facility, an unexpectedly successful probe, or exceeding
the runtime limit fails acceptance. There is no unrestricted fallback.

The installed CLI runs `kit status`, `check`, `coverage`, `schema check`, an adapter
run, independent `report check`, and HTML rendering. The harness compares the full
snapshot digest and every ordered record with a run against the checked-out source
kit, excluding only the already documented volatile duration fields. It also checks
that modifying a schema after acquisition fails manifest verification.

Starting at beta.3, the same runtime also runs all 80 package integrity and 78
resolution cases. It copies `spec/package` from the checked-out tag into its
temporary directory and supplies that explicit path to `morphir mck package run`.
This is a copied package corpus, separate from the managed IR kit; it does not
qualify package `kit vendor` or acquisition support. Missing or malformed package
inputs fail acceptance. Fixed recordings of the independent TypeScript adapter
provide the responses. Both runs must preserve their fixed corpus hashes, pass
every case and reproduce the complete ordered frozen reports, excluding only
`driverVersion` and `startedAt`. The [baseline provenance](https://github.com/finos/morphir/blob/main/spec/mck/baseline/package/README.md)
records the source revisions and capture procedure.

Starting at beta.4, preparation also compiles the pinned Rust package MVP adapter
from the tagged source. The isolated runtime copies it beside the downloaded
CLI and runs all 70 required local Library cases with `mck package mvp-run`.
`mvp-report check` independently verifies the full inventory and all passing
results; `mvp-report render` produces standalone HTML. The runtime removes one
record from a copy of the report and requires the checker to reject it. It
also runs the downloaded CLI's `itest` command on the signed local Library
restore and scoped-update examples. Those examples exercise explicit trust,
fresh metadata, resolution, restore, and generated provider consumption. All
inputs are copied from the checked-out tag before execution. These checks do
not replace the 80/78 historical gates.

Each matrix job uploads acquisition metadata, the network-denial result, kit status,
source and acquired-kit reports, HTML, and runtime logs. Package-capable tags also
upload `package-integrity.json`, `package-resolution.json` and `package-runtime.json`.
The latter records contract versions, hashes, passing counts and the network probe.
Checksums establish archive
integrity relative to the published checksum; they do not authenticate an independent
publisher. The replay proves runner behavior against fixed answers, not an independent
binding's implementation. Separate binding adoption gates remain necessary.
Beta.4 jobs additionally retain `package-mvp.json`, `package-mvp.html`,
`package-mvp-negative.log`, `package-mvp-runtime.json` and
`package-examples.log`. The harness copies these as it runs, so a later failure
still leaves the earlier report and command output in the uploaded artifact.

For normal development, the existing installed-CLI smoke still vendors the embedded
kit. `MORPHIR_MCK_PREACQUIRED_KIT` selects a previously acquired snapshot directory;
`MORPHIR_MCK_INSTALLED_CLI` selects the executable to test. The workflow compiles the
harness before isolation and runs its executable directly. Do not infer published or
cross-platform acceptance from a local source build passing the smoke test.

For package acceptance regressions, `MORPHIR_MCK_PACKAGE_CORPUS` overrides the
`spec/package` directory to copy and `MORPHIR_MCK_PACKAGE_BASELINE` overrides the
recordings/reports directory. These are test-harness inputs, not CLI configuration.
Release workflows use the checked-out tag's defaults.
