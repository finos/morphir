# Configuration compatibility corpus

`../workspace/parity_test.mbt` compares the frozen former TOML loader with the published Moon-Lander TOML parser and
explicit-source loader. It collects every leaf-value and winning-origin difference before reporting a failure.
It also checks replacement of lists, inherited fields, scalar values and successive source origins.

The corpus embeds the three tracked `morphir*.toml` fixtures under
`apps/morphir-workbench/scripts/fixtures/folder-import/monorepo/`: the root workspace and its `core` and `utils`
members. `tests/configuration/toml-corpus.json` freezes their canonical LF text and UTF-8 SHA-256 digests.
Checkout CRLF pairs are normalized before comparison and hashing. CLI acceptance checks
that every tracked fixture is represented, each snapshot still matches its source, and the embedded MoonBit
test data matches the manifest. Update the manifest when changing a fixture, then regenerate it with:

```sh
moon tool embed --text --name toml_corpus_json --input tests/configuration/toml-corpus.json --output pkgs/morphir-engine/workspace/corpus_generated_test.mbt
```

Run `moon test pkgs/morphir-engine/config pkgs/morphir-engine/workspace --target <target>` on native, JS, WASI and Wasm GC.
The workspace suite also compares every effective leaf and origin from the production conventions adapter
with the former loader. The former parser and merge live only in `workspace/old_loader_test.mbt`; production
configuration delegates to Moon-Lander. No discovery algorithm is implemented by the oracle.
