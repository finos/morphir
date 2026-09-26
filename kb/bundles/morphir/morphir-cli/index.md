---
okf_version: "0.2"
title: Morphir CLI
description: "The Rust morphir command line: its commands, behavior and design, as shipped from finos/morphir."
---

# Morphir CLI

The Rust morphir command line: its commands, behavior and design, as shipped from finos/morphir.

## Orientation

* [Knowledge Base Tooling](/kb-tooling.md) - The morphir kb command manages the OKF knowledge base and the intent recorded in it, from the command line.
* [Example-driven CLI validation](/example-driven-validation.md) - Markdown and Gherkin scenarios with embedded Rego assertions turn documented Morphir CLI workflows into incremental regression coverage.

## Design

* [Configuration and lifecycle](/configuration-and-lifecycle.md) - The proposed model for how the Morphir CLI resolves a setting and where each phase of a run produces the state the next one needs.

## Decisions

* [The command line is a configuration layer](/decisions/0001-the-command-line-is-a-configuration-layer.md) - Morphir chose to make command-line flags an ordinary layer in the configuration stack, above the environment, rather than precedence logic written again at each call site. Implementation is pending.
* [The session owns the application lifecycle](/decisions/0002-the-session-owns-the-application-lifecycle.md) - Morphir chose to have the CLI session implement every starbase phase and hold phase-produced data in a discriminated union, so command code cannot run without the state its phase produced. Implementation is pending.
* [SemVer is the default contract versioning scheme](/decisions/0003-semver-is-the-default-contract-versioning-scheme.md) - Every versioned contract Morphir defines uses SemVer 2.0 strings by default, with prerelease versions that match only exactly, so a contract can be refined as a draft and then frozen. Morphir IR formatVersion is not affected.
