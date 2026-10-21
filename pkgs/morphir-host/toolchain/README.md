# Acquired MoonBit tooling

The MoonBit `finos/morphir-host/toolchain` package provides an injectable `Host`
and a versioned `Provider` request boundary. It validates the selected compiler,
compiles and runs a smoke program against its core, captures diagnostics and
enforces process timeouts. Host effects are explicit callbacks, independent of
the engine and its workspace discovery.

The outer Morphir `Host` accepts an optional `toolchain` provider. Pipeline hosts
can invoke `toolchain_request` through it, with host events and cancellation checks.
Embedding applications own provider lifecycle and disposal.

The process provider supports native macOS/Linux, Node and the Node WASM-GC
runner. Native Windows and plain WASI Preview 1 lack this package's process adapter;
they report that capability explicitly. Node hosts can use existing Windows
toolchains. Embedding is available through the adjacent JS package and custom hosts.

Selection order: `--home`, `MORPHIR_MOON_HOME`, the managed pinned installation,
`MOON_HOME`, then installations found on `PATH`. Explicit invalid installations
fail without silently choosing a different one. Managed roots use
`MORPHIR_HOME/toolchains`, falling back to the user's `.morphir/toolchains`.

Setup downloads official macOS arm64 or Linux x64 tools and matching core for
`0.10.16+b1a0e846e`. Both archives have pinned SHA-256 values in `release.mbt`.
Installation requires consent, uses an exclusive lock, bundles core in staging,
validates it, then publishes by rename. Failed operations remove their own staging
data. Existing directories are validated and reused; they are never overwritten.
The host needs `curl`, `tar`, `chmod`, `ln` and a SHA-256 utility for acquisition.
Official binary URLs have upstream retention limits; an expired pin requires a
reviewed pin update. Installed toolchains continue to work offline.

`MOON_HOME` and the tool directory on `PATH` are set only in child processes.
No shell profile or caller environment is changed. Process arguments are passed
as arrays; JSON output includes the child exit code, stdout and stderr. Cancellation
is checked before and after effects; process timeouts bound individual effects.

This implementation belongs to `finos/morphir-moonbit`. Its completion does not
complete installation or extension integration in the Rust CLI in `finos/morphir`.
