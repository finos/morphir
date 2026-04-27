---
title: Introduction
description: "Substrate turns the documents an organization already writes into verifiable knowledge — a structured, link-typed corpus that humans, engineers, and LLMs can collaborate on."
breadcrumb: ["Start here", "Introduction"]
---

Substrate is a **specification substrate**: a structured, link-typed,
human-readable corpus of Markdown documents that captures what a system
*should* do — its concepts, rules, operations, and examples — in a form
that both humans and LLMs can read, edit, and reason about.

Its purpose is to turn the documents an organization already writes —
specifications, regulations, domain models, runbooks — into **verifiable
knowledge**: a corpus whose internal consistency, type compatibility,
and behavioural claims can be checked by tooling rather than taken on
faith.

## Why this matters

Most institutional knowledge lives in unverifiable documents. Nothing
checks that a definition on page 12 matches the rule on page 47, that
an example still produces the stated output, or that the implementation
actually does what the document says.

LLMs amplify this. They are powerful readers and writers of prose, but
their answers are only as trustworthy as the context they are given.
Feed a model the wrong slice of a sprawling document set, or one that
quietly contradicts itself, and you get confident output that is wrong
in ways no one catches.

The same structure that makes a corpus mechanically verifiable also
makes it the ideal context source for an LLM. A document set that tools
can check, an LLM can be trusted to act on.

## A knowledge graph hidden in plain Markdown

Substrate is **plain Markdown**, written by humans assisted by LLMs,
rendered by GitHub, no custom syntax. Structure is carried by the
things Markdown already gives you — headings, tables, lists, footnotes,
and especially **links** between documents.

As authors describe a business problem in their own words, every
reference to a concept, type, or operation is a link to the place that
defines it. The corpus quietly accumulates a **semantic knowledge
graph** that tools can traverse, type-check, and slice for an LLM —
without constraining how the prose is written. The freedom to describe
the domain naturally and the ability to interpret it mechanically come
from the same structure.

## What this changes for engineers

Engineers contribute most when they can spot patterns and translate
them into efficient technology. With unstructured prose as the only
context, that skill has nowhere to land — engineers either build a
mental model in their head and hand-hold an LLM through implementation,
or they let the LLM interpret the prose directly and improvise.

Substrate externalizes the mental model. Engineers describe recurring
patterns using the corpus's own identifiers and attach **technology
mappings** to them — how each pattern is realized in TypeScript, SQL,
or whatever target fits. Where a pattern matches and a mapping exists,
the tooling produces the implementation directly: no LLM improvisation,
no per-task prompt engineering. Where a case is novel, the LLM still
helps, but its work is checked against the corpus and the result can be
promoted to a reusable pattern. Engineering judgment accumulates in the
corpus rather than evaporating into chat transcripts.

## How to read these docs

- **[Vision](/docs/specs/vision/)** — goals, principles, and where this
  is headed.
- **[Language](/docs/specs/language/)** — the conventions a Substrate
  corpus follows: Markdown structure, link semantics, types, concepts,
  and expressions.
- **[Tools](/docs/specs/tools/cli/)** — the `substrate` CLI: context
  extraction, validation, refactoring, packaging, and test execution.
- **[Install & quickstart](/docs/getting-started/)** — set up a corpus
  and run your first commands in about five minutes.

## Conventions

Inline `code` denotes Substrate identifiers, command names, or other
literal tokens. Block quotes are direct quotations from the primary
sources a corpus cites (regulations, contracts, papers). Decision
tables render as ordinary Markdown tables and are authoritative.
