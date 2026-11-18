# Writer policy `morphir.compact/0.1.0-draft.1`

This policy fixes, byte for byte, what a writer produces when it compacts the names of one Morphir file into the
envelope of `ir-context/0.1.0-draft.1` (see `../../examples/README.md`). The normative text is the `ir/name-compaction`
requirements in `openspec/changes/add-bounded-model-access/specs/ir/name-compaction/spec.md`; this page restates
them with the arithmetic the cases use. Every expected file under `cases/` was worked out by hand from this text. No
implementation produced any of them.

## Output form

- The output is the policy's **written form** of the file. Object members are sorted by their UTF-16 code units, as
  RFC 8785 (JCS) sorts them. Strings are escaped as RFC 8785 escapes them: only `"`, `\` and control characters,
  with non-ASCII written raw as UTF-8. There is no whitespace and no trailing newline. Three things are not as JCS
  writes them:
  1. **Every JSON number is written with its exact source lexeme**, the characters that spell it in the plain
     document given to the writer, and is never reformatted. JCS writes the ECMAScript form of an IEEE double, which
     changes IR values: the v4 `IntegerLiteral` 9007199254740993 would become 9007199254740992, and the
     `FloatLiteral` `1.0` would become `1`, the spelling of an integer where v4 reads a bare number by its lexeme
     (decision 0009).
  2. **The members of an order-carrying object keep their source order** (the list follows).
  3. **The content of a `DocumentLiteral` keeps its source member order and lexemes everywhere inside it.** The
     content is the JSON value of the literal's `DocumentLiteral` member, which the IR 4 schema calls "any JSON value,
     carried verbatim". Every object inside it, at any depth, keeps the member order of the plain document.

  The escaping and no-whitespace rules hold inside order-carrying objects and `DocumentLiteral` content too. The plain
  document given to the writer is JSON text, and its source lexemes and source member order are those of that text.
  A writer that builds the plain document in memory takes the text its own plain encoder writes.
- An order-carrying object is one whose member order the enclosed document's IR JSON Schema declares semantic. In IR 4
  (`website/static/schemas/morphir-ir-v4.json`) these are exactly:
  - the `inputTypes` of each value definition body, `ExpressionBody`, `NativeBody`, `ExternalBody` and
    `IncompleteBody`, wherever the body appears (a module's values, a value file's `def`, a `LetDefinition` or
    `LetRecursion` definition). The schema says: "The key order of "inputTypes" is the parameter order."
  - the object form of a `ValueSpecification`'s `inputs`, wherever the specification appears (a module
    specification's values, a value file's `spec`). The schema says: "The key order of "inputs" is the parameter
    order." (`morphir-ir-v4-document-tree-files.json` says the same of its `ValueSpecification`.)

  IR 3 has no order-carrying object: its parameters are arrays, and the objects of a v3 tree file are maps. IR 3 has
  no `DocumentLiteral` either. No object inside a `DocumentLiteral` is order-carrying; rule 3 keeps the order of all
  of them. The document order of an order-carrying object is its member order in the plain document the writer was
  given, and expansion gives the members back in that order.
- A compacted file is the envelope with exactly three members, `$schema`, `context` and `document`. Sorted, they come
  in that order, so the context always comes before the document. The writer adds no `critical` list.
- The context's tables are therefore written sorted: `fqNames`, `modulePaths`, `names`, `packagePaths`. A table with
  no entry is left out. The context holds no number and no `DocumentLiteral`, so it is written as JCS writes it.
- When the writer declines, the plain document is written in the same written form.
- Every size below is the UTF-8 byte length of text in the written form, and a number costs the bytes of its lexeme.
  Member order does not change a byte length, but a lexeme can be longer or shorter than the JCS number: the costs
  are those of the written form, not of JCS (case `exact-numbers` is 801 bytes plain, where its JCS text is 798).
  Expansion gives back each number with its lexeme and the `DocumentLiteral` content with its member order.

## Candidates

A candidate is a pair of a table and an expanded spelling. Its occurrences are the outermost typed name positions of
the plain document that hold it: a position inside another typed position (such as the package path inside a classic
FQName) is not a separate occurrence. The occurrence size `O` is the size of the value as the plain document writes
it: `len(s) + 2` for a canonical string, or the size of the classic word arrays in a classic v3 slot. One candidate can
have occurrences of both kinds in a v3 tree file.

## Order and ids

Candidates are taken in first-use order: by the byte offset, in the written form of the plain document, at which
their first occurrence starts. Inside an order-carrying object that is document order, not sorted order, and every
number before an occurrence counts the bytes of its lexeme. Then by the ordinal (UTF-16) order of the spelling, and
then by table, in the order `names`, `packagePaths`, `modulePaths`, `fqNames`. Two outermost positions never start
at the same offset, so in draft.1 the first key decides every order; the further keys make the order total by
definition, and no case can exercise them.

Ids are given out as `a`, `b`, … `z`, `aa`, `ab`, … `az`, `ba`, … `zz`, `aaa`, …: the bijective base-26 numerals over
`a`–`z`, one sequence shared by all tables. A candidate takes the next id only if it is aliased; a candidate that
stays spelled out consumes nothing.

## Costs and the two decisions

Every cost is the exact number of UTF-8 bytes in a piece of written-form text. `len(x)` is the byte length of the
bare text of `x` (an id, a spelling `s` or a table name), **without** quotes. Ids and spellings are ASCII under the
envelope schema's patterns, so the written form has them unescaped and `len(x)` is their character count:
`len(fqNames)` is 7, and `len(a)` is 1. Each term below is the written-form text in its second column; the third
column says which quotes, colons, commas and braces that text holds, and only those are counted. None of the terms
holds a number.

| Term | Text counted | Quotes, colon, comma, braces | Bytes |
| --- | --- | --- | --- |
| `R`, a reference | `{"$name":"<id>"}` | 4 quotes, 1 colon, no comma, 2 braces | `12 + len(id)` (13 for a one-letter id) |
| `O`, an occurrence | the value as the plain document writes it: `"<s>"`, or the classic word arrays | 2 quotes for a string; for classic arrays, every bracket, quote and comma inside them | `len(s) + 2` for a string |
| `S`, the saving | `Σ (O − R)` over the candidate's occurrences | — | — |
| `E`, an entry with its separator | `"<id>":"<s>",` | 4 quotes, 1 colon, 1 comma, no braces | `len(id) + len(s) + 6` |
| `T`, a table header | `"<table>":{}` | 2 quotes, 1 colon, no comma, 2 braces | `len(table) + 5`: `fqNames` 12, `modulePaths` 16, `names` 10, `packagePaths` 17 |
| An entry in the envelope | `"<id>":"<s>"` | 4 quotes, 1 colon, no comma, no braces | `len(id) + len(s) + 5` |
| The separators | `,` between two entries of a table and between two tables | 1 comma each | `k − 1` for `k` entries |
| The fixed envelope | `{"$schema":"` (12), the URL (79), `","context":{` (13), `},"document":` (13), `}` (1) | 8 quotes, 3 colons, 2 commas, 4 braces | 118 |

1. **Alias decision.** In order, each candidate is aliased if and only if `S > E`. When `S = E` it stays spelled out.
   A table that already holds 16,384 entries takes no more; later candidates of that table stay spelled out.
2. **Loss decision.** Let `Σ S` be the savings of the aliased candidates, and let the overhead be
   `H = 118 + Σ_tables T + Σ_entries (len(id) + len(s) + 5) + (k − 1)`, summed over the tables that hold an entry and
   over the `k` entries. The compacted file is `plain − Σ S + H` bytes. The writer writes the envelope only when
   `Σ S > H`, so the compacted file is smaller than the plain one. When `Σ S = H` the two are the same size and the
   writer declines. Otherwise, or when no candidate is aliased, it writes the plain document in the written form,
   and its result says that no alias was worth its cost. `loss-boundary-declined` (`Σ S = H`) and
   `loss-boundary-accepted` (`Σ S = H + 1`) pin the boundary.

## Spellings used by the cases

| Symbol | Spelling | `len(s)` | `O` as a string | `O` as classic arrays |
| --- | --- | --- | --- | --- |
| F | `acme/order-management:pricing/discount-rules#discounted-amount-before-regional-sales-tax-adjustment` | 99 | 101 | 141 |
| G | `acme/order-management:pricing/discount-rules#loyalty-discount-rate-for-premium-members` | 86 | 88 | — |
| P | `acme/orders:pricing#net-price` | 29 | 31 | — |
| N | `discounted-amount-before-regional-sales-tax-adjustment` (a name) | 54 | 56 | 70 |
| M | `morphir/SDK:basics#multiply` | 27 | 29 | 55 |
| X | `acme/order-management:pricing/discount-rules#discounted-amount-before-regional-sales-tax-adjustment-for-orders-shipped-to-customers-outside-the-primary-region` | 158 | 160 | — |
| Y | X with `domestic` for `primary` | 159 | 161 | — |

The classic form of F is
`[[["acme"],["order","management"]],[["pricing"],["discount","rules"]],["discounted","amount","before","regional","sales","tax","adjustment"]]`:
33 bytes of package path, 34 of module path, 70 of name, two commas and two brackets.

## Cases

`cases.json` lists the cases. Each directory holds `input.json` (the plain document, formatted for reading),
`expected.json` (the exact output bytes) and a `README.md` with the computation. The sizes in each README were
computed by hand and then compared with the byte length of the written files.

| Case | Shows |
| --- | --- |
| `v4-single-file`, `v3-single-file` | A single-file model stays one file |
| `v4-manifest`, `v3-manifest` | A manifest never repeats a package path, so nothing is aliased and the output is the plain file in the written form |
| `v4-module`, `v3-module` | An inline module file |
| `v4-type`, `v3-type` | A type file; in v3 the classic FQName is 141 bytes, so two uses pay for the envelope |
| `v4-value`, `v3-value` | A value file; a rejected candidate consumes no id |
| `name-used-once` | An FQName used once stays spelled out beside an aliased one |
| `non-ascii-content` | A doc string with `é` and `è` is measured and written as raw UTF-8 |
| `alias-allocation-order` | Ids follow first use in the written form (here JCS order), not the order of the input file |
| `tie` | A saving exactly equal to the entry's cost stays spelled out |
| `table-order` | Ids run across tables in first-use order; JCS writes `fqNames` before `names`; a classic FQName used once is worth an alias |
| `look-alike-literal` | A string literal holding `{"$name":"a"}` stays a literal beside a real alias `a` |
| `loss` | An alias worth its entry, but not the envelope: the output is the plain file |
| `loss-boundary-declined` | Savings exactly equal to the overhead (294): the output is the plain file |
| `loss-boundary-accepted` | Savings one byte above the overhead (296 > 295): the envelope is written, one byte smaller |
| `ordered-inputs` | Parameters `rate`, `amount`, `discount`, `limit` keep their order in `inputTypes`, and ids follow first use in that order |
| `exact-numbers` | The `IntegerLiteral` 9007199254740993, the `FloatLiteral`s `1.0` and `1e2` and an unsorted `DocumentLiteral` holding `1.50`, `1e3` and `0.10` are written as `input.json` writes them, and the costs count their lexemes |

`bun test tools/check-ir-context.test.ts` checks only that each `expected.json` is in the written form (sorted
members, except that each order-carrying object and all `DocumentLiteral` content follow the member order of
`input.json`, and every number spelled as `input.json` spells it), that a compacted one satisfies the envelope schema
and a plain one has no envelope, and that each input is a valid plain document where a JSON Schema exists for it. It
never computes an expected file.
