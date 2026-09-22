---
okf_version: "0.2"
title: Morphir extensions
description: "Compile-time extensions to the Morphir CLI: frontend and process providers, their identities and selection."
---

# Morphir extensions

Compile-time extensions to the Morphir CLI: frontend and process providers, their identities and selection.

## Orientation

* [Elm extension delivery](/design/elm-extension-delivery.md) - How the morphir-elm process extension reaches users and CI: published executables, pinned releases, local index installation and the remaining process-bundle publication gap.
* [Capability statements across the extension lifecycle](/design/capability-statements.md) - How an extension's capability statement travels unchanged from the guest through packaging, publication, installation and a session, and how hosts and extensions stay compatible while its formats change.

## Decisions

* [Two Elm frontend providers](/decisions/0001-two-elm-frontend-providers.md) - The CLI keeps morphir-elm as the default Elm frontend and morphir-elm-native as an opt-in provider until the native one reaches value and type-inference parity.
* [Extensions declare IR capability sets](/decisions/0002-extension-capability-sets.md) - Every extension declares which IR features it handles, in a vocabulary the IR specification owns and the Morphir Compatibility Kit verifies, so the toolchain can plan and check a pipeline instead of discovering gaps at run time.
* [The guest authors its capability statement](/decisions/0003-the-guest-authors-its-capability-statement.md) - The extension itself is the only author of its capability statement, which packaging captures with morphir.extension.describe, publish accepts for process bundles, install probes on the selected artifact, and each artifact carries separately.
* [Readers ignore unknown members unless critical](/decisions/0004-readers-ignore-unknown-members-unless-critical.md) - Every reader of extension formats ignores unknown members unless they are marked critical, accepts the current and previous released major and listed drafts, and converts old records, so host and extension changes ship on their own after one bootstrap host release.

## Design

* [A JavaScript runtime mode for extensions: exploration](/design/js-extension-runtime-exploration.md) - Compares ways to host JavaScript extensions in the Morphir CLI and records why the Elm extension stays a process extension for now.
