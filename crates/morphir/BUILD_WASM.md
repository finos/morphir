# WASM Build Integration

This document describes how to build and bundle the Gleam binding WASM extension.

## Building the Gleam Binding WASM

The Gleam binding (`morphir-gleam-binding`) is configured as a `cdylib` crate that can be compiled to WASM.

### Prerequisites

- Rust toolchain with `wasm32-unknown-unknown` target
- `wasm-pack` (optional, for optimized builds)

### Build Steps

1. **Install WASM target** (if not already installed):
   ```bash
   rustup target add wasm32-unknown-unknown
   ```

2. **Build the Gleam binding as WASM**:
   ```bash
   cd crates/morphir-gleam-binding
   cargo build --target wasm32-unknown-unknown --release
   ```

3. **Copy WASM file to CLI resources**:
   ```bash
   mkdir -p crates/morphir/resources/extensions
   cp target/wasm32-unknown-unknown/release/morphir_gleam_binding.wasm \
      crates/morphir/resources/extensions/gleam.wasm
   ```

### Build Script Integration

The `build.rs` script in `crates/morphir/` can be extended to:
- Automatically build the Gleam binding WASM during CLI build
- Copy the WASM file to a resources directory
- Embed the WASM file in the binary (using `include_bytes!`)

### Current Status

Currently, the WASM file must be built manually and placed in the expected location.
The extension discovery logic in `morphir-design` will look for:
- `extensions/gleam.wasm` (relative to binary)
- `resources/extensions/gleam.wasm` (relative to binary)
- Bundled resources (when build script is updated)

### Future Improvements

- Automate WASM build in CI/CD
- Embed WASM in binary for single-file distribution
- Support multiple extension WASM files
- Version management for bundled extensions
