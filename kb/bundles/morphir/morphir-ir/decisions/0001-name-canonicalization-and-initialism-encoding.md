---
type: Decision Record
title: Names encode initialisms as uppercase segments
description: "IR v4 marks an initialism by writing its canonical segment in uppercase, and projects names onto the document tree through a defined escape."
state: Accepted
decided: 2026-08-30
tags: [ir, ir-v4, naming, canonicalization, filesystem, uri]
status: draft
---

# Names encode initialisms as uppercase segments

IR v4 changes three things about names at once, because they are one design and were previously conflated.

| Layer | Before | After |
| ----- | ------ | ----- |
| Model | An initialism is a run of single-letter words: `["value", "in", "u", "s", "d"]` | An initialism is a word carrying a flag: `["value", "in", initialism("usd")]` |
| Canonical string | A run is wrapped in parentheses: `value-in-(usd)` | An initialism segment is written uppercase: `value-in-USD` |
| Document tree | The canonical string is the filename verbatim: `value-in-(usd).value.json` | The filename is a defined, reversible escape of the canonical string: `value-in-_usd.value.json` |

This record is `Proposed`. Two questions listed under [Unresolved](#unresolved) decide it, and both belong to the
project maintainers rather than to this analysis.

## Summary

The parenthesized encoding was adopted on the stated grounds that it is "URL-safe, readable, unambiguous"
(`docs/design/draft/ir/naming.md`, line 17). The URL premise behind that phrasing is false: RFC 3986 makes the path
component case-sensitive. Correcting the premise removes the reason to avoid case, and case is the marker every
reader and every tool already understands. The filesystem, not the URL, is the constraint that actually bites, and it
requires an escape layer for reasons unrelated to initialisms. Once that layer exists, the canonical string is free
to be legible.

| Option | Outcome | Why |
| ------ | ------- | --- |
| Initialism flag on a word, uppercase canonical segment, escaped document tree | Chosen | Legible on sight, unreserved in a URI, and the escape layer is required regardless |
| Parenthesized single-letter runs, as drafted for v4 | Rejected | The URL rationale is false, parentheses are percent-encoded inconsistently, and letter runs misclassify single-letter words |
| Doubled hyphen marker, identity stays lowercase | Rejected | Defensible, and the named fallback, but reads as a typo and keeps a bespoke grammar |
| Underscore prefix marker | Rejected | Collides with the permissive `snake_case` input format the parser already accepts |
| Percent-encoding the initialism | Rejected | `%` expands in `cmd.exe` and invites double-encoding through URL libraries |
| Tilde marker | Rejected | Shell tilde expansion and the editor backup-file convention |
| No marker, backends consult an initialism dictionary | Rejected | Rendering then differs per tool, which breaks cross-language round-trip |
| No marker, always render `Usd` | Rejected | Discards author intent on import and produces non-idiomatic output for Go and Java |

## Why

### The URL premise was wrong

RFC 3986 section 6.2.2.1 normalizes only the scheme and the host to lowercase, and states that all other components
are compared case-sensitively. Percent-encoding triplets are the one further exception, and they are irrelevant here.
So `morphir://pkg/my-org/domain/User.type.json` and `morphir://pkg/my-org/domain/user.type.json` are distinct URIs,
and a URL path carries case without loss.

This is proven from the specification text, not judged.

The correction removes a justification for lowercase-only identity. It does not by itself remove the *conclusion*,
because lowercase identity has an independent benefit discussed under
[the doubled hyphen alternative](#doubled-hyphen-marker-identity-stays-lowercase).

### Parentheses do not buy safety

Parentheses are legal unencoded in a URI path. RFC 3986 lists `(` and `)` among `sub-delims`, and `pchar` admits
`sub-delims`. The problem is not legality, it is that many URL libraries percent-encode them anyway, so the same name
circulates as both `user-(id)` and `user-%28id%29`. A canonical form with two spellings in the wild is not
unambiguous, which was the third of the three claimed properties.

Three further costs are observed rather than theoretical:

1. PowerShell reads an unquoted `(` as the start of a subexpression, and `cmd.exe` breaks on parentheses inside
   `for` and `if` blocks. Every filename carrying an initialism needs quoting on Windows.
2. Parentheses terminate a Markdown inline link target. This repository publishes `docs/` through Docusaurus, and
   `docs/spec/ir/schemas/v4/document-tree-files.md` already contains `user-(id).type.json` in directory listings.
3. The encoding costs two characters per initialism and requires a grammar the reader has to be taught.

### The filesystem is the real constraint, and it already fails

Two document-tree failures exist today, independent of the initialism question. Both are proven by the Windows
filesystem rules rather than judged.

`con`, `prn`, `aux`, `nul`, `com0` through `com9`, and `lpt0` through `lpt9` are reserved device names on Windows,
and the reservation applies with any extension. A Morphir type named `aux` or `con` produces `aux.type.json`, which
cannot be created. Both are plausible domain vocabulary.

The default `MAX_PATH` limit of 260 characters is reachable from nested modules, long kebab names and the
`.value.json` suffix together.

That limit is not universal, and it is no longer the common case, so the truncation budget defaults to 4000 rather
than to the most restrictive target. Making every tree pay for the least capable consumer is the wrong trade when
the payment is lossy: a truncated stem is not reversible and forces the module to carry a `fileNames` map. A
deployment bound by `MAX_PATH` lowers the budget to 200 instead.

The restrictive case is not gone. `LongPathsEnabled` is opt-in rather than default, a Win32 process must also
declare `longPathAware` in its manifest, and Git for Windows ships `core.longpaths=false`, so a stock Windows clone
of a tree written under the default budget can fail to check out.

That residual risk is why the budget is always recorded rather than inferred. A writer sets `pathBudget` in the
manifest unconditionally, so a reader that cannot satisfy it says so once, up front, and no consumer has to guess
what an unmarked tree assumed. Inferring it would reintroduce the silent portability failure this escape exists to
prevent.

Either failure forces a name-to-filename escape layer. Once the specification owns that layer, the canonical string
no longer has to satisfy the intersection of URI syntax, shell quoting and filesystem rules by itself. That is the
structural move this record makes, and everything else follows from it.

### Case-insensitive filesystems are handled by the escape, not by the alphabet

Windows NTFS is case-preserving and case-insensitive. macOS APFS is case-insensitive by default. Linux ext4 is
case-sensitive. A canonical name that uses case therefore cannot be written to disk verbatim: `value-in-USD` and
`value-in-usd` would coexist on a Linux build machine and collide on a Windows checkout.

The escape layer removes the hazard by producing filenames that are entirely lowercase. An initialism segment is
written lowercase with an `_` prefix, so `value-in-USD` becomes `value-in-_usd` and `value-in-usd` stays
`value-in-usd`. The two are distinct after case folding, and the mapping is reversible because a word segment never
contains `_`. A reserved device stem takes a trailing `_`, so `con` becomes `con_`.

### Letter runs are the wrong model, and the spec already contradicts itself

The parenthesis syntax is a marker over a deeper problem. Encoding "this is an initialism" by fragmenting a word into
single letters is a proxy, and the proxy leaks.

`docs/spec/draft/names.md` line 39 states that a `TypeVariable` canonicalizes as `"a"`. A `TypeVariable` wraps a
`Name`, and `group_consecutive_singles` in `docs/design/draft/ir/naming.md` line 427 groups any run of single-letter
words, including a run of length one. `name_from_words(["a"])` therefore produces `"(a)"`. Every single-letter type
parameter is encoded as a parenthesized initialism, and the two documents disagree about it. The same rule turns
`["point", "x", "y"]` into `point-(xy)`, rendering `pointXY`.

The model also bakes in a rendering decision that belongs to the backend. Target conventions genuinely disagree: Go
writes `HTMLParser`, Rust writes `HtmlParser` and spells its own types `Uuid` and `Io`, and the .NET Framework Design
Guidelines put two-letter acronyms in full caps (`IOStream`) while writing three letters or more in Pascal case
(`XmlDocument`). With a flag, a Rust backend renders `Html` and a Go backend renders `HTML` from one IR. With a
letter run, the letters are already committed and each backend has to rejoin them heuristically.

Finally, a letter run cannot express `IPv6`, `gRPC` or `OAuth` faithfully.

### Legacy decoding stays available and fixes the type-variable case

A v1 through v3 name decodes by collapsing each maximal run of two or more single-letter words into one initialism
word. `["value", "in", "u", "s", "d"]` becomes `value in USD`. A run of length one stays a plain word, so `["a"]`
decodes to `a` and the type-variable contradiction disappears. Encoding back to the legacy array explodes an
initialism into single letters, which is lossy only for a one-letter initialism.

## Alternatives rejected

### Parenthesized single-letter runs, as drafted for v4

Argued above. The decisive points are the false URL premise, the two spellings that inconsistent percent-encoding
produces, and the `TypeVariable` contradiction that the underlying letter-run model causes.

### Doubled hyphen marker, identity stays lowercase

Writing `value-in--usd` keeps every canonical name inside `[a-z0-9-]`. That is a real benefit: a lowercase-only
identity projects into case-insensitive targets such as SQL identifiers, DNS labels and Windows paths with no case
handling at all. The obvious objection, that a leading `--` in a filename is parsed as a command-line option, does
not survive, because the escape layer this record adopts already renames a leading initialism to `_html-parser`.

The option is therefore safe and is the named fallback. It is rejected on legibility. `value-in--usd` reads as a
typographical error, the doubled separator has to be explained to every reader, and the grammar remains bespoke where
the uppercase form is self-describing. The judgement that legibility outweighs a case-free identity is the weakest
link in this record, and it is the subject of the first unresolved question.

### Underscore prefix marker

`value-in-_usd` is unreserved in a URI, never percent-encoded, safe in every shell, and safe on every filesystem. It
fails for a specific reason: the parser already accepts `snake_case` as a permissive input format
(`docs/design/draft/ir/naming.md` line 44), where `in_usd` means two words. Reusing `_` as an initialism marker makes
that input ambiguous. The character remains the right choice inside the escape layer, where no permissive parsing
happens.

### Percent-encoding the initialism

`value-in-%55%53%44` is illegible, `%` triggers variable expansion in `cmd.exe`, and a name that is itself
percent-encoded double-encodes when placed in a URL.

### Tilde marker

`~` is unreserved in a URI and legal on every filesystem, but shells expand a leading tilde, and `*~` is a backup-file
pattern that editors write and tools ignore.

### No marker, backends consult an initialism dictionary

Pushing initialism detection to a per-backend word list keeps the IR minimal. It also makes rendering
non-deterministic across tools: a Scala backend and a TypeScript backend with different word lists disagree about the
same name, which defeats the cross-language round-trip that Morphir exists to provide.

### No marker, always render `Usd`

Deleting the feature is coherent, and Rust's own conventions show that `Usd` is a defensible rendering. It is rejected
because importing existing Go, Java or Scala code discards intent that cannot be recovered, and because generated code
for those targets reads as foreign.

## Consequences

1. The canonical `Name` grammar becomes `^SEG(-SEG)*$` where a segment is all-lowercase, all-uppercase, or all-digit.
   The `NameString` pattern in `website/static/schemas/morphir-ir-v4.yaml` line 50 and the derived `PathString` and
   `FQNameString` patterns shrink correspondingly.
2. A mixed-case segment such as `Usd` is invalid. A typo is rejected rather than silently accepted as a third
   spelling.
3. Name identity becomes case-sensitive. Equality, hashing, JSON object keys and map lookups compare case-sensitively.
   Implementations that fold case for lookup are wrong under this record.
4. `TypeVariable` canonicalizes as `a`, matching what `docs/spec/draft/names.md` already claims.
5. The document tree filename is no longer the canonical name verbatim. Tools read and write it through the escape
   function. This is a genuine loss: "the filename is the name" was a stated virtue of the v4 tree.
6. `module.json` gains the ability to record a name-to-filename mapping for the cases where escaping is not the
   identity function, which also gives the path-length truncation case somewhere to record itself.
7. A validation rule is added: within one namespace, no two names may collide after escaping. A tree that builds on
   Linux is then guaranteed to check out on Windows.
8. Rendering into a case-free target convention stops being injective. `in-usd` and `in-USD` both render `in_usd`,
   where the letter-run model produced the distinct but unidiomatic `in_usd` and `in_u_s_d`. Backends gain an
   obligation to detect collisions after case transformation and report them. This is the one respect in which the
   chosen model is weaker than the one it replaces.
9. Every published v4 example carrying `(usd)`, `(id)`, `(sdk)` or `(html)` is rewritten. The affected files are
   `docs/spec/draft/names.md`, `docs/design/draft/ir/naming.md`, `docs/spec/ir/schemas/v4/document-tree-files.md`,
   `docs/spec/draft/modules.md`, `docs/design/draft/ir/distributions.md`, `docs/design/draft/ir/modules.md`, and the
   four schema files under `website/static/schemas/`. The replacement text and the exact schema patches are drafted
   at `docs/design/proposals/ir-v4-name-encoding.md`, which also carries the Option 2 delta as an appendix.
10. v4 has not shipped, so no migration of published artifacts is owed. Legacy array decoding covers v1 through v3.

## Unresolved

Two questions decide whether this record is accepted as written or replaced by its fallback.

**Should name identity stay case-free?** Choosing case-free identity selects the doubled-hyphen form instead. The
argument for case-free is that names then project into SQL identifiers, DNS labels and case-insensitive filesystems
with no escaping at all. The argument against is that the escape layer exists regardless, so the benefit is narrower
than it looks. This record judges legibility the stronger consideration. That judgement is not proven.

**Is "the filename is the canonical name" worth keeping?** This record assumes it is already lost to Windows reserved
device names and `MAX_PATH`, and that formalizing the escape is better than leaving those two failures unhandled. If
the project instead decides to forbid reserved names and cap path length by validation, the verbatim property
survives, and the doubled-hyphen form becomes clearly correct because it needs no escape.

Unmeasured: how often initialisms actually occur in real Morphir models. If they are rare, the legibility argument
carries less weight than assumed here.

## Revisit when

- A Morphir target appears whose identifiers cannot carry case and which cannot accept an escaped projection.
- Real-world model corpora show that initialisms occur rarely enough that "always render `Usd`" costs nothing.
- Unicode is admitted into names, which reopens case folding on a much larger alphabet and invalidates the
  ASCII-only reasoning throughout this record.
