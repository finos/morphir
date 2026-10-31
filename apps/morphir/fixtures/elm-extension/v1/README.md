# Elm extension qualification fixtures

`mise run test:cli-extension-elm` compiles these with the published Elm
extensions.

- `src/Rules.elm`, package `acme/rules`, for the executables of `v0.4.1` and
  elm-classic `v0.5.1`. They do not claim `multiDocument`, so the fixture is one
  document. Its module name has one segment, because these extensions compile
  only module names that the package name does not prefix.
- `package/Acme/Rules/Main.elm`, package `Acme.Rules`, for the `v0.5.0-preview.2`
  WASM module. That extension requires each module name to start with the
  package name and to have one more segment, and the file path to match it.

Both hold the same two functions.
