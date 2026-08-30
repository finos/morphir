---
title: IR v4 name canonicalization and initialism encoding
sidebar_label: IR v4 name encoding
status: proposed
tracking:
  decision: kb/bundles/morphir/morphir-ir/decisions/0001-name-canonicalization-and-initialism-encoding.md
  supersedes_sections:
    spec: docs/spec/draft/names.md
    design: docs/design/draft/ir/naming.md
    schemas: website/static/schemas/morphir-ir-v4.yaml
---

# IR v4 name canonicalization and initialism encoding

Proposed replacement for the naming sections of the v4 specification, with the exact schema patches.

:::caution Applied
Decision Record 0001 is `Accepted`. The specification page [Naming](../../spec/draft/names.md) describes this
encoding, the four schema files under `website/static/schemas/` carry the new patterns, the reference implementation
in `ecosystem/morphir-rust/crates/morphir-core/src/naming/` follows it, and the
[conformance corpus](../../spec/ir/fixtures/naming-conformance.json) is generated and run against it.

Still carrying the retired parenthesized encoding, as narrative rather than as normative rules:
`docs/design/draft/ir/naming.md`, and the example-bearing pages listed in
[section 10](#10-files-to-change-when-this-is-accepted).
:::

## What changes

Three layers change together, because they were previously conflated into one string.

| Layer | Current v4 draft | Proposed |
| ----- | ---------------- | -------- |
| Model | An initialism is a run of single-letter words: `["value", "in", "u", "s", "d"]` | An initialism is a word carrying a flag: `["value", "in", initialism("usd")]` |
| Canonical string | The run is wrapped in parentheses: `value-in-(usd)` | The segment is written uppercase: `value-in-USD` |
| Document tree | The canonical string is the filename: `value-in-(usd).value.json` | The filename is a reversible escape: `value-in-_usd.value.json` |

The short reasons: RFC 3986 makes a URI path case-sensitive, so the premise that forced parentheses does not hold;
parentheses are percent-encoded inconsistently by URL libraries, so the canonical form circulates in two spellings;
and the document tree needs an escape layer regardless, because Windows reserves `con`, `aux`, `nul` and their
siblings as device names and caps default paths at 260 characters.

The body below is written against **Option 1 (uppercase segments)**, the recommended form.
[Appendix A](#appendix-a-option-2-delta-doubled-hyphen) gives the complete delta for **Option 2 (doubled hyphen)**,
which keeps identity case-free. The filesystem escape in section 6 is identical under both, so only sections 3, 4
and 8 differ.

## 1. Abstract model

A `Name` is a non-empty sequence of segments. A segment is a lowercase alphanumeric token plus a class.

```text
Name     = NonEmpty[Segment]
Segment  = Word(text) | Initialism(text)
text     = 1*( %x61-7A / %x30-39 )      ; [a-z0-9]+, stored lowercase
```

The class is the whole of the change from v1 through v3. An initialism is no longer a run of single-letter words; it
is one word that carries a flag. The text is stored case-normalized, so rendering rather than storage decides how an
initialism appears in a target language.

`TypeVariable` wraps a `Name` unchanged. A single-letter type parameter is `Word("a")` and canonicalizes as `a`.
That resolves a contradiction in the current draft: `docs/spec/draft/names.md` states that a `TypeVariable`
serializes as `"a"`, but `group_consecutive_singles` in `docs/design/draft/ir/naming.md` groups any run of
single-letter words including a run of length one, so `name_from_words(["a"])` produces `"(a)"`.

## 2. What each layer is for

| Layer | Form | Used for |
| ----- | ---- | -------- |
| Canonical string | `value-in-USD` | Identity, equality, JSON object keys, `FQName`, identity URIs |
| Structured segments | `[Word("value"), Word("in"), Initialism("usd")]` | Rendering to a target naming convention |
| Escaped filename | `value-in-_usd` | The document tree, and any case-insensitive target |

Keeping these separate is the point. One string cannot satisfy URI syntax, shell quoting and Windows filesystem
rules at once without becoming unreadable, which is what produced `value-in-(usd)`.

## 3. Canonical grammar

```abnf
name       = segment *( "-" segment )
segment    = word / initialism
word       = 1*( LOWER / DIGIT )
initialism = 1*( UPPER / DIGIT )

path       = name *( "/" name )
qname      = path "#" name
fqname     = path ":" path "#" name

LOWER      = %x61-7A   ; a-z
UPPER      = %x41-5A   ; A-Z
DIGIT      = %x30-39   ; 0-9
```

A segment is either all lowercase or all uppercase, with digits permitted in both. A mixed-case segment such as
`Usd` is **invalid**, so a casing typo is rejected rather than silently admitted as a third spelling.

A segment made only of digits matches both productions. It is classified as a `Word`. That is the only
classification rule the grammar itself does not carry.

### Regular expressions

The segment, used throughout:

```text
([a-z0-9]+|[A-Z0-9]+)
```

Expanded for the schema:

```text
Name  ^([a-z0-9]+|[A-Z0-9]+)(-([a-z0-9]+|[A-Z0-9]+))*$

Path  ^([a-z0-9]+|[A-Z0-9]+)(-([a-z0-9]+|[A-Z0-9]+))*
      (/([a-z0-9]+|[A-Z0-9]+)(-([a-z0-9]+|[A-Z0-9]+))*)*$
```

`FQName` is `Path` `:` `Path` `#` `Name`, written out in section 8. Compare the current `Name` pattern, which has to
escape parentheses and nest two alternations:

```text
^([a-z0-9]+|\([a-z0-9]+\))(-([a-z0-9]+|\([a-z0-9]+\)))*$
```

### Examples

| Canonical | Segments |
| --------- | -------- |
| `user-account` | `Word(user)`, `Word(account)` |
| `value-in-USD` | `Word(value)`, `Word(in)`, `Initialism(usd)` |
| `get-HTML` | `Word(get)`, `Initialism(html)` |
| `my-API-client` | `Word(my)`, `Initialism(api)`, `Word(client)` |
| `user-ID` | `Word(user)`, `Initialism(id)` |
| `morphir/SDK` | path: `Word(morphir)` then `Initialism(sdk)` |
| `US/FR2052A/data-tables` | path: `Initialism(us)`, `Initialism(fr2052a)`, then `Word(data)` `Word(tables)` |
| `a` | `Word(a)`, a type variable rather than an initialism |
| `Usd` | invalid, mixed case |
| `value-in-(usd)` | invalid, parentheses are no longer in the grammar |

## 4. Parsing

`name_from_string` accepts the canonical form first. When the input is not canonical, these permissive formats are
recognized as a convenience for hand-authored input.

| Input format | Input | Segments | Canonical |
| ------------ | ----- | -------- | --------- |
| canonical | `value-in-USD` | `value`, `in`, initialism `usd` | `value-in-USD` |
| kebab-case | `value-in-usd` | three words | `value-in-usd` |
| snake_case | `value_in_usd` | three words | `value-in-usd` |
| camelCase | `valueInUsd` | three words | `value-in-usd` |
| camelCase with run | `valueInUSD` | `value`, `in`, initialism `usd` | `value-in-USD` |
| PascalCase | `ValueInUSD` | `value`, `in`, initialism `usd` | `value-in-USD` |

The camelCase splitter is the only interesting case. It splits before an uppercase letter that follows a lowercase
letter or a digit, and treats a run of two or more uppercase letters as one `Initialism`, ending that run one letter
early when the next character is lowercase. `parseHTMLDocument` yields `parse`, initialism `html`, `document`. A run
of one uppercase letter is a `Word`.

`split_camel_case` in `docs/design/draft/ir/naming.md` is currently a placeholder that returns its input unsplit. It
needs a real implementation whichever option is adopted.

## 5. Rendering

A backend receives segments and applies its own convention to each `Initialism`. This is what the flag buys: one IR
renders idiomatically for targets that disagree with each other. Go writes `HTMLParser`; Rust writes `HtmlParser`
and spells its own types `Uuid` and `Io`; the .NET Framework Design Guidelines put two-letter acronyms in full caps
(`IOStream`) and write three letters or more in Pascal case (`XmlDocument`).

| Canonical | camelCase (Go style) | PascalCase (Go style) | PascalCase (Rust or .NET style) | snake_case | SCREAMING_SNAKE |
| --------- | -------------------- | --------------------- | ------------------------------- | ---------- | --------------- |
| `in-usd` | `inUsd` | `InUsd` | `InUsd` | `in_usd` | `IN_USD` |
| `in-USD` | `inUSD` | `InUSD` | `InUsd` | `in_usd` | `IN_USD` |
| `get-HTML` | `getHTML` | `GetHTML` | `GetHtml` | `get_html` | `GET_HTML` |
| `my-API-client` | `myAPIClient` | `MyAPIClient` | `MyApiClient` | `my_api_client` | `MY_API_CLIENT` |
| `IO-error` | `ioError` | `IOError` | `IoError` | `io_error` | `IO_ERROR` |

Two rules a backend needs:

**A leading initialism in camelCase is lowercased whole.** `IO-error` renders `ioError`, not `iOError`.

**Rendering into a case-free convention is not injective.** `in-usd` and `in-USD` both render `in_usd`. Under the
letter-run model they rendered `in_usd` and `in_u_s_d`, which were distinct but not idiomatic. Backends must detect
collisions after transformation and report them. This is a real behavior change, and the one place where the
proposed model is weaker than the current one.

## 6. Filesystem escape

The document tree stores an escaped projection of a name rather than the canonical name. The escape exists for three
reasons, only one of which involves initialisms.

1. Case-insensitive filesystems cannot hold both `value-in-USD` and `value-in-usd`. Windows NTFS is case-preserving
   and case-insensitive; macOS APFS is case-insensitive by default; Linux ext4 is case-sensitive. Without an escape,
   a tree that builds on Linux fails to check out on Windows.
2. Windows reserves `con`, `prn`, `aux`, `nul`, `com0` through `com9`, and `lpt0` through `lpt9` as device names, and
   the reservation applies with any extension. A type named `aux` produces `aux.type.json`, which cannot be created.
3. The default `MAX_PATH` of 260 characters is reachable from nested modules plus long names plus `.value.json`.

Reasons 2 and 3 apply to the current v4 draft as it stands. They are unhandled today.

### escape

```text
escape(name):
    stem = join("-", for each segment:
                        Word(t)       -> t
                        Initialism(t) -> "_" + t)
    if lowercase(stem) is a reserved device name:
        stem = stem + "_"
    return stem
```

Every escaped stem matches `^_?[a-z0-9]+(-_?[a-z0-9]+)*_?$` and is entirely lowercase, so a case-insensitive
filesystem distinguishes two escaped stems exactly when they differ.

`escape` applies to every path segment, not only to leaf names. A module directory named `aux` is as unopenable as a
file named `aux.type.json`.

### unescape

```text
unescape(stem):
    if stem ends with "_": stem = drop last character
    return for each part in split(stem, "-"):
               part starts with "_" -> Initialism(drop first character)
               otherwise            -> Word(part)
```

`escape` is injective, so `unescape(escape(n))` returns `n`. A word segment never contains `_`, and no non-reserved
escaped stem ends in `_`, so neither marker is ambiguous.

### Path length

When the path from the distribution root would exceed 200 characters, the stem is truncated to fit and suffixed with
`__` followed by the first 8 lowercase hex digits of the SHA-256 of the untruncated escaped stem. The `__` sequence
cannot occur otherwise, because `_` appears only as a segment prefix and segments are separated by `-`.

A truncated name is not recoverable from its filename. When any name in a module is truncated, that module's
`module.json` must carry a `fileNames` map from canonical name to filename stem.

```json
{
  "formatVersion": 4,
  "path": "my-org/domain",
  "types": ["some-extremely-long-canonical-type-name-that-overflows"],
  "fileNames": {
    "some-extremely-long-canonical-type-name-that-overflows": "some-extremely-long-canonical__3f9a1c04"
  }
}
```

### Worked example

| Canonical name | Filename stem | File |
| -------------- | ------------- | ---- |
| `user` | `user` | `user.type.json` |
| `user-ID` | `user-_id` | `user-_id.type.json` |
| `value-in-USD` | `value-in-_usd` | `value-in-_usd.value.json` |
| `get-HTML` | `get-_html` | `get-_html.value.json` |
| `aux` | `aux_` | `aux_.type.json` |
| `CON` | `_con` | `_con.type.json` |

```text
.morphir-dist/
├── manifest.json
└── pkg/
    └── my-org/
        └── my-project/
            └── domain/
                ├── module.json
                ├── user.type.json            # name: "user"
                ├── user-_id.type.json        # name: "user-ID"
                └── value-in-_usd.value.json  # name: "value-in-USD"
```

The `name` field inside each file holds the canonical name. The filename holds the escaped stem. The current
"`name` must match the filename" rule in `docs/spec/ir/schemas/v4/document-tree-files.md` becomes "`escape(name)`
must match the filename stem".

### Validation rule

Within one module, the escaped stems of all types must be unique, and the escaped stems of all values must be
unique. Because `escape` is injective and its output is all lowercase, satisfying this rule guarantees that a tree
written on Linux checks out on Windows and macOS.

## 7. URI and Locator

The existing `Locator` split already carries this distinction and needs no structural change, only a stated rule.

- `ByIdentity(FQName)` uses canonical names: `morphir/SDK:list#map`.
- `ByUri(Uri)` addresses the document tree and uses escaped stems:
  `morphir://pkg/my-org/domain/value-in-_usd.value.json`.

`Uri.name` therefore holds an escaped stem rather than a `Name`. Its type should change to a distinct `FileStem`, or
the field should be documented as escaped.

## 8. Schema patch

These replace the corresponding definitions in `website/static/schemas/morphir-ir-v4.yaml`. The `.json` mirror and
the two `morphir-ir-v4-document-tree-files` files take the same substitutions.

```yaml
  NameString:
    type: string
    pattern: "^([a-z0-9]+|[A-Z0-9]+)(-([a-z0-9]+|[A-Z0-9]+))*$"
    description: |
      Canonical string representation of a name: segments joined by "-".
      A segment is all-lowercase (a word) or all-uppercase (an initialism).
      Digits are permitted in both; a digits-only segment is a word.
      A mixed-case segment such as "Usd" is invalid.
    examples: ["my-name", "user-ID", "value-in-USD", "get-HTML", "price-per-unit"]

  Name:
    oneOf:
      - $ref: "#/definitions/NameString"
      - type: array
        items:
          type: string
          pattern: "^[a-z][a-z0-9]*$"
        minItems: 1
        description: |
          Legacy v1-v3 array representation. On decode, each maximal run of two or
          more single-letter entries collapses into one initialism; a run of one
          stays a word. ["value","in","u","s","d"] decodes to "value-in-USD",
          and ["a"] decodes to "a".
        examples: [["my", "name"], ["value", "in", "u", "s", "d"]]

  PathString:
    type: string
    pattern: "^([a-z0-9]+|[A-Z0-9]+)(-([a-z0-9]+|[A-Z0-9]+))*(/([a-z0-9]+|[A-Z0-9]+)(-([a-z0-9]+|[A-Z0-9]+))*)*$"
    description: |
      Canonical string representation of a path (package or module path).
      Segments are Names joined by forward slashes.
    examples: ["morphir/SDK", "my-org/domain/users", "US/FR2052A/data-tables"]

  FQNameString:
    type: string
    pattern: "^([a-z0-9]+|[A-Z0-9]+)(-([a-z0-9]+|[A-Z0-9]+))*(/([a-z0-9]+|[A-Z0-9]+)(-([a-z0-9]+|[A-Z0-9]+))*)*:([a-z0-9]+|[A-Z0-9]+)(-([a-z0-9]+|[A-Z0-9]+))*(/([a-z0-9]+|[A-Z0-9]+)(-([a-z0-9]+|[A-Z0-9]+))*)*#([a-z0-9]+|[A-Z0-9]+)(-([a-z0-9]+|[A-Z0-9]+))*$"
    description: |
      Fully-qualified name in canonical string format: "package:module#name".
    examples: ["morphir/SDK:list#map", "morphir/SDK:basics#int", "my-org/domain:users#create-user"]

  FileStem:
    type: string
    pattern: "^_?[a-z0-9]+(-_?[a-z0-9]+)*_?$"
    description: |
      Escaped projection of a Name onto the document tree. All lowercase, so it is
      stable on case-insensitive filesystems. An initialism segment carries a "_"
      prefix; a stem colliding with a Windows reserved device name carries a "_"
      suffix.
    examples: ["user", "user-_id", "value-in-_usd", "aux_"]
```

The annotation shorthand pattern in the same file also carries the parenthesis character class and changes to:

```yaml
        pattern: "^[a-zA-Z0-9-/]+:[a-zA-Z0-9-/]+#[a-zA-Z0-9-]+(:.+)?$"
```

## 9. Conformance corpus

The [name-encoding conformance corpus](../../spec/ir/fixtures/naming-conformance.json) records the expected
canonical string, escaped filename stem, rendered forms and legacy array decoding for every case in this document,
under **both** encodings. Implementations run it rather than reimplementing the expectations.

| Section | Covers |
| ------- | ------ |
| `roundTripCases` | Segments to canonical, escaped stem, and five rendering conventions |
| `legacyDecodeCases` | v1 through v3 arrays to segments, including the run-of-one rule |
| `rejectCases` | Inputs that are invalid, recorded per style |
| `pathCases`, `fqNameCases` | Composition and the resulting document-tree path |

Two limits are recorded in the file itself. Path-length truncation is not covered, because it depends on a SHA-256
digest that the Morphir SDK cannot express, so those cases are host-verified. The legacy array `["f","r","2052","a"]`
is inherently ambiguous, because the multi-character token `2052` breaks the letter run; the corpus records the
deterministic result and implementations match it rather than guessing.

Carrying both encodings in one corpus means an implementation that flips the constant described in
`kb/bundles/morphir/morphir-ir/decisions/0002-both-name-encodings-behind-one-switch.md` needs no new fixtures.

## 10. Files to change when this is accepted

| File | Change |
| ---- | ------ |
| `docs/spec/draft/names.md` | Sections 1 through 7 above; drop the parenthesis tables and the abbreviation section |
| `docs/design/draft/ir/naming.md` | The design-decisions table, the Gleam model, the encode and decode helpers, and a real `split_camel_case` |
| `docs/spec/ir/schemas/v4/document-tree-files.md` | The filename rule, every `user-(id)` and `value-in-(usd)` example, and the file-naming validation lists |
| `docs/spec/draft/modules.md` | Parenthesized examples |
| `docs/design/draft/ir/distributions.md` | Parenthesized examples |
| `docs/design/draft/ir/modules.md` | Parenthesized examples |
| `website/static/schemas/morphir-ir-v4.yaml` and `.json` | Section 8 |
| `website/static/schemas/morphir-ir-v4-document-tree-files.yaml` and `.json` | Section 8 |
| `website/src/components/ir-checker/ValidationCard.tsx` | Sample names shown to the user |
| `.claude/skills/technical-writer/references/spec-design-consistency.md` | The naming consistency rule it encodes |

v4 has not shipped, so no migration of published artifacts is owed. Legacy array decoding covers v1 through v3.

## Appendix A: Option 2 delta (doubled hyphen)

Adopt this instead if identity should stay case-free. Sections 1, 2, 5, 6, 7 and 9 are unchanged. In particular the
filesystem escape and every filename are identical, because both options escape an initialism to `_` followed by its
lowercase text.

### Section 3 becomes

```abnf
name       = [ "--" ] segment *( sep segment )
sep        = "--" / "-"
segment    = 1*( LOWER / DIGIT )
```

A doubled separator marks the following segment as an initialism. A leading `--` marks the first segment.

```text
Name  ^(--)?[a-z0-9]+(--?[a-z0-9]+)*$

Path  ^(--)?[a-z0-9]+(--?[a-z0-9]+)*(/(--)?[a-z0-9]+(--?[a-z0-9]+)*)*$
```

| Canonical | Segments |
| --------- | -------- |
| `value-in--usd` | `Word(value)`, `Word(in)`, `Initialism(usd)` |
| `--html-parser` | `Initialism(html)`, `Word(parser)` |
| `my--api-client` | `Word(my)`, `Initialism(api)`, `Word(client)` |
| `morphir/--sdk` | path: `Word(morphir)` then `Initialism(sdk)` |
| `a` | `Word(a)` |

### Section 4 becomes

Identical, except that the canonical column reads `value-in--usd`. An empty segment is invalid in both options, so a
kebab-case input containing `--` parses as an initialism marker rather than as an empty segment.

### Section 8 becomes

```yaml
  NameString:
    type: string
    pattern: "^(--)?[a-z0-9]+(--?[a-z0-9]+)*$"
    description: |
      Canonical string representation of a name: segments joined by "-".
      A doubled separator marks the following segment as an initialism.
    examples: ["my-name", "user--id", "value-in--usd", "--html-parser"]

  PathString:
    type: string
    pattern: "^(--)?[a-z0-9]+(--?[a-z0-9]+)*(/(--)?[a-z0-9]+(--?[a-z0-9]+)*)*$"
    examples: ["morphir/--sdk", "my-org/domain/users", "--us/--fr2052a/data-tables"]
```

`FQNameString` composes the two in the same shape as section 8.

### What Option 2 costs and buys

`value-in--usd` reads as a typographical error on first encounter, and the doubled separator has to be taught.
Against that, every canonical name stays inside `[a-z0-9/-]`, so names project into SQL identifiers, DNS labels and
case-insensitive targets with no case handling, and identity comparison cannot be got wrong by a consumer that folds
case.

The objection that a leading `--` in a filename is parsed as a command-line option does not apply, because the
escape layer already renames a leading initialism to `_html-parser`.
