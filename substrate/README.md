# Substrate

**Verifiable knowledge for human–LLM collaboration.**

Substrate turns the documents your organization already writes —
specifications, regulations, domain models, runbooks — into a structured,
link-typed, mechanically verifiable corpus that both humans and language
models can read, edit, and act on.

## Why

Most institutional knowledge lives in unverifiable documents. Nothing
checks that a definition on page 12 matches the rule on page 47, that
an example still produces the stated output, or that the implementation
actually does what the document says. As specifications evolve, the gap
between document and reality widens silently.

LLMs amplify this. They are powerful readers and writers of prose, but
their answers are only as trustworthy as the context they are given.
Feed a model the wrong slice of a sprawling document set, or one that
quietly contradicts itself, and you get confident output that is wrong
in ways no one catches.

The same structure that makes a corpus mechanically verifiable also
makes it the ideal context source for an LLM. A document set that tools
can check, an LLM can be trusted to act on.

## What it is

Substrate is **plain markdown**, written by humans assisted by LLMs, 
rendered by GitHub, no custom syntax. Structure is carried by the things 
markdown already gives you — headings, tables, lists, footnotes, and 
especially **links** between documents.

Around that medium, Substrate adds:

- A **package model** — versioned libraries of reusable concepts, and
  domain corpora that compose them, with cross-repository links resolved
  through a vendored `substrate/` tree.
- A **CLI** — `substrate` — that extracts focused context for LLMs,
  validates the corpus for consistency and type compatibility, refactors
  safely across files, runs embedded test cases, and binds
  specifications to live data.

## Verifiable knowledge

Every claim the corpus makes is mechanically checkable: that this term
has that type, that this operation produces that output for this input,
that this rule depends on that definition. Verification is layered —
structural validity, link resolution, type compatibility, embedded test
cases — and findings are reported against the originating prose, not an
opaque intermediate representation.

## What you can do with it today

```bash
substrate context spec.md#section          # tree-shaken slice for an LLM
substrate validate                         # structure, links, types
substrate test spec.md                     # run embedded test cases
substrate refactor rename a.md#x b.md#y    # safe corpus-wide rename
substrate install / update / publish       # versioned packages
```

Run `substrate --help` for the full command set.

## Status

Substrate is part of the [Morphir](https://github.com/finos/morphir)
project. It is in active development; the language and tooling are
evolving together.

## Learn more

- [Vision](specs/vision.md) — goals, principles, and where this is
  headed.
- [Language Specification](specs/language.md) — the conventions the
  corpus follows.
- [CLI](specs/tools/cli/) — command reference and design decisions.

## License

See [LICENSE](LICENSE).
