---
okf_version: "0.2"
title: Morphir extensions
description: "Compile-time extensions to the Morphir CLI: frontend and process providers, their identities and selection."
---

# Morphir extensions

Compile-time extensions to the Morphir CLI: frontend and process providers, their identities and selection.

## Orientation

* [Elm extension delivery](/design/elm-extension-delivery.md) - How the morphir-elm process extension reaches users and CI: published executables, pinned releases, local index installation and the remaining process-bundle publication gap.
* [Capability claims across the extension lifecycle](/design/capability-claims.md) - How an extension's capability claim set travels unchanged from the guest through packaging, publication, installation and a session, how the host checks the claims, and how hosts and extensions stay compatible while the formats change.

## Decisions

* [Two Elm frontend providers](/decisions/0001-two-elm-frontend-providers.md) - The CLI keeps morphir-elm as the default Elm frontend and morphir-elm-native as an opt-in provider until the native one reaches value and type-inference parity.
* [Extensions declare IR capability sets](/decisions/0002-extension-capability-sets.md) - Every extension declares which IR features it handles, in a vocabulary the IR specification owns and the Morphir Compatibility Kit verifies, so the toolchain can plan and check a pipeline instead of discovering gaps at run time.
* [The guest authors its capability statement](/decisions/0003-the-guest-authors-its-capability-statement.md) - The extension itself is the only author of its capability statement, which packaging captures with morphir.extension.describe, publish accepts for process bundles, install probes on the selected artifact, and each artifact carries separately.
* [Readers ignore unknown members unless critical](/decisions/0004-readers-ignore-unknown-members-unless-critical.md) - Every reader of extension formats ignores unknown members unless they are marked critical, accepts the current and previous released major and listed drafts, and converts old records, so host and extension changes ship on their own after one bootstrap host release.
* [Elm providers normalize explicit package names](/decisions/0005-elm-providers-normalize-explicit-package-names.md) - Every Elm workspace provider reads an explicit package name with both `.` and `/` as segment separators and reports one normal form, lowercase words joined by `-` and segments joined by `/`, which keeps the Morphir IR package path unchanged.
* [The describe fallback reports only what a session reports](/decisions/0006-the-describe-fallback-reports-only-what-a-session-reports.md) - A refusal before initialize has its own MEP error code, -32014, and a statement the host builds from a fallback session holds only what that session reports, with no requires or critical members.
* [Extensions make capability claims](/decisions/0007-extensions-make-capability-claims.md) - The document an extension authors about itself is a capability claim set made of claims, not a capability statement; the version-2 draft formats rename their members and move to the next draft, and readers still accept the draft.1 spelling.

## Design

* [A JavaScript runtime mode for extensions: exploration](/design/js-extension-runtime-exploration.md) - Compares ways to host JavaScript extensions in the Morphir CLI and records why the Elm extension stays a process extension for now.
