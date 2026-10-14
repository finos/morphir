# Morphir typing tools

`finos/morphir-typing-tools` is not published. It holds the tools for the SDK specification and the oracle tests
for Morphir IR type inference (`finos/morphir-typing`).

| Package | What it does | Targets |
| --- | --- | --- |
| `vspec` | Parses morphir-elm `vSpec` signatures | all four |
| `sdkgen` | Bootstraps, generates and checks the SDK specification | native only |
| `oracle` | Tests inference against the classic corpus and the fixture corpora | native only |

`sdkgen` and `oracle` are native only. `sdkgen` reads and writes files. `oracle` sets
`supported_targets = "native"` in its `moon.pkg`, so `moon test` on the other targets skips it.

## vspec

`vspec` parses the `vSpec` signature notation of morphir-elm, for example
`vSpec "map2" [ ( "f", tFun [ tVar "a", tVar "b" ] (tVar "c") ) ] (tVar "c")`. It also converts Elm names to
canonical names with `canonical_name`.

## sdkgen

`sdkgen` is an executable with three commands:

```shell
moon run pkgs/morphir-typing-tools/sdkgen --target native -- bootstrap pkgs/morphir-sdk/conformance/bindings.json pkgs/morphir-sdk-spec/sdk.scm
moon run pkgs/morphir-typing-tools/sdkgen --target native -- generate
moon run pkgs/morphir-typing-tools/sdkgen --target native -- check
```

- `bootstrap` writes `pkgs/morphir-sdk-spec/sdk.scm` from `bindings.json`. The file has the hand-written SDK
  types and the value signatures. It was run once. After that, edit `sdk.scm` by hand. If a name or a construct
  is unknown, `bootstrap` stops and lists all of them.
- `generate` writes `pkgs/morphir-sdk-spec/sdk_data.mbt` from `sdk.scm`. Run it as `mise run sdk-spec:generate`.
- `check` compares `sdk.scm` with `bindings.json` and checks that `sdk_data.mbt` is fresh. Run it as
  `mise run sdk-spec:check`. The [SDK specification README](../morphir-sdk-spec/README.md) lists what it checks.

Some morphir-elm signatures repeat a parameter name, for example `result2` twice in `Result.map3`. The IR refuses
that. A repeated name takes the next free number (`result-2` becomes `result-3`). `bootstrap` and `check` use the
same rule.

## oracle

The oracle runs `@typing.infer` over real IR and compares the result with types that other tools wrote. Run it
with:

```shell
moon test pkgs/morphir-typing-tools/oracle --target native
```

Each test passes the SDK specification (`@sdk_spec.sdk_specification()`) as a dependency, because inference has
no built-in SDK.

### The helpers

The helpers in `strip.mbt` walk each declaration with the logical path steps of
`pkgs/morphir-typing/paths.mbt`. A path in an oracle line is therefore the same path as in an inference problem.
They walk only what inference walks: expression bodies and external fallbacks of the file's own package. Inference
trusts the packages that an `Application` bundles and does not infer the value of an `IncompleteBody`, so the
helpers do not walk these either. The test "C2" pins this.

- `strip_node_types(file)` sets every node `inferred_type` to `None`. It keeps the signatures. Criterion B uses
  it.
- `strip_full(file)` is `strip_node_types`, and it also replaces every top-level signature type with an unknown
  variable: `t-0`, `t-1`, … for each declaration. Criterion A uses it.
- `compare_types(original, filled)` compares every node type and every signature type. It expands aliases from
  the SDK, the file's dependencies and the file's own package. Then it compares the types of each declaration in
  that declaration's `@typing.TypeScope`, made from the declaration in `original`. It writes one line per
  difference: `<path>: expected <t1>, found <t2>`. A top-level signature type is at `<path>:input/<i>` or
  `<path>:output`. The only differences that it allows are alias expansion and one consistent renaming per
  declaration that keeps the signature variables and the classes.
- `mutate_first_literal_type(file)` changes the type of the first `Literal` node to `String`, or to `Int` if it was
  `String`. It returns the file and the node's path.
- `mutate_first_rigid(file)` renames the signature variable in the first node type that has one, to `swapped`.
  `drop_first_class(file)` removes the `typeclass` constraint of a variable in the first node type that has one,
  when the variable's name gives no class. Each returns the file and the node's path.
- `count_untyped(file)` counts the `Value` and `Pattern` nodes with no `inferred_type`.

### The criteria

| Criterion | Fixtures | Test |
| --- | --- | --- |
| A | The Elm backend fixtures `rentals` and `shapes`, and the MoonBit fixtures `library`, `pricing`, `acceptance_library`, `invocation_library`, `conformance` and `rust_conformance` | Each original corpus passes `Check` unchanged. After `strip_full`, `Fill` succeeds, leaves no untyped node and leaves no unknown variable in any signature. |
| B | The classic morphir-elm fixtures: greeting (format 3), and rentals in formats 1 and 2 | After `strip_node_types`, `Fill` gives every node type and every signature type that morphir-elm wrote. |
| C | The same classic fixtures | `Check` returns the file unchanged. A changed literal type is `annotation_mismatch` at that node, and is the only problem. |
| C (variables) | The Elm backend fixture `shapes`, filled after `strip_node_types` | `Check` returns the filled file unchanged. A swapped signature variable (`mutate_first_rigid`) and a dropped class (`drop_first_class`) are each `annotation_mismatch` at that node, and the only problem. The classic fixtures have no type variable in a node type, so these mutations use `shapes`, whose `largest` has the rigid `a` with the class `number`. |

### Ruling 1: criterion B keeps the top-level signatures

Classic IR does not record which top-level signatures came from an Elm annotation and which ones morphir-elm
inferred. If the oracle strips them, inference finds the principal type of each body. That type is correctly more
general than an Elm annotation. For example, `request : Int -> Int -> Result String Int` with the body
`if a <= b then Ok a else Err "…"` gives `comparable -> comparable -> Result String comparable`. A record alias
parameter that the body only reads from gives an extensible record. No inference can recover a narrowing that only
the annotation states.

So criterion B uses `strip_node_types`, which keeps the top-level signatures and clears every node type. Inference must then give every node type
and every signature type that is not a placeholder, up to variable renaming and alias expansion.

### Ruling 2: morphir-elm's let placeholders

morphir-elm writes a signature for every let definition. When the Elm source has no annotation for the let, the
signature keeps the type variables that the frontend made before inference: `t` and a number, as in `t8`
(canonical `t-8`). The solved types are only on the nodes. For example, classic greeting has
`let discount = originalPrice * (discountPercent / 100)` with the output type `t8`.

Classic IR has no unknown markers, so inference would check `t8` as a rigid annotation and report
`rigid_variable`. Migration from classic IR marks the morphir-elm let placeholders (`t-<digits>`), so every caller
gets the same IR. The marker is the one that `@typing.unknown_type` writes. In criterion B,
`compare_types` compares a let-signature type that has a placeholder only outside the placeholder: each placeholder
position becomes `()` on both sides, and a placeholder row compares only the fields that the signature lists. So
`List t8` still has to be a list.

Inference does not change. A let annotation that a user wrote as `t8` would also be marked, but classic IR cannot
tell the two apart.
