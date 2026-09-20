---
okf_version: "0.2"
title: Morphir CLI
description: "The Rust morphir command line: its commands, behavior and design, as shipped from finos/morphir."
---

# Morphir CLI

The Rust morphir command line: its commands, behavior and design, as shipped from finos/morphir.

## Orientation

* [Knowledge Base Tooling](/kb-tooling.md) - The morphir kb command manages the OKF knowledge base and the intent recorded in it, from the command line.
* [Example-driven CLI validation](/example-driven-validation.md) - Notebook and Markdown scenarios with embedded Rego assertions turn documented Morphir CLI workflows into incremental regression coverage.

## Design

* [Configuration and lifecycle](/configuration-and-lifecycle.md) - How the Morphir CLI resolves a setting and where each phase of a run produces the state the next one needs.

## Decisions

* [The command line is a configuration layer](/decisions/0001-the-command-line-is-a-configuration-layer.md) - Command-line flags become an ordinary layer in the existing configuration stack, above the environment, rather than precedence logic written again at each call site.
* [The session owns the application lifecycle](/decisions/0002-the-session-owns-the-application-lifecycle.md) - The CLI session implements every starbase phase and holds phase-produced data in a discriminated union, so command code cannot run without the state its phase produced.
