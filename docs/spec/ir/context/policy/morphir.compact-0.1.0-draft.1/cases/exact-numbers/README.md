# Exact numbers

A v4 tree value file `limits` with three inputs of type F (`base`, `bonus`, `rebate`). Its output type is the tuple
`(int, float, float, document)` and its body is a tuple of four literals: the `IntegerLiteral` 9007199254740993
(2^53 + 1), the `FloatLiteral`s `1.0` and `1e2`, and a `DocumentLiteral` whose members are not in sorted order and
which holds the numbers `1.50`, `1e3` and `0.10`.

**The written form of the plain document.** Every number keeps its lexeme from `input.json`: JCS would write
9007199254740992, `1`, `100`, `1.5`, `1000` and `0.1`, which changes the integer, turns the bare spelling of a float
into that of an integer, and loses the document's own text. The `DocumentLiteral` content keeps its member order at
every depth, `region`, `cap`, `tiers` and inside the tier `upTo`, `rate`; JCS would sort `cap` first and `rate`
before `upTo`. `inputTypes` is order-carrying and its order, `base`, `bonus`, `rebate`, is also sorted. Every other
object is sorted: `def` (inside it `ExpressionBody` before `access`; inside that `body`, `inputTypes`,
`outputType`), then `formatVersion`, then `name`.

**Occurrences in first-use order**, by offset in that written form. The body holds no typed name position: the
literals are not positions, and nothing inside a `DocumentLiteral` is one.

1. F (`fqNames`) at `inputTypes/base`, `inputTypes/bonus` and `inputTypes/rebate`, O = 101 each. Id `a`:
   S = 3 × (101 − 13) = 264 > E = 1 + 99 + 6 = 106: aliased as `a`.
2. `morphir/SDK:basics#int` (`fqNames`, 22 bytes) at `outputType/Tuple/0`, O = 24, once. Tentative id `b`:
   S = 24 − 13 = 11; E = 1 + 22 + 6 = 29. Spelled out, and `b` is not consumed.
3. `morphir/SDK:basics#float` (`fqNames`, 24 bytes) at `outputType/Tuple/1` and `/2`, O = 26 each. Tentative id `b`:
   S = 2 × (26 − 13) = 26; E = 1 + 24 + 6 = 31. Spelled out.
4. `morphir/SDK:document#document` (`fqNames`, 29 bytes) at `outputType/Tuple/3`, O = 31, once. Tentative id `b`:
   S = 18; E = 36. Spelled out.
5. `limits` (`names`) at `name`, O = 8, once. Tentative id `b`: S = −5 ≤ E = 13. Spelled out.

**Plain size**, counted over the written form:

- `{"def":{"ExpressionBody":{"body":{"Tuple":[` is 43 bytes.
- `{"Literal":{"IntegerLiteral":9007199254740993}}` is 12 + 16 + 1 + 16 + 2 = 47 bytes: `{"Literal":{` (12),
  `"IntegerLiteral"` (16), the colon, the 16-digit lexeme and `}}`.
- `{"Literal":{"FloatLiteral":1.0}}` and `{"Literal":{"FloatLiteral":1e2}}` are 12 + 14 + 1 + 3 + 2 = 32 bytes each.
- `{"Literal":{"DocumentLiteral":` is 12 + 17 + 1 = 30 bytes. The content
  `{"region":"outside-primary","cap":1.50,"tiers":[{"upTo":1e3,"rate":0.10}]}` is 74 bytes: `{` (1),
  `"region":"outside-primary"` (26), `,"cap":1.50` (11), `,"tiers":[` (10), `{"upTo":1e3` (11), `,"rate":0.10` (12)
  and `}]}` (3). Then `}}` (2): 106 bytes.
- Three commas between the four elements, and `]}` closing the tuple and `body`: 5 bytes. The body ends at
  43 + 47 + 32 + 32 + 106 + 5 = 265.
- `,"inputTypes":{` (15), `"base":` (7) + 101, `,"bonus":` (9) + 101, `,"rebate":` (10) + 101, `}` (1): 345, so 610.
- `,"outputType":{"Tuple":[` (24), `"morphir/SDK:basics#int"` (24), `,` and the float (27) twice,
  `,"morphir/SDK:document#document"` (32) and `]}` (2): 136, so 746.
- `}` (1), `,"access":"Public"` (18), `}` (1), `,"formatVersion":4` (18), `,"name":"limits"` (16) and `}` (1): 55.

So 746 + 55 = 801 bytes. JCS text of the same document would be 798 bytes (`1` is 2 shorter than `1.0`, `1.5` and
`0.1` are 1 shorter each, and `1000` is 1 longer than `1e3`), so the costs are those of the written form, not of JCS.

**Loss decision.** Overhead = 118 + 12 + (1 + 99 + 5) + 0 = 235. Savings 264 > 235, so the envelope is written, 29
bytes smaller: 801 bytes plain, 801 − 264 + 235 = 772 bytes compacted. In the compacted file each reference is 13
bytes, and the numbers and the literal's content are written exactly as in the plain document.
