---
type: Decision Record
title: One preview version per contract family, carried by a published schema
state: Accepted
decided: 2026-11-10
supersedes: ["0003"]
tags: [versioning, semver, compatibility, schema, preview, distribution]
status: stable
description: Documents that are read and written together share one version, carried by a required $schema URL to a published JSON Schema; formats not ready for 1.0 are 0.x.0-preview.N previews that match only exactly. MEP, the IR formatVersion and tool release metadata v1 keep their own versions.
sources:
  - id: decision
    resource: https://github.com/finos/morphir/issues/1146
    title: "finos/morphir#1146: Decision 15, one preview version per contract family (10 November 2026)"
---

# One preview version per contract family, carried by a published schema

Morphir versions its document contracts by family, not by file, and the version travels in a published schema URL:

| Rule | What it says |
| --- | --- |
| Family | Documents that are read and written together share one version. No file of a family has a version of its own. |
| `$schema` | Every JSON document of a family has a required `"$schema"` member, written first: the URL of that file's published schema, `https://morphir.finos.org/schemas/<family>/<version>/<file>.schema.json`. A TOML document carries the URL in a `#:schema <url>` directive at the top of the file. There is no `schemaVersion` member. |
| Preview | A format that is not ready for 1.0 is on `0.x.0-preview.N`, labelled `preview`, starting at `0.1.0-preview.1`, whatever shipped before. |
| Exact match | A reader accepts a document only when its `$schema` URL is one the reader lists, compared as exact text. A preview promises nothing to the next, and nothing converts between previews. |
| 1.0 | A family moves to `1.0.0` only when its format is settled. SemVer's release rules apply from then on. |
| Exceptions | MEP is the 0.2 line, every prerelease of `0.2.0` and every final `0.2.x`. The Morphir IR `formatVersion` follows its own decisions. Tool release metadata v1 keeps its own version. |

The extension state family is the first one: the release descriptor, the repository index record, the installed catalog, the extension lock, the transaction journal, the repositories configuration and the capability claim set. It restarts at `0.1.0-preview.1`.

## Summary

Decision 0003 made SemVer the default and had a revised, already-shipped format continue from its released major. Followed literally, that put the extension contracts on a `2.0.0-draft` line. Yet none of them is ready for 1.0, and each file of a set carried a version of its own. The maintainer decided on 10 November 2026 (finos/morphir#1146, Decision 15) to keep SemVer but to say "not ready" with a `preview` label below 1.0, and to version a set of documents once. A published schema per file then states that version where a reader and a validator both find it.

| Option | Outcome | Why |
| --- | --- | --- |
| One preview version per family, carried by a `$schema` URL | Chosen | One version for a set that changes together, and the schema both names and validates the format |
| Keep decision 0003: a version per file, revisions continue from the released major | Rejected | It produced `2.0.0-draft` versions for formats that are not ready for 1.0, and a version per file for documents that change together |
| One version per family, in a `schemaVersion` member | Rejected | A bare version names no schema, so a reader or editor cannot validate the document from the document alone |
| Keep the `draft` label below 1.0 | Rejected | `draft` on a 2.0.0 line read as close to stable; `preview` on `0.x` says the format is not settled |

## Why

The extension contracts showed the cost of decision 0003's rule 6. The release descriptor and the index and installed records had shipped as the integer `1` and `"1.0"`, so their revisions became `2.0.0-draft.1`, then `2.0.0-draft.2`, and the dotted-ids change moved them to `2.0.0-draft.3`. Meanwhile the extension lock went to its own `2.0.0-draft.1` and the transaction journal to another. Nothing in that set was ready for a 1.0 promise, and the version numbers said otherwise. The documents also change together: a new member in the catalog almost always means one in the lock. Separate versions per file meant separate bumps, and separate places for two hosts to disagree.

A family version removes both problems. One string says which set of formats a document belongs to, and a pre-1.0 `preview` says that set is still moving. Carrying the version in a `$schema` URL rather than a bare member means the same string names a schema that can be fetched and checked. Editors that understand `$schema`, and TOML tools that understand `#:schema`, validate the document with no Morphir code at all. A reader compares the URL as exact text. That is the exact-match rule decision 0003 had for drafts, now applied to every preview.

## Alternatives rejected

### Keep decision 0003: a version per file, revisions continue from the released major

This is what produced the `2.0.0-draft` line. The rule kept a revision from sorting below what released hosts read. But no current host reads the earlier formats, because transient pre-1.0 formats are neither read nor converted (maintainer, 9 November 2026), so that protection bought nothing, and it cost a misleading major.

### One version per family, in a `schemaVersion` member

It fixes the per-file problem but not the second one. A `schemaVersion` names a version, not a schema, so a validator still needs out-of-band knowledge of where the schema for that version lives. The URL carries both.

### Keep the `draft` label below 1.0

The label is cosmetic for SemVer precedence, but not for readers of the documents. `preview` on a `0.x` line is the plainer statement that the format promises nothing yet.

## Consequences

- `AGENTS.md`, "Contract Versioning", states these rules in place of decision 0003's.
- The extension state family restarts at `0.1.0-preview.1`. The OpenSpec changes in flight, `allow-dotted-extension-ids` and `add-extension-packages`, replace their per-file versions with it. Each family file needs a published JSON Schema under `website/static/schemas/extensions/0.1.0-preview.1/`.
- The toolchain documents form their own family and get their own preview version, in their own change.
- MEP, the IR `formatVersion` and tool release metadata v1 are unchanged.
- Other contracts that cite decision 0003's drafts keep their versions until a change of their own moves them; this record does not renumber them.
- Decided beside it, Decision 16 deletes the Rust CLI from finos/morphir. No reader or writer of these formats is planned in Rust.

## Revisit when

Revisit when a family is ready for `1.0.0` and needs a compatibility range across released versions, or when a document must belong to two families at once.
