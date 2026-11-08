# Rust extension qualification fixtures

`mise run test:cli-extension-model-line` compiles `models.rs` and generates from
the result with the published Rust extension `0.4.0`.

The three source files are the golden files of the extension's own tests, copied
unchanged from `crates/morphir-rust-binding/tests/fixtures/model/` of
finos/morphir-rust at `0716e22a04728ddf883fc144bffb6cb52fce3102`, the commit of
the tag `extension/rust/v0.4.0` (Apache-2.0):

- `models.rs`, package `acme/example`: one document, because the extension does
  not claim `multiDocument`.
- `compiled-ir-v4.json`: the IR 4 that `models.rs` compiles to. The compile row
  compares its result with this file, and the generate rows use this file as
  plain IR that the guest did not compile in the same run.
- `generated-lib.rs`: the crate that this IR generates. The frontend's source
  subset has no module declarations, so it cannot compile this crate back, and
  the generate rows compare their result with this file instead.
