# A literal that looks like an alias

A v4 value file with three inputs of type F whose body is the string literal `{"$name":"a"}`. In the plain document
the literal is the JSON string `"{\"$name\":\"a\"}"`.

**Occurrences in first-use order.** `body` (the literal is not a position), `inputTypes`, `outputType`, then `name`.

1. F (`fqNames`) at `inputTypes/base`, `inputTypes/bonus` and `inputTypes/rebate`, O = 101 each. Id `a`: S = 264 >
   E = 106: aliased as `a`, the very id the literal spells.
2. `morphir/SDK:string#string` (`fqNames`) at `outputType`, O = 27, once. Tentative id `b`: S = 14; E = 1 + 25 + 6 =
   32. Spelled out.
3. `label` (`names`) at `name`, O = 7, once: spelled out.

The literal stays a string, written by JCS with its quotes escaped, `"{\"$name\":\"a\"}"`, and it never expands.

**Loss decision.** Overhead = 118 + 12 + 105 + 0 = 235. Savings 264 > 235, so the envelope is written, 29 bytes
smaller: 522 bytes plain, 493 bytes compacted.
