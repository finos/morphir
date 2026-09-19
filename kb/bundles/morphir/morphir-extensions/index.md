---
okf_version: "0.2"
title: Morphir extensions
description: "Compile-time extensions to the Morphir CLI: frontend and process providers, their identities and selection."
---

# Morphir extensions

Compile-time extensions to the Morphir CLI: frontend and process providers, their identities and selection.

## Orientation

* [Elm extension delivery](/design/elm-extension-delivery.md) - How the morphir-elm process extension reaches users and CI: published executables, pinned releases, local index installation and the remaining process-bundle publication gap.

## Decisions

* [Two Elm frontend providers](/decisions/0001-two-elm-frontend-providers.md) - The CLI keeps morphir-elm as the default Elm frontend and morphir-elm-native as an opt-in provider until the native one reaches value and type-inference parity.

## Design

* [A JavaScript runtime mode for extensions: exploration](/design/js-extension-runtime-exploration.md) - Compares ways to host JavaScript extensions in the Morphir CLI and records why the Elm extension stays a process extension for now.
