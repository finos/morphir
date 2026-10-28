# Configuration compatibility corpus

`parity_test.mbt` compares the current TOML document loader with the published Moon-Lander TOML parser and
explicit-source loader. It collects every leaf-value and winning-origin difference before reporting a failure.
It also checks replacement of lists, inherited fields, scalar values and successive source origins.

The corpus embeds the three tracked `morphir*.toml` fixtures under
`apps/morphir-workbench/scripts/fixtures/folder-import/monorepo/`: the root workspace and its `core` and `utils`
members. `tests/configuration/toml-corpus.json` freezes their text and SHA-256 digests. CLI acceptance checks
that every tracked fixture is represented, each snapshot still matches its source, and the embedded MoonBit
test data matches the manifest. Update the manifest when changing a fixture, then regenerate it with:

```sh
moon tool embed --text --name toml_corpus_json --input tests/configuration/toml-corpus.json --output pkgs/morphir-engine/config/corpus_generated_test.mbt
```

Run `moon test pkgs/morphir-engine/config --target <target>` on native, JS, WASI and Wasm GC.
This is explicit-source compatibility evidence. The adoption's complete loader parity test must also exercise
the production conventions adapter once the upstream workspace discovery and format-layer support is published.
No discovery algorithm is implemented by this corpus.
