---
title: Published MCK release acceptance
---

The manually dispatched **Published MCK release acceptance** workflow qualifies an
existing CLI release on all six supported native targets. Run it after the release
assets are published, with a tag containing the acceptance harness. It does not
publish a release or change consumer version pins.

The workflow checks out that tag and verifies the native archive against its
published SHA-256 file. It compiles the existing `mck_run` integration harness,
which also provides a native adapter replaying fixed protocol answers. The installed
CLI acquires a kit from the tag's exact full source commit. A fresh consumer Git
repository records `kit/`, its manifest, and an attribute rule preserving every byte.
The acquisition home, temporary files, and downloaded archive are removed before
runtime acceptance.

Before isolation, every matrix target also runs the native `runner_parity` and
`transport` integration suites. These source tests exercise transcript replay and
hostile adapter behavior on each platform; their log is retained separately from
the published executable's runtime evidence.

The runtime copies the installed CLI, replay adapter, transcript and acquired kit
into another temporary directory. It uses an empty tool path and a fresh home. The
selected snapshot is mandatory: missing or malformed inputs never fall back to the
embedded kit. No package manager, Cargo, Bun or external schema validator runs in
this phase.

Operating-system network denial applies to the test process and its children:

- Linux runs the native test in an isolated network namespace.
- macOS runs it with a sandbox profile denying network operations.
- Windows adds an outbound block rule only on a disposable GitHub-hosted runner,
  executes the native test with a five-minute limit, and removes the rule in a
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

Each matrix job uploads acquisition metadata, the network-denial result, kit status,
source and acquired-kit reports, HTML, and runtime logs. Checksums establish archive
integrity relative to the published checksum; they do not authenticate an independent
publisher. The replay proves runner behavior against fixed answers, not an independent
binding's implementation. Separate binding adoption gates remain necessary.

For normal development, the existing installed-CLI smoke still vendors the embedded
kit. `MORPHIR_MCK_PREACQUIRED_KIT` selects a previously acquired snapshot directory;
`MORPHIR_MCK_INSTALLED_CLI` selects the executable to test. The workflow compiles the
harness before isolation and runs its executable directly. Do not infer published or
cross-platform acceptance from a local source build passing the smoke test.
