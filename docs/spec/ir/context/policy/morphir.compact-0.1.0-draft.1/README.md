# Writer policy `morphir.compact/0.1.0-draft.1`

This policy fixes, byte for byte, what a writer produces when it compacts the names of one Morphir file into the
envelope of `ir-context/0.1.0-draft.1` (see `../../examples/README.md`). The normative text is the `ir/name-compaction`
requirements in `openspec/changes/add-bounded-model-access/specs/ir/name-compaction/spec.md`; this page restates
them with the arithmetic the cases use. Every expected file under `cases/` was worked out by hand from this text. No
implementation produced any of them.

## Output form

- The output is the RFC 8785 canonical JSON (JCS) of the file: object members sorted by their UTF-16 code units, no
  whitespace, strings with only `"`, `\` and control characters escaped (non-ASCII written raw as UTF-8), numbers in
  the ECMAScript form. There is no trailing newline.
- A compacted file is the envelope with exactly three members, `$schema`, `context` and `document`. JCS sorts them in
  that order, so the context always comes before the document. The writer adds no `critical` list.
- The context's tables are therefore written in JCS order: `fqNames`, `modulePaths`, `names`, `packagePaths`. A table
  with no entry is left out.
- Every size below is the UTF-8 byte length of JCS text.

## Candidates

A candidate is a pair of a table and an expanded spelling. Its occurrences are the outermost typed name positions of
the plain document that hold it: a position inside another typed position (such as the package path inside a classic
FQName) is not a separate occurrence. The occurrence size `O` is the size of the value as the plain document writes
it: `len(s) + 2` for a canonical string, or the size of the classic word arrays in a classic v3 slot. One candidate can
have occurrences of both kinds in a v3 tree file.

## Order and ids

Candidates are taken in first-use order: by the byte offset, in the JCS text of the plain document, at which their
first occurrence starts. Then by the ordinal (UTF-16) order of the spelling, and then by table, in the order `names`,
`packagePaths`, `modulePaths`, `fqNames`. Two outermost positions never start at the same offset, so in draft.1 the
first key decides every order; the further keys make the order total by definition, and no case can exercise them.

Ids are given out as `a`, `b`, … `z`, `aa`, `ab`, … `az`, `ba`, … `zz`, `aaa`, …: the bijective base-26 numerals over
`a`–`z`, one sequence shared by all tables. A candidate takes the next id only if it is aliased; a candidate that
stays spelled out consumes nothing.

## Costs and the two decisions

Every cost is the exact number of UTF-8 bytes in a piece of JCS text. `len(x)` is the byte length of the bare text of
`x` (an id, a spelling `s` or a table name), **without** quotes. Ids and spellings are ASCII under the envelope
schema's patterns, so JCS writes them unescaped and `len(x)` is their character count: `len(fqNames)` is 7, and
`len(a)` is 1. Each term below is the JCS text in its second column; the third column says which quotes, colons,
commas and braces that text holds, and only those are counted.

| Term | JCS text counted | Quotes, colon, comma, braces | Bytes |
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
   writer declines. Otherwise, or when no candidate is aliased, it writes the plain document as JCS, and its result
   says that no alias was worth its cost. `loss-boundary-declined` (`Σ S = H`) and `loss-boundary-accepted`
   (`Σ S = H + 1`) pin the boundary.

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
| `v4-manifest`, `v3-manifest` | A manifest never repeats a package path, so nothing is aliased and the output is the plain JCS file |
| `v4-module`, `v3-module` | An inline module file |
| `v4-type`, `v3-type` | A type file; in v3 the classic FQName is 141 bytes, so two uses pay for the envelope |
| `v4-value`, `v3-value` | A value file; a rejected candidate consumes no id |
| `name-used-once` | An FQName used once stays spelled out beside an aliased one |
| `non-ascii-content` | A doc string with `é` and `è` is measured and written as raw UTF-8 |
| `alias-allocation-order` | Ids follow first use in JCS order, not the order of the input file |
| `tie` | A saving exactly equal to the entry's cost stays spelled out |
| `table-order` | Ids run across tables in first-use order; JCS writes `fqNames` before `names`; a classic FQName used once is worth an alias |
| `look-alike-literal` | A string literal holding `{"$name":"a"}` stays a literal beside a real alias `a` |
| `loss` | An alias worth its entry, but not the envelope: the output is the plain file |
| `loss-boundary-declined` | Savings exactly equal to the overhead (294): the output is the plain file |
| `loss-boundary-accepted` | Savings one byte above the overhead (296 > 295): the envelope is written, one byte smaller |

`bun test tools/check-ir-context.test.ts` checks only that each `expected.json` is JCS, that a compacted one
satisfies the envelope schema and a plain one has no envelope, and that each input is a valid plain document where a
JSON Schema exists for it. It never computes an expected file.
