# Gleam extension packaging

The Morphir CLI builds the Rust `morphir-gleam-binding` crate into the executable and registers it as a native built-in extension. A normal CLI build does not compile, copy, embed, or search for `gleam.wasm`.

## Built-in execution

The built-in exposes both Gleam frontend and backend capabilities. CLI compile and generate commands select its typed Rust traits by default. The same extension instance also exposes native MEP execution for parity and conformance tests.

Because the CLI links the built-in, there is no runtime path convention for it. In particular, these locations have no special meaning:

- `extensions/gleam.wasm` beside the executable
- `resources/extensions/gleam.wasm` beside the executable
- an embedded `gleam.wasm` resource

## Portable WebAssembly distribution

A WebAssembly build of the Gleam extension can still be published as an installable alternative. This is useful for portable deployment and for checking native behavior against the protocol boundary. It is not the built-in acquisition mechanism.

Package the module as an extension release with `wasm` runtime metadata, frontend and backend capability metadata, supported MEP and Morphir IR versions, and its SHA-256 digest. Publish the release and artifact through a configured extension repository. Users then install it through the verified flow:

```console
morphir extension repository add --directory <REPOSITORY-DIRECTORY> <REPOSITORY>
morphir extension repository verify <REPOSITORY>
morphir extension install --repository <REPOSITORY> morphir-gleam-binding
```

Installation resolves an exact release, verifies its metadata and artifact digest, and records matching lock and catalog state. At invocation time, an eligible installed Gleam provider takes precedence over the built-in and runs as `WasmMep`. Removing the installed provider restores selection of the native built-in.

Do not copy a raw module beside the CLI binary. The host does not scan adjacent paths, and bypassing the repository and install flow would omit integrity and capability checks.

## Contributor checks

Native and native-MEP parity tests run as part of the CLI test suite. A separately packaged WebAssembly release should also pass the extension SDK's protocol conformance tests and an installed-provider compile and generate test before publication.
