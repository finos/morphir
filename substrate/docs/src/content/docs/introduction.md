---
title: Introduction
description: "Substrate is an LLM-native executable specification language. This is what it is, and how to read these docs."
breadcrumb: ["Start here", "Introduction"]
---

Substrate is a programming language designed to be **authored, read, and extended by large language models as fluently as by humans**. A substrate spec is a Markdown document whose structure — headings, tables, links — is the program. There is no separate source file; the Markdown is the source.

## Why an executable specification?

Most software is shadowed by a natural-language artifact (a PRD, a regulation, a legal clause) that is the real source of truth. Code translates that artifact, imperfectly, into a runnable form. When the artifact changes, the code drifts.

Substrate collapses that split: the specification **is** the program. It reads like a specification — and runs like one.

## How to read these docs

- **[Vision](/docs/specs/vision/)** — the motivation and design principles.
- **[Language](/docs/specs/language/)** — the definitive reference for syntax, types, concepts, and expressions. Every spec construct is documented here.
- **[Tools](/docs/specs/tools/cli/)** — the `substrate` CLI, package manager, and related tooling.
- **[Install & quickstart](/docs/getting-started/)** — run your first spec in about five minutes.

## Conventions

Inline `code` is Substrate source. Block quotes are direct quotations from the primary sources a spec cites (regulations, contracts, papers). Decision tables render as ordinary Markdown tables and are authoritative.
