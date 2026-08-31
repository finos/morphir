# OpenAPI and JSON Schema backend — Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the generation protocol carry the selected target, extract shared IR normalization into its own crate, and ship a `morphir-openapi` extension whose `json-schema` target generates JSON Schema 2020-12 end to end through the CLI.

**Architecture:** The Morphir Extension Protocol request gains a required `target` field so one extension can serve several targets. Avro's `normalize` and `model` modules move into a new `morphir-projection` crate. A new `morphir-openapi-extension` crate normalizes IR, projects it into a dialect-neutral schema model, and renders JSON Schema 2020-12. The OpenAPI target and the release land in the follow-up plan.

**Tech Stack:** Rust (workspace edition), `serde`/`serde_json`, `thiserror`, `pretty_assertions`, `jsonschema` (dev-dependency validator), `wasm32-unknown-unknown` guest builds, Cargo workspaces across two repositories linked by a git submodule.

**Spec:** `docs/superpowers/specs/2026-08-31-openapi-json-schema-backend-design.md`

## Global Constraints

- Two repositories. `MORPHIR` = `/Users/damian/.t3/worktrees/morphir/t3code-ccf19da9` (this repo, the umbrella). `RUST` = `$MORPHIR/ecosystem/morphir-rust` (a git submodule, its own git repository). Commits in `RUST` are made inside that directory and are separate from umbrella commits.
- MEP stays at `0.1`. `MEP_VERSION` in `$RUST/crates/morphir-extension-sdk/src/protocol.rs:11` is not changed.
- `GenerateRequest.target` is a required `String`. No `Option`, no `#[serde(default)]`.
- Extension ID: `morphir-openapi`. Crate: `morphir-openapi-extension`. Version `0.1.0`.
- Advertised targets, in this exact order: `["openapi", "json-schema"]`. Advertised IR versions: `["3", "4"]`.
- JSON Schema dialect: `https://json-schema.org/draft/2020-12/schema`.
- Diagnostic codes: `JSC001` and onward for the `json-schema` target, `OAS001` and onward for `openapi`.
- Option names use `snake_case`. Option precedence: backend defaults, then the `morphir.toml` table, then CLI `--option` values in command-line order, last value wins.
- Every generated artifact's content ends with exactly one `\n`.
- No AI attribution in commit messages. No `Co-Authored-By: Claude`, no "Generated with Claude Code". This repository uses EasyCLA and such a line blocks merges.
- Commit message style is Conventional Commits, matching both repositories' history (`feat(cli):`, `fix(hooks):`, `docs(design):`).

---

### Task 1: Add the required `target` field to the protocol

**Files:**
- Modify: `$RUST/crates/morphir-extension-sdk/src/types.rs:318-324`
- Test: `$RUST/crates/morphir-extension-sdk/src/types.rs` (inline `#[cfg(test)]` module at the end of the file)

**Interfaces:**
- Consumes: nothing.
- Produces: `pub struct GenerateRequest { pub ir: serde_json::Value, pub target: String, pub options: HashMap<String, serde_json::Value> }`. Every later task and both repositories construct this struct.

- [ ] **Step 1: Write the failing tests**

Append to `$RUST/crates/morphir-extension-sdk/src/types.rs`:

```rust
#[cfg(test)]
mod generate_request_tests {
    use super::*;

    #[test]
    fn decodes_a_request_that_states_its_target() {
        let request: GenerateRequest = serde_json::from_value(serde_json::json!({
            "ir": {"formatVersion": 4},
            "target": "json-schema",
            "options": {"unsupported": "warn-and-skip"}
        }))
        .expect("a request stating its target decodes");

        assert_eq!(request.target, "json-schema");
        assert_eq!(request.ir["formatVersion"], 4);
        assert_eq!(
            request.options.get("unsupported"),
            Some(&serde_json::json!("warn-and-skip"))
        );
    }

    #[test]
    fn rejects_a_request_with_no_target() {
        let error = serde_json::from_value::<GenerateRequest>(serde_json::json!({
            "ir": {"formatVersion": 4},
            "options": {}
        }))
        .expect_err("the host always states the selected target");

        assert!(error.to_string().contains("target"), "{error}");
    }

    #[test]
    fn defaults_options_to_an_empty_map() {
        let request: GenerateRequest = serde_json::from_value(serde_json::json!({
            "ir": {},
            "target": "openapi"
        }))
        .expect("options remain optional");

        assert!(request.options.is_empty());
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd $RUST && cargo test -p morphir-extension-sdk generate_request_tests`
Expected: FAIL. `decodes_a_request_that_states_its_target` fails to compile or panics because `GenerateRequest` has no `target` field.

- [ ] **Step 3: Add the field**

In `$RUST/crates/morphir-extension-sdk/src/types.rs`, replace the `GenerateRequest` definition:

```rust
/// Request to generate code
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GenerateRequest {
    /// Input IR (JSON)
    pub ir: serde_json::Value,
    /// Target selected by the host for this generation call.
    ///
    /// The host states the exact target ID it negotiated during provider
    /// selection. A backend that advertises more than one target dispatches on
    /// this value and never guesses a default.
    pub target: String,
    /// Generation options
    #[serde(default)]
    pub options: HashMap<String, serde_json::Value>,
}
```

If the struct derives `Default`, remove that derive — a default empty target would defeat the point of the field. Check the current derive list before editing and keep every other derive as it is.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd $RUST && cargo test -p morphir-extension-sdk generate_request_tests`
Expected: PASS, 3 tests.

- [ ] **Step 5: Find every construction site that now fails to compile**

Run: `cd $RUST && cargo check --workspace --all-targets 2>&1 | grep -E "^error" -A 5 | head -60`
Expected: errors listing each `GenerateRequest { ... }` literal and each `GenerateRequest::default()` call. Record the file list; Task 2 fixes them.

- [ ] **Step 6: Commit**

```bash
cd $RUST
git add crates/morphir-extension-sdk/src/types.rs
git commit -m "feat(sdk): state the selected target in the generation request"
```

---

### Task 2: Update the Avro extension and every other SDK consumer

**Files:**
- Modify: `$RUST/crates/morphir-avro-extension/tests/guest.rs:19-22`
- Modify: every other file the Task 1 Step 5 check reported, typically under `$RUST/crates/morphir-avro-extension/tests/`, `$RUST/crates/morphir-ext-example/`, and `$RUST/crates/morphir-daemon/`
- Test: `$RUST/crates/morphir-avro-extension/tests/guest.rs`

**Interfaces:**
- Consumes: `GenerateRequest { ir, target, options }` from Task 1.
- Produces: a workspace that compiles with the new struct, and the rule that a single-target backend ignores `target`.

- [ ] **Step 1: Write the failing test**

Append to `$RUST/crates/morphir-avro-extension/tests/guest.rs`:

```rust
#[test]
fn a_single_target_backend_ignores_the_requested_target() {
    let ir = mothers::classic::customer_library();

    let stated = AvroExtension
        .generate(GenerateRequest {
            ir: ir.clone(),
            target: "avro".into(),
            options: options([]),
        })
        .expect("generation succeeds");
    let unexpected = AvroExtension
        .generate(GenerateRequest {
            ir,
            target: "not-a-target".into(),
            options: options([]),
        })
        .expect("generation succeeds");

    assert!(stated.success);
    assert_eq!(stated.artifacts, unexpected.artifacts);
}
```

If `mothers::classic::customer_library()` is not the exact mother name in this crate, run `grep -rn "pub fn" $RUST/crates/morphir-avro-extension/tests/support/mothers/classic.rs` and use the mother that returns a v3 customer library IR value.

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd $RUST && cargo test -p morphir-avro-extension --test guest`
Expected: FAIL to compile. `GenerateRequest` literals in this file are missing the `target` field.

- [ ] **Step 3: Fix every construction site**

In `$RUST/crates/morphir-avro-extension/tests/guest.rs`, change the shared helper:

```rust
fn generate(ir: Value, options: HashMap<String, Value>) -> morphir_extension_sdk::GenerateResult {
    AvroExtension
        .generate(GenerateRequest {
            ir,
            target: "avro".into(),
            options,
        })
        .expect("backend-domain failures should remain successful MEP calls")
}
```

Replace each remaining `GenerateRequest { ir, options }` literal with one that also sets `target`, and each `GenerateRequest::default()` with an explicit literal:

```rust
GenerateRequest {
    ir: serde_json::Value::Null,
    target: "avro".into(),
    options: Default::default(),
}
```

Do not add a `target` field to `AvroOptions` and do not change any Avro projection behavior. The Avro backend reads `request.ir` and `request.options` only.

- [ ] **Step 4: Run the full workspace test suite**

Run: `cd $RUST && cargo test --workspace`
Expected: PASS. Avro golden files are unchanged; if any golden test fails, the fix in Step 3 changed behavior and must be reverted rather than the golden updated.

- [ ] **Step 5: Commit**

```bash
cd $RUST
git add -A
git commit -m "refactor(avro): state the avro target in generation requests"
```

---

### Task 3: Make the host state the target and update the protocol document

**Files:**
- Modify: `$MORPHIR/crates/morphir/src/commands/generate.rs:116-121`
- Modify: `$MORPHIR/crates/morphir/src/commands/generate/provider.rs` (test call sites at lines 663, 712, 741, 772, 792, 820)
- Modify: `$MORPHIR/docs/design/draft/extensions/protocol.md:349-356`
- Modify: `$MORPHIR` submodule pointer for `ecosystem/morphir-rust`
- Test: `$MORPHIR/crates/morphir/src/commands/generate/provider.rs` (inline test module)

**Interfaces:**
- Consumes: `GenerateRequest { ir, target, options }` from Task 1.
- Produces: the host guarantee that `request.target` equals the target ID used for provider selection. Task 6 depends on this guarantee.

- [ ] **Step 1: Write the failing test**

Add to the existing `#[cfg(test)]` module in `$MORPHIR/crates/morphir/src/commands/generate/provider.rs`:

```rust
#[test]
fn the_request_states_the_selected_target() {
    let request = GenerateRequest {
        ir: serde_json::json!({"formatVersion": 4}),
        target: "json-schema".into(),
        options: Default::default(),
    };

    assert_eq!(request.target, "json-schema");
}
```

This compiles only once the file's other `GenerateRequest` literals carry the field, which is the point: it fails until Step 3 finishes.

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd $MORPHIR && cargo test -p morphir provider::`
Expected: FAIL to compile, with errors on `GenerateRequest::default()` and the literal at line 663.

- [ ] **Step 3: Set the target at the one place the request is built**

In `$MORPHIR/crates/morphir/src/commands/generate.rs`, change the request construction:

```rust
    let request = GenerateRequest {
        ir: ir_data,
        target: target_lang.clone(),
        options: serde_json::from_value(backend_options).map_err(|error| CliError::Config {
            error: error.into(),
        })?,
    };
```

`target_lang` is the value already used two lines later in `provider::resolve_provider(&installed, &target_lang, &ir_version)`, so the request states exactly the target used for selection. If `target_lang` is not a `String` at that point, use `target_lang.to_string()`.

Then update each test call site in `provider.rs`. Replace `GenerateRequest::default()` with:

```rust
GenerateRequest {
    ir: serde_json::Value::Null,
    target: "avro".into(),
    options: Default::default(),
}
```

and add `target: "avro".into(),` to the literals at lines 663 and 820.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd $MORPHIR && cargo test -p morphir`
Expected: PASS.

- [ ] **Step 5: Update the protocol document**

In `$MORPHIR/docs/design/draft/extensions/protocol.md`, under "Backend generation", replace the paragraph that currently reads:

> `morphir.backend.generate` accepts one IR distribution and returns artifacts by
> value. Its parameters are exactly `GenerateRequest { ir, options }`. Input
> paths, output paths, target selection, and IR-version detection are host
> concerns. They do not appear in the guest request.

with:

```markdown
`morphir.backend.generate` accepts one IR distribution and returns artifacts by
value. Its parameters are exactly `GenerateRequest { ir, target, options }`.
`target` is required. The host selects the target, and states the selected
target ID in the request so that an extension advertising more than one target
can dispatch on it. Input paths, output paths, and IR-version detection remain
host concerns and do not appear in the guest request.

A backend that advertises one target may ignore `target`. A backend that
advertises several targets must fail with a diagnostic when `target` is not one
of its advertised targets. It must not fall back to a default target.
```

In the same section, add the target to the example request:

```json
{
  "jsonrpc": "2.0",
  "id": "generate-1",
  "method": "morphir.backend.generate",
  "params": {
    "ir": {},
    "target": "avro",
    "options": {}
  }
}
```

- [ ] **Step 6: Verify the documented example matches the code**

Run: `cd $MORPHIR && grep -n '"target"' docs/design/draft/extensions/protocol.md && grep -n "pub target" ecosystem/morphir-rust/crates/morphir-extension-sdk/src/types.rs`
Expected: both greps produce a hit.

- [ ] **Step 7: Commit, including the submodule pointer**

```bash
cd $MORPHIR
git add crates/morphir/src/commands/generate.rs \
        crates/morphir/src/commands/generate/provider.rs \
        docs/design/draft/extensions/protocol.md \
        ecosystem/morphir-rust
git commit -m "feat(cli): state the selected target in backend generation requests"
```

---

### Task 4: Extract normalization into the `morphir-projection` crate

**Files:**
- Create: `$RUST/crates/morphir-projection/Cargo.toml`
- Create: `$RUST/crates/morphir-projection/src/lib.rs`
- Move: `$RUST/crates/morphir-avro-extension/src/model.rs` → `$RUST/crates/morphir-projection/src/model.rs`
- Move: `$RUST/crates/morphir-avro-extension/src/normalize/` → `$RUST/crates/morphir-projection/src/normalize/`
- Move: `$RUST/crates/morphir-avro-extension/tests/normalization.rs` → `$RUST/crates/morphir-projection/tests/normalization.rs`
- Move: `$RUST/crates/morphir-avro-extension/tests/support/mothers/` → `$RUST/crates/morphir-projection/tests/support/mothers/` and re-export for Avro
- Modify: `$RUST/Cargo.toml` (workspace members)
- Modify: `$RUST/crates/morphir-avro-extension/Cargo.toml`
- Modify: `$RUST/crates/morphir-avro-extension/src/lib.rs:1-31`

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces, all re-exported from `morphir_projection`:
  - `pub fn normalize(ir: &serde_json::Value) -> Result<ProjectionPackage, NormalizeError>`
  - `pub enum NormalizeError` with `pub fn code(&self) -> &'static str`
  - `ProjectionPackage`, `ProjectionDependency`, `ProjectionModule`, `TypeDeclaration`, `TypeExpr`, `NamedType`, `Constructor`, `ValueSpecification`, `ValueKind`, `EntryPointKind`, `EntryPointMetadata`, `DistributionKind`, `IncompletenessKind`
  - Test mothers under `morphir_projection::testing::mothers` (feature-gated, see Step 4)

  Tasks 6 through 9 use these names. Field shapes are unchanged from the Avro crate, so read `model.rs` for the exact variants rather than guessing.

- [ ] **Step 1: Capture the behavior baseline before moving anything**

Run: `cd $RUST && cargo test -p morphir-avro-extension 2>&1 | tail -20 && git status --short`
Expected: PASS, and a clean tree. Record the passing test count. This same count must hold at Step 6, and no golden file may change.

- [ ] **Step 2: Create the crate**

Create `$RUST/crates/morphir-projection/Cargo.toml`:

```toml
[package]
name = "morphir-projection"
version = "0.1.0"
edition.workspace = true
rust-version.workspace = true
authors.workspace = true
license.workspace = true
repository.workspace = true
description = "Shared Morphir IR normalization for backend extensions"

[features]
testing = []

[dependencies]
morphir-core = { path = "../morphir-core" }
serde = { version = "1.0", features = ["derive"] }
serde_json = "1.0"
thiserror = { workspace = true }

[dev-dependencies]
pretty_assertions = "1.4"
```

Add `"crates/morphir-projection"` to the `members` list in `$RUST/Cargo.toml`, keeping the list sorted the way it already is.

Create `$RUST/crates/morphir-projection/src/lib.rs`:

```rust
//! Shared normalization from Morphir IR into a body-free projection model.
//!
//! Backend extensions decode IR v3 or v4 with [`normalize()`] and then project
//! the resulting [`ProjectionPackage`] into their own target model. The model
//! keeps public declarations, documentation, source FQNames, dependencies, and
//! v4 entry-point metadata, and drops every value body.

mod model;
mod normalize;

pub use model::{
    Constructor, DistributionKind, EntryPointKind, EntryPointMetadata, IncompletenessKind,
    NamedType, ProjectionDependency, ProjectionModule, ProjectionPackage, TypeDeclaration,
    TypeExpr, ValueKind, ValueSpecification,
};
pub use normalize::{NormalizeError, normalize};

#[cfg(any(test, feature = "testing"))]
pub mod testing;
```

- [ ] **Step 3: Move the modules with git so history follows**

```bash
cd $RUST
git mv crates/morphir-avro-extension/src/model.rs crates/morphir-projection/src/model.rs
git mv crates/morphir-avro-extension/src/normalize crates/morphir-projection/src/normalize
git mv crates/morphir-avro-extension/tests/normalization.rs crates/morphir-projection/tests/normalization.rs
```

In the moved files, change every `crate::` path that pointed at Avro-only items. `normalize/` referenced `crate::model::...`, which still resolves. If a moved file references `crate::AvroDiagnostic` or any other Avro type, that reference is a sign the module was not purely normalization — stop and report it rather than copying Avro types into the new crate.

- [ ] **Step 4: Share the IR mothers**

```bash
cd $RUST
git mv crates/morphir-avro-extension/tests/support/mothers crates/morphir-projection/src/testing
```

Create `$RUST/crates/morphir-projection/src/testing/mod.rs` if the moved `mod.rs` does not already declare the submodules, exposing the same public functions the Avro tests used:

```rust
//! Shared Morphir IR fixtures for backend extension tests.
//!
//! Enabled by the `testing` feature so that extension crates can build IR
//! fixtures without duplicating them.

pub mod classic;
pub mod v4;
```

In `$RUST/crates/morphir-avro-extension/tests/support/mod.rs`, replace the removed module with a re-export:

```rust
#![allow(dead_code)]

pub use morphir_projection::testing as mothers;

pub mod projection;
```

Add the dev-dependency in `$RUST/crates/morphir-avro-extension/Cargo.toml`:

```toml
morphir-projection = { path = "../morphir-projection", features = ["testing"] }
```

- [ ] **Step 5: Point the Avro crate at the new crate**

Add to `[dependencies]` in `$RUST/crates/morphir-avro-extension/Cargo.toml`:

```toml
morphir-projection = { path = "../morphir-projection" }
```

In `$RUST/crates/morphir-avro-extension/src/lib.rs`, delete the `mod model;` and `mod normalize;` declarations and replace the two `pub use` blocks that exported them with a re-export from the new crate:

```rust
pub use morphir_projection::{
    Constructor, DistributionKind, EntryPointKind, EntryPointMetadata, IncompletenessKind,
    NamedType, NormalizeError, ProjectionDependency, ProjectionModule, ProjectionPackage,
    TypeDeclaration, TypeExpr, ValueKind, ValueSpecification, normalize,
};
```

Then fix the resulting compile errors inside `src/avro/` and `src/render/` by changing `crate::model::X` to `morphir_projection::X`. Run `cd $RUST && cargo check -p morphir-avro-extension 2>&1 | grep "^error" | head -30` and work through the list.

- [ ] **Step 6: Prove the extraction changed no behavior**

Run: `cd $RUST && cargo test -p morphir-avro-extension -p morphir-projection`
Expected: PASS with the same Avro test count recorded in Step 1.

Run: `cd $RUST && git status --short crates/morphir-avro-extension/tests/golden`
Expected: no modified golden files. Only renames from Step 3 and Step 4 may appear anywhere in `git status`. A modified `.avsc`, `.avpr`, or `.avdl` file means behavior changed and must be fixed rather than accepted.

- [ ] **Step 7: Commit**

```bash
cd $RUST
git add -A
git commit -m "refactor(projection): extract shared IR normalization into morphir-projection"
```

---

### Task 5: Create the extension crate with two advertised targets

**Files:**
- Create: `$RUST/crates/morphir-openapi-extension/Cargo.toml`
- Create: `$RUST/crates/morphir-openapi-extension/src/lib.rs`
- Create: `$RUST/crates/morphir-openapi-extension/src/diagnostic.rs`
- Create: `$RUST/crates/morphir-openapi-extension/tests/guest.rs`
- Modify: `$RUST/Cargo.toml` (workspace members)

**Interfaces:**
- Consumes: `GenerateRequest { ir, target, options }` (Task 1); `morphir_projection::normalize` (Task 4).
- Produces:
  - `pub struct OpenApiExtension;`
  - `pub enum Target { OpenApi, JsonSchema }` with `pub fn parse(target: &str) -> Option<Target>` and `pub fn id(self) -> &'static str`
  - `pub struct SchemaDiagnostic` with `pub fn code(&self) -> &'static str`, `pub fn message(&self) -> &str`, `pub fn source(&self) -> Option<&str>`, `pub fn into_diagnostic(self, severity: DiagnosticSeverity) -> Diagnostic`, and constructors `SchemaDiagnostic::unknown_target(target: &str)`, `SchemaDiagnostic::invalid_option(message: impl Into<String>)`, `SchemaDiagnostic::unsupported_form(source_name: &str, message: impl Into<String>)`, `SchemaDiagnostic::name_collision(source_name: &str, message: impl Into<String>)`
  - `pub fn generate_request(request: GenerateRequest) -> Result<GenerateResult, SchemaGenerationError>`

- [ ] **Step 1: Write the failing tests**

Create `$RUST/crates/morphir-openapi-extension/tests/guest.rs`:

```rust
use std::collections::HashMap;

use morphir_extension_sdk::{
    Backend, DiagnosticSeverity, Extension, ExtensionType, GenerateRequest,
};
use morphir_openapi_extension::OpenApiExtension;
use serde_json::{Value, json};

fn generate(target: &str, ir: Value, options: HashMap<String, Value>) -> morphir_extension_sdk::GenerateResult {
    OpenApiExtension
        .generate(GenerateRequest {
            ir,
            target: target.into(),
            options,
        })
        .expect("backend-domain failures remain successful MEP calls")
}

#[test]
fn advertises_both_targets_and_both_ir_versions() {
    let info = OpenApiExtension::info();
    assert_eq!(info.id, "morphir-openapi");
    assert_eq!(info.name, "Morphir OpenAPI");
    assert_eq!(info.version, env!("CARGO_PKG_VERSION"));
    assert_eq!(info.types, [ExtensionType::Backend]);
    assert_eq!(info.license.as_deref(), Some("Apache-2.0"));

    let backend = OpenApiExtension::capabilities()
        .backend
        .expect("the extension advertises a backend capability");
    assert_eq!(backend.targets, ["openapi", "json-schema"]);
    assert_eq!(backend.ir_versions, ["3", "4"]);
    assert!(backend.generate);
}

#[test]
fn rejects_a_target_it_does_not_advertise() {
    let result = generate("avro", json!({"formatVersion": 4}), HashMap::new());

    assert!(!result.success);
    assert!(result.artifacts.is_empty());
    let diagnostic = result
        .diagnostics
        .first()
        .expect("an unadvertised target reports a diagnostic");
    assert_eq!(diagnostic.severity, DiagnosticSeverity::Error);
    assert_eq!(diagnostic.code.as_deref(), Some("JSC001"));
    assert!(diagnostic.message.contains("avro"), "{}", diagnostic.message);
}

#[test]
fn reports_an_ir_error_rather_than_panicking() {
    let result = generate("json-schema", json!({}), HashMap::new());

    assert!(!result.success);
    assert!(result.artifacts.is_empty());
    assert!(!result.diagnostics.is_empty());
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd $RUST && cargo test -p morphir-openapi-extension --test guest`
Expected: FAIL. The package does not exist yet.

- [ ] **Step 3: Create the crate manifest**

Create `$RUST/crates/morphir-openapi-extension/Cargo.toml`:

```toml
[package]
name = "morphir-openapi-extension"
version = "0.1.0"
edition.workspace = true
rust-version.workspace = true
authors.workspace = true
license.workspace = true
repository.workspace = true
description = "OpenAPI and JSON Schema backend extension for Morphir"

[lib]
crate-type = ["rlib", "cdylib"]

[dependencies]
morphir-core = { path = "../morphir-core" }
morphir-extension-sdk = { path = "../morphir-extension-sdk" }
morphir-projection = { path = "../morphir-projection" }
serde = { version = "1.0", features = ["derive"] }
serde_json = "1.0"
thiserror = { workspace = true }

[dev-dependencies]
morphir-projection = { path = "../morphir-projection", features = ["testing"] }
jsonschema = "0.26"
pretty_assertions = "1.4"
```

Add `"crates/morphir-openapi-extension"` to the workspace `members` list in `$RUST/Cargo.toml`.

- [ ] **Step 4: Write the diagnostics module**

Create `$RUST/crates/morphir-openapi-extension/src/diagnostic.rs`:

```rust
use morphir_extension_sdk::{Diagnostic, DiagnosticSeverity};
use thiserror::Error;

/// A stable diagnostic emitted by the OpenAPI and JSON Schema backend.
#[derive(Debug, Clone, Error, PartialEq, Eq)]
#[error("{message}")]
pub struct SchemaDiagnostic {
    code: &'static str,
    message: String,
    source_name: Option<String>,
}

impl SchemaDiagnostic {
    fn new(code: &'static str, message: impl Into<String>, source_name: Option<String>) -> Self {
        Self {
            code,
            message: message.into(),
            source_name,
        }
    }

    /// The host asked for a target this extension does not advertise.
    pub fn unknown_target(target: &str) -> Self {
        Self::new(
            "JSC001",
            format!(
                "unsupported generation target '{target}'; this extension advertises 'openapi' and 'json-schema'"
            ),
            None,
        )
    }

    /// A backend option was unknown, of the wrong type, or out of range.
    pub fn invalid_option(message: impl Into<String>) -> Self {
        Self::new("JSC002", message, None)
    }

    /// A Morphir form has no safe schema projection.
    pub fn unsupported_form(source_name: &str, message: impl Into<String>) -> Self {
        Self::new("JSC003", message, Some(source_name.to_owned()))
    }

    /// Two projected declarations claimed the same schema name.
    pub fn name_collision(source_name: &str, message: impl Into<String>) -> Self {
        Self::new("JSC004", message, Some(source_name.to_owned()))
    }

    /// Return the stable backend diagnostic code.
    pub fn code(&self) -> &'static str {
        self.code
    }

    /// Return the human-readable diagnostic message.
    pub fn message(&self) -> &str {
        &self.message
    }

    /// Return the canonical Morphir source associated with this diagnostic.
    pub fn source(&self) -> Option<&str> {
        self.source_name.as_deref()
    }

    /// Convert this diagnostic to the extension protocol representation.
    pub fn into_diagnostic(self, severity: DiagnosticSeverity) -> Diagnostic {
        Diagnostic {
            severity,
            code: Some(self.code.into()),
            message: match &self.source_name {
                Some(source) => format!("{}: {}", source, self.message),
                None => self.message.clone(),
            },
            location: None,
            related: Vec::new(),
        }
    }
}

/// An internal failure that must not escape as a protocol error.
#[derive(Debug, Clone, Error, PartialEq, Eq)]
pub enum SchemaGenerationError {
    /// A renderer produced output the backend could not serialize.
    #[error("schema rendering failed: {0}")]
    Rendering(String),
}
```

- [ ] **Step 5: Write the extension entry point**

Create `$RUST/crates/morphir-openapi-extension/src/lib.rs`:

```rust
//! OpenAPI and JSON Schema backend extension for Morphir.
//!
//! The extension advertises two targets. `json-schema` renders JSON Schema
//! 2020-12 documents, and `openapi` renders an OpenAPI document. Both targets
//! share one normalization step and one schema projection, so a type has the
//! same schema in either output.

mod diagnostic;

pub use diagnostic::{SchemaDiagnostic, SchemaGenerationError};

use morphir_extension_sdk::{
    Backend, BackendCapability, DiagnosticSeverity, Extension, ExtensionCapabilities,
    ExtensionError, ExtensionInfo, ExtensionType, GenerateRequest, GenerateResult,
};

/// A generation target advertised by this extension.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Target {
    /// An OpenAPI document.
    OpenApi,
    /// JSON Schema documents.
    JsonSchema,
}

impl Target {
    /// Parse a host-supplied target ID.
    pub fn parse(target: &str) -> Option<Self> {
        match target {
            "openapi" => Some(Self::OpenApi),
            "json-schema" => Some(Self::JsonSchema),
            _ => None,
        }
    }

    /// The stable target ID advertised in the backend capability.
    pub fn id(self) -> &'static str {
        match self {
            Self::OpenApi => "openapi",
            Self::JsonSchema => "json-schema",
        }
    }
}

/// Portable Morphir backend that projects specifications into OpenAPI and JSON Schema.
#[derive(Default)]
pub struct OpenApiExtension;

impl Extension for OpenApiExtension {
    fn info() -> ExtensionInfo {
        ExtensionInfo {
            id: "morphir-openapi".into(),
            name: "Morphir OpenAPI".into(),
            version: env!("CARGO_PKG_VERSION").into(),
            description: Some(
                "Projects Morphir specifications into OpenAPI and JSON Schema".into(),
            ),
            types: vec![ExtensionType::Backend],
            author: Some("FINOS".into()),
            homepage: Some("https://github.com/finos/morphir-rust".into()),
            license: Some("Apache-2.0".into()),
            min_sdk_version: Some("0.2.0".into()),
        }
    }

    fn capabilities() -> ExtensionCapabilities {
        ExtensionCapabilities {
            backend: Some(BackendCapability {
                targets: vec!["openapi".into(), "json-schema".into()],
                ir_versions: vec!["3".into(), "4".into()],
                generate: true,
            }),
            ..ExtensionCapabilities::default()
        }
    }
}

impl Backend for OpenApiExtension {
    fn generate(&self, request: GenerateRequest) -> morphir_extension_sdk::Result<GenerateResult> {
        generate_request(request)
            .map_err(|error| ExtensionError::ExecutionFailed(error.to_string()))
    }

    fn target_languages() -> Vec<String> {
        vec!["openapi".into(), "json-schema".into()]
    }
}

morphir_extension_sdk::export_extension!(OpenApiExtension, backend);

/// Decode one MEP generation request and return backend diagnostics as data.
///
/// Target dispatch runs first: an unadvertised target is a backend-domain
/// failure, not a protocol failure, and never falls back to a default target.
pub fn generate_request(
    request: GenerateRequest,
) -> Result<GenerateResult, SchemaGenerationError> {
    let Some(_target) = Target::parse(&request.target) else {
        return Ok(failed(SchemaDiagnostic::unknown_target(&request.target)));
    };
    let _package = match morphir_projection::normalize(&request.ir) {
        Ok(package) => package,
        Err(error) => {
            return Ok(failed(SchemaDiagnostic::invalid_option(error.to_string())));
        }
    };
    Ok(GenerateResult {
        success: true,
        artifacts: Vec::new(),
        diagnostics: Vec::new(),
    })
}

fn failed(diagnostic: SchemaDiagnostic) -> GenerateResult {
    GenerateResult {
        success: false,
        artifacts: Vec::new(),
        diagnostics: vec![diagnostic.into_diagnostic(DiagnosticSeverity::Error)],
    }
}
```

Check `$RUST/crates/morphir-avro-extension/src/lib.rs` for the exact `export_extension!` invocation and the `min_sdk_version` value currently in use, and match them.

- [ ] **Step 6: Run the tests to verify they pass**

Run: `cd $RUST && cargo test -p morphir-openapi-extension --test guest`
Expected: PASS, 3 tests.

- [ ] **Step 7: Commit**

```bash
cd $RUST
git add -A
git commit -m "feat(openapi): add the extension crate advertising openapi and json-schema"
```

---

### Task 6: Decode `json-schema` options

**Files:**
- Create: `$RUST/crates/morphir-openapi-extension/src/options.rs`
- Modify: `$RUST/crates/morphir-openapi-extension/src/lib.rs`
- Create: `$RUST/crates/morphir-openapi-extension/tests/options.rs`

**Interfaces:**
- Consumes: `SchemaDiagnostic::invalid_option` (Task 5).
- Produces:
  - `pub struct SchemaOptions { pub unsupported: Unsupported }` with `pub fn from_map(options: &HashMap<String, serde_json::Value>) -> Result<Self, SchemaDiagnostic>` and a `Default` whose `unsupported` is `Unsupported::Error`
  - `pub enum Unsupported { Error, WarnAndSkip }`, serde `kebab-case`

  Task 8 reads `options.unsupported`. The follow-up plan adds OpenAPI-only fields to this same struct.

- [ ] **Step 1: Write the failing tests**

Create `$RUST/crates/morphir-openapi-extension/tests/options.rs`:

```rust
use std::collections::HashMap;

use morphir_openapi_extension::{SchemaOptions, Unsupported};
use serde_json::{Value, json};

fn map(entries: impl IntoIterator<Item = (&'static str, Value)>) -> HashMap<String, Value> {
    entries
        .into_iter()
        .map(|(key, value)| (key.to_owned(), value))
        .collect()
}

#[test]
fn defaults_to_strict_unsupported_handling() {
    let options = SchemaOptions::from_map(&HashMap::new()).expect("an empty map decodes");

    assert_eq!(options.unsupported, Unsupported::Error);
    assert_eq!(options, SchemaOptions::default());
}

#[test]
fn decodes_the_documented_enum_spelling() {
    let options = SchemaOptions::from_map(&map([("unsupported", json!("warn-and-skip"))]))
        .expect("the documented spelling decodes");

    assert_eq!(options.unsupported, Unsupported::WarnAndSkip);
}

#[test]
fn rejects_an_unknown_option_key() {
    let error = SchemaOptions::from_map(&map([("representation", json!("idl"))]))
        .expect_err("an unknown key is an invalid option");

    assert_eq!(error.code(), "JSC002");
}

#[test]
fn rejects_a_wrong_json_type() {
    let error = SchemaOptions::from_map(&map([("unsupported", json!(true))]))
        .expect_err("a boolean is not an unsupported policy");

    assert_eq!(error.code(), "JSC002");
}

#[test]
fn rejects_an_invalid_enum_value() {
    let error = SchemaOptions::from_map(&map([("unsupported", json!("ignore"))]))
        .expect_err("only the documented values decode");

    assert_eq!(error.code(), "JSC002");
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd $RUST && cargo test -p morphir-openapi-extension --test options`
Expected: FAIL. `SchemaOptions` is not defined.

- [ ] **Step 3: Write the options module**

Create `$RUST/crates/morphir-openapi-extension/src/options.rs`:

```rust
use std::collections::{BTreeMap, HashMap};

use serde::Deserialize;
use serde_json::Value;

use crate::SchemaDiagnostic;

/// Configuration accepted by the OpenAPI and JSON Schema backend.
#[derive(Debug, Clone, PartialEq, Eq, Deserialize)]
#[serde(default, deny_unknown_fields)]
pub struct SchemaOptions {
    /// Unsupported-form handling policy.
    pub unsupported: Unsupported,
}

impl Default for SchemaOptions {
    fn default() -> Self {
        Self {
            unsupported: Unsupported::Error,
        }
    }
}

impl SchemaOptions {
    /// Decode backend options without coercing the JSON values supplied by the host.
    pub fn from_map(options: &HashMap<String, Value>) -> Result<Self, SchemaDiagnostic> {
        let options = options
            .iter()
            .map(|(key, value)| (key.clone(), value.clone()))
            .collect::<BTreeMap<_, _>>();

        let value = serde_json::to_value(options)
            .map_err(|error| SchemaDiagnostic::invalid_option(error.to_string()))?;
        serde_json::from_value(value)
            .map_err(|error| SchemaDiagnostic::invalid_option(error.to_string()))
    }
}

/// How the backend reacts to a Morphir form it cannot project.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default, Deserialize)]
#[serde(rename_all = "kebab-case")]
pub enum Unsupported {
    /// Fail the whole generation and emit no artifacts.
    #[default]
    Error,
    /// Skip the form, warn at its Morphir FQName, and keep valid artifacts.
    WarnAndSkip,
}
```

In `$RUST/crates/morphir-openapi-extension/src/lib.rs`, add `mod options;` next to `mod diagnostic;` and `pub use options::{SchemaOptions, Unsupported};` next to the diagnostic re-export. In `generate_request`, decode the options before normalizing the IR, so an invalid option has stable precedence over an IR error:

```rust
    let _options = match SchemaOptions::from_map(&request.options) {
        Ok(options) => options,
        Err(diagnostic) => return Ok(failed(diagnostic)),
    };
```

Place that block immediately after the target dispatch and before the `normalize` call.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd $RUST && cargo test -p morphir-openapi-extension`
Expected: PASS, 5 option tests plus the 3 guest tests.

- [ ] **Step 5: Commit**

```bash
cd $RUST
git add -A
git commit -m "feat(openapi): decode backend options with strict unsupported handling"
```

---

### Task 7: Project Morphir types into the dialect-neutral schema model

**Files:**
- Create: `$RUST/crates/morphir-openapi-extension/src/schema/mod.rs`
- Create: `$RUST/crates/morphir-openapi-extension/src/schema/names.rs`
- Create: `$RUST/crates/morphir-openapi-extension/src/schema/types.rs`
- Modify: `$RUST/crates/morphir-openapi-extension/src/lib.rs`
- Create: `$RUST/crates/morphir-openapi-extension/tests/projection.rs`

**Interfaces:**
- Consumes: `morphir_projection::{ProjectionPackage, TypeDeclaration, TypeExpr, NamedType, Constructor}` (Task 4); `SchemaOptions`, `Unsupported` (Task 6); `SchemaDiagnostic` (Task 5).
- Produces:
  - `pub enum Schema { Boolean, Integer { format: Option<&'static str> }, Number { format: Option<&'static str> }, Text { max_length: Option<u32> }, Null, Array { items: Box<Schema>, unique: bool }, Tuple(Vec<Schema>), Map { values: Box<Schema> }, Object { fields: Vec<SchemaField>, required: Vec<String> }, Enumeration(Vec<String>), OneOf { discriminator: String, variants: Vec<SchemaVariant> }, Union(Vec<Schema>), Reference(String) }`
  - `pub struct SchemaField { pub name: String, pub schema: Schema, pub required: bool, pub doc: Option<String> }`
  - `pub struct SchemaVariant { pub name: String, pub schema: Schema, pub source_name: String }`
  - `pub struct NamedSchema { pub name: String, pub source_name: String, pub schema: Schema, pub doc: Option<String> }`
  - `pub struct SchemaProjection { pub roots: Vec<NamedSchema>, pub definitions: BTreeMap<String, NamedSchema>, pub diagnostics: Vec<(SchemaDiagnostic, bool)> }` where the `bool` is `true` when the diagnostic is a warning
  - `pub fn project(package: &ProjectionPackage, options: &SchemaOptions) -> Result<SchemaProjection, SchemaDiagnostic>`
  - `pub fn schema_name(source_name: &str) -> String` in `names.rs`

  Task 8 renders `SchemaProjection`. The follow-up plan's OpenAPI renderer consumes the same struct.

- [ ] **Step 1: Write the failing tests**

Create `$RUST/crates/morphir-openapi-extension/tests/projection.rs`:

```rust
use morphir_openapi_extension::{Schema, SchemaOptions, Unsupported, project};
use morphir_projection::{normalize, testing::mothers};

fn projection(ir: serde_json::Value) -> morphir_openapi_extension::SchemaProjection {
    let package = normalize(&ir).expect("the fixture normalizes");
    project(&package, &SchemaOptions::default()).expect("the fixture projects")
}

fn root<'a>(
    projection: &'a morphir_openapi_extension::SchemaProjection,
    source_name: &str,
) -> &'a Schema {
    &projection
        .roots
        .iter()
        .find(|root| root.source_name == source_name)
        .unwrap_or_else(|| panic!("no root for {source_name}"))
        .schema
}

#[test]
fn projects_a_record_alias_as_an_object_with_required_fields() {
    let projection = projection(mothers::classic::customer_library());

    let Schema::Object { fields, required } = root(&projection, "acme/customer:customer#customer")
    else {
        panic!("a record alias projects as an object");
    };
    assert!(fields.iter().any(|field| field.name == "customerId"));
    assert!(required.contains(&"customerId".to_owned()));
}

#[test]
fn projects_maybe_as_a_union_with_null() {
    let projection = projection(mothers::classic::customer_library());

    let optional = projection
        .definitions
        .values()
        .flat_map(|named| match &named.schema {
            Schema::Object { fields, .. } => fields.clone(),
            _ => Vec::new(),
        })
        .find(|field| matches!(field.schema, Schema::Union(_)))
        .expect("the fixture has an optional field");

    let Schema::Union(members) = optional.schema else {
        unreachable!("filtered above");
    };
    assert!(members.iter().any(|member| matches!(member, Schema::Null)));
}

#[test]
fn projects_a_nullary_custom_type_as_an_enumeration() {
    let projection = projection(mothers::classic::customer_library());

    let enumeration = projection
        .definitions
        .values()
        .find(|named| matches!(named.schema, Schema::Enumeration(_)))
        .expect("the fixture has a nullary custom type");

    let Schema::Enumeration(values) = &enumeration.schema else {
        unreachable!("filtered above");
    };
    assert!(!values.is_empty());
    assert_eq!(values.clone(), {
        let mut sorted = values.clone();
        sorted.sort();
        sorted
    });
}

#[test]
fn a_name_collision_is_an_error_rather_than_a_rename() {
    let package = normalize(&mothers::classic::colliding_names_library())
        .expect("the fixture normalizes");

    let error =
        project(&package, &SchemaOptions::default()).expect_err("a collision fails projection");

    assert_eq!(error.code(), "JSC004");
}

#[test]
fn strict_mode_fails_on_a_function_used_as_data() {
    let package =
        normalize(&mothers::classic::function_field_library()).expect("the fixture normalizes");

    let error =
        project(&package, &SchemaOptions::default()).expect_err("a function field has no schema");

    assert_eq!(error.code(), "JSC003");
}

#[test]
fn warn_and_skip_omits_the_form_and_keeps_the_rest() {
    let package =
        normalize(&mothers::classic::function_field_library()).expect("the fixture normalizes");
    let options = SchemaOptions {
        unsupported: Unsupported::WarnAndSkip,
    };

    let projection = project(&package, &options).expect("skipping keeps projection successful");

    assert!(projection.diagnostics.iter().any(|(diagnostic, warning)| {
        *warning && diagnostic.code() == "JSC003"
    }));
    assert!(!projection.roots.is_empty());
}
```

If `colliding_names_library` and `function_field_library` do not exist in the shared mothers, add them there in this task. Run `grep -rn "pub fn" $RUST/crates/morphir-projection/src/testing/classic.rs` first; the Avro crate has edge-case fixtures under names such as `edge_*`, and reusing an existing fixture is better than adding one.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd $RUST && cargo test -p morphir-openapi-extension --test projection`
Expected: FAIL. `project`, `Schema`, and `SchemaProjection` are not defined.

- [ ] **Step 3: Write the schema model and the name mapping**

Create `$RUST/crates/morphir-openapi-extension/src/schema/names.rs`:

```rust
/// Map a canonical Morphir FQName to a stable schema name.
///
/// `acme/customer:customer#customer-id` becomes `CustomerId`. The mapping is a
/// pure function of the FQName, so it does not depend on traversal order.
pub fn schema_name(source_name: &str) -> String {
    let local = source_name.rsplit('#').next().unwrap_or(source_name);
    upper_camel_case(local)
}

/// Map a canonical Morphir name to a field or property name.
pub fn field_name(name: &str) -> String {
    lower_camel_case(name)
}

fn upper_camel_case(value: &str) -> String {
    value
        .split(['-', '_', ' '])
        .filter(|segment| !segment.is_empty())
        .map(capitalize)
        .collect()
}

fn lower_camel_case(value: &str) -> String {
    let mut segments = value
        .split(['-', '_', ' '])
        .filter(|segment| !segment.is_empty());
    let first = segments.next().unwrap_or_default().to_lowercase();
    std::iter::once(first)
        .chain(segments.map(capitalize))
        .collect()
}

fn capitalize(segment: &str) -> String {
    let mut characters = segment.chars();
    match characters.next() {
        Some(first) => first.to_uppercase().chain(characters).collect(),
        None => String::new(),
    }
}
```

Create `$RUST/crates/morphir-openapi-extension/src/schema/mod.rs` holding `Schema`, `SchemaField`, `SchemaVariant`, `NamedSchema`, and `SchemaProjection` exactly as listed in this task's **Interfaces** block, each with a doc comment, and `pub fn project`. `project` walks every public module of the package, projects each `TypeDeclaration` through `types::project_declaration`, registers the result in `definitions` keyed by `schema_name(source_name)`, and returns `SchemaDiagnostic::name_collision` when a key is already present with a different `source_name`. Public root types become `roots` in declaration order.

Create `$RUST/crates/morphir-openapi-extension/src/schema/types.rs` holding `project_declaration` and `project_type`, mapping `TypeExpr` per the constraint table:

| Morphir form | `Schema` value |
|---|---|
| `Bool` | `Schema::Boolean` |
| `Int` | `Schema::Integer { format: Some("int64") }` |
| `Float` | `Schema::Number { format: Some("double") }` |
| `String` | `Schema::Text { max_length: None }` |
| `Char` | `Schema::Text { max_length: Some(1) }` |
| `Unit` / `TypeExpr::Unit` | `Schema::Null` |
| `Maybe a` | `Schema::Union(vec![project(a), Schema::Null])` |
| `List a` | `Schema::Array { items, unique: false }` |
| `Set a` | `Schema::Array { items, unique: true }` |
| `Dict String a` | `Schema::Map { values }` |
| `TypeExpr::Tuple` | `Schema::Tuple` |
| `TypeExpr::Record` | `Schema::Object` |
| Nullary `TypeDeclaration::Custom` | `Schema::Enumeration` with constructor names sorted |
| `TypeDeclaration::Custom` with payloads | `Schema::OneOf { discriminator: "kind".into(), variants }` |
| `TypeExpr::Reference` to a declared type | `Schema::Reference(schema_name(source_name))` |
| `TypeExpr::Function`, `TypeExpr::ExtensibleRecord`, `TypeDeclaration::Opaque`, `TypeDeclaration::Incomplete`, unbound `TypeExpr::Variable`, `Dict` with a non-`String` key | `SchemaDiagnostic::unsupported_form` |

Under `Unsupported::WarnAndSkip`, an unsupported form is pushed onto `diagnostics` as `(diagnostic, true)` and its declaration is omitted, rather than returned as `Err`.

Add `mod schema;` to `$RUST/crates/morphir-openapi-extension/src/lib.rs` and re-export `NamedSchema`, `Schema`, `SchemaField`, `SchemaProjection`, `SchemaVariant`, and `project`.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd $RUST && cargo test -p morphir-openapi-extension --test projection`
Expected: PASS, 6 tests.

- [ ] **Step 5: Check the projection is deterministic**

Run: `cd $RUST && cargo test -p morphir-openapi-extension --test projection -- --test-threads=1 && cargo test -p morphir-openapi-extension --test projection`
Expected: PASS both times with identical output. `definitions` is a `BTreeMap`, so ordering does not depend on traversal.

- [ ] **Step 6: Commit**

```bash
cd $RUST
git add -A
git commit -m "feat(openapi): project Morphir declarations into a dialect-neutral schema model"
```

---

### Task 8: Render JSON Schema 2020-12 documents

**Files:**
- Create: `$RUST/crates/morphir-openapi-extension/src/render/mod.rs`
- Create: `$RUST/crates/morphir-openapi-extension/src/render/json_schema.rs`
- Modify: `$RUST/crates/morphir-openapi-extension/src/lib.rs`
- Create: `$RUST/crates/morphir-openapi-extension/tests/golden.rs`
- Create: `$RUST/crates/morphir-openapi-extension/tests/golden/` (reviewed `.schema.json` files)

**Interfaces:**
- Consumes: `SchemaProjection`, `Schema` (Task 7); `SchemaOptions` (Task 6).
- Produces:
  - `pub fn render_json_schema(projection: &SchemaProjection) -> Vec<morphir_extension_sdk::Artifact>`
  - Artifact path shape: `<module-path-joined-by-dot>.<SchemaName>.schema.json`, all lowercase for the module segments, for example `customer.Customer.schema.json`
  - `generate_request` now returns real artifacts for `Target::JsonSchema`

- [ ] **Step 1: Write the failing tests**

Create `$RUST/crates/morphir-openapi-extension/tests/golden.rs`:

```rust
use std::collections::HashMap;
use std::path::PathBuf;

use morphir_extension_sdk::{Backend, GenerateRequest};
use morphir_openapi_extension::OpenApiExtension;
use morphir_projection::testing::mothers;
use pretty_assertions::assert_eq;
use serde_json::Value;

fn golden(name: &str, actual: &str) -> String {
    let path = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("tests/golden")
        .join(name);
    if std::env::var_os("UPDATE_GOLDEN").is_some() {
        std::fs::write(&path, actual).expect("golden file is writable");
    }
    std::fs::read_to_string(&path).unwrap_or_else(|_| panic!("missing golden file {name}"))
}

fn generate(ir: Value) -> morphir_extension_sdk::GenerateResult {
    OpenApiExtension
        .generate(GenerateRequest {
            ir,
            target: "json-schema".into(),
            options: HashMap::new(),
        })
        .expect("generation is a successful MEP call")
}

#[test]
fn renders_one_document_per_public_root_type() {
    let result = generate(mothers::classic::customer_library());

    assert!(result.success, "{:?}", result.diagnostics);
    assert!(!result.artifacts.is_empty());
    for artifact in &result.artifacts {
        assert!(artifact.path.ends_with(".schema.json"), "{}", artifact.path);
        assert!(!artifact.binary);
        assert!(artifact.content.ends_with('\n'));
        assert!(!artifact.content.ends_with("\n\n"));
    }
}

#[test]
fn matches_the_reviewed_golden_documents() {
    let result = generate(mothers::classic::customer_library());

    let artifact = result
        .artifacts
        .iter()
        .find(|artifact| artifact.path == "customer.Customer.schema.json")
        .expect("the customer root is generated");

    assert_eq!(artifact.content, golden("customer.Customer.schema.json", &artifact.content));
}

#[test]
fn every_document_is_a_valid_2020_12_schema() {
    let result = generate(mothers::classic::customer_library());

    for artifact in &result.artifacts {
        let document: Value = serde_json::from_str(&artifact.content)
            .unwrap_or_else(|error| panic!("{}: {error}", artifact.path));
        assert_eq!(
            document["$schema"],
            "https://json-schema.org/draft/2020-12/schema"
        );
        jsonschema::validator_for(&document)
            .unwrap_or_else(|error| panic!("{} is not a valid schema: {error}", artifact.path));
    }
}

#[test]
fn local_references_resolve_inside_the_document() {
    let result = generate(mothers::classic::customer_library());

    for artifact in &result.artifacts {
        let document: Value = serde_json::from_str(&artifact.content).expect("valid JSON");
        let definitions = document
            .get("$defs")
            .and_then(Value::as_object)
            .cloned()
            .unwrap_or_default();
        for reference in references(&document) {
            let name = reference
                .strip_prefix("#/$defs/")
                .unwrap_or_else(|| panic!("{}: non-local reference {reference}", artifact.path));
            assert!(
                definitions.contains_key(name),
                "{}: dangling reference {reference}",
                artifact.path
            );
        }
    }
}

fn references(value: &Value) -> Vec<String> {
    match value {
        Value::Object(members) => members
            .iter()
            .flat_map(|(key, member)| {
                if key == "$ref" {
                    member.as_str().map(str::to_owned).into_iter().collect()
                } else {
                    references(member)
                }
            })
            .collect(),
        Value::Array(members) => members.iter().flat_map(references).collect(),
        _ => Vec::new(),
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd $RUST && cargo test -p morphir-openapi-extension --test golden`
Expected: FAIL. `renders_one_document_per_public_root_type` fails because `generate_request` still returns no artifacts.

- [ ] **Step 3: Write the renderer**

Create `$RUST/crates/morphir-openapi-extension/src/render/json_schema.rs` with `render_json_schema`. Each root type produces one document:

```rust
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "$id": "<schema name>.schema.json",
  "title": "<schema name>",
  "x-morphir-fqname": "<canonical source FQName>",
  ...<the root schema, inline>,
  "$defs": { "<Name>": { ...<referenced schema> } }
}
```

Rules:
- `$defs` holds only the transitive closure the root actually references, so a document is self-contained and has no unused definitions.
- A `Schema::Reference(name)` renders as `{"$ref": "#/$defs/<name>"}`.
- `Schema::Union(members)` renders as `{"anyOf": [...]}`, except when every member is a simple type, where it renders as `{"type": ["string", "null"]}` style. Pick one and keep it: use `anyOf` in all cases, because it stays correct for referenced members.
- `Schema::OneOf { discriminator, variants }` renders as `{"oneOf": [...]}` where each variant is an object with the discriminator property `const`-fixed to the constructor name.
- `Schema::Tuple(members)` renders `{"type": "array", "prefixItems": [...], "items": false, "minItems": n, "maxItems": n}`.
- Documentation goes into `description`. The Morphir FQName goes into `x-morphir-fqname` on every named schema.
- Serialize with `serde_json::to_string_pretty` and push exactly one trailing `\n`.

Create `$RUST/crates/morphir-openapi-extension/src/render/mod.rs` declaring `pub mod json_schema;` and re-exporting `render_json_schema`.

In `generate_request`, replace the empty success result with target dispatch:

```rust
    let projection = match project(&package, &options) {
        Ok(projection) => projection,
        Err(diagnostic) => return Ok(failed(diagnostic)),
    };
    let artifacts = match target {
        Target::JsonSchema => render_json_schema(&projection),
        Target::OpenApi => Vec::new(),
    };
    Ok(GenerateResult {
        success: true,
        artifacts,
        diagnostics: projection
            .diagnostics
            .into_iter()
            .map(|(diagnostic, warning)| {
                diagnostic.into_diagnostic(if warning {
                    DiagnosticSeverity::Warning
                } else {
                    DiagnosticSeverity::Error
                })
            })
            .collect(),
    })
```

Bind the target with `let Some(target) = Target::parse(&request.target) else { ... }` rather than the `_target` placeholder from Task 5. `Target::OpenApi` returning no artifacts is intentional here; the follow-up plan fills it in.

- [ ] **Step 4: Create the golden files**

Run: `cd $RUST && UPDATE_GOLDEN=1 cargo test -p morphir-openapi-extension --test golden`

Then read every generated file under `$RUST/crates/morphir-openapi-extension/tests/golden/` and check by eye that the schema says what the Morphir fixture means. A golden file is a reviewed artifact, not a recording — do not commit one you have not read.

- [ ] **Step 5: Run the tests to verify they pass**

Run: `cd $RUST && cargo test -p morphir-openapi-extension`
Expected: PASS, all suites.

- [ ] **Step 6: Commit**

```bash
cd $RUST
git add -A
git commit -m "feat(openapi): render JSON Schema 2020-12 documents for the json-schema target"
```

---

### Task 9: Prove the target works end to end through the CLI

**Files:**
- Create: `$MORPHIR/crates/morphir/tests/generate_json_schema.rs`
- Modify: `$MORPHIR/ecosystem/morphir-rust` (submodule pointer)
- Reference: `$MORPHIR/crates/morphir/tests/generate_extension.rs` (the Avro equivalent; copy its fixture and index helpers)

**Interfaces:**
- Consumes: everything above. This is the first test where the host, the protocol change, and the extension run together.
- Produces: proof that one installed extension serves a host-selected target.

- [ ] **Step 1: Write the failing test**

Create `$MORPHIR/crates/morphir/tests/generate_json_schema.rs`, modelled on `generate_extension.rs`. Read that file first and reuse its structure: it builds the guest, writes a schema-v2 local index, installs into an isolated `MORPHIR_HOME`, and runs the CLI.

```rust
//! End-to-end coverage for the morphir-openapi extension.
//!
//! Build the guest first:
//! `cargo build --locked --release --manifest-path ecosystem/morphir-rust/Cargo.toml \
//!   -p morphir-openapi-extension --target wasm32-unknown-unknown`

// ... reuse the index and install helpers from generate_extension.rs, with:
//   artifact_name = "morphir_openapi_extension.wasm"
//   id            = "morphir-openapi"
//   backend       = { "targets": ["openapi", "json-schema"], "irVersions": ["3", "4"] }

#[test]
fn generates_json_schema_through_the_installed_extension() {
    let fixture = OpenApiCliMother::new(openapi_guest_path());

    let output = fixture.generate(&["--target", "json-schema"]);

    assert!(output.status.success(), "{}", String::from_utf8_lossy(&output.stderr));
    let generated = fixture.output_dir();
    let documents: Vec<_> = std::fs::read_dir(&generated)
        .expect("the output directory exists")
        .filter_map(Result::ok)
        .map(|entry| entry.file_name().to_string_lossy().into_owned())
        .filter(|name| name.ends_with(".schema.json"))
        .collect();
    assert!(!documents.is_empty(), "no schema documents in {generated:?}");
}

#[test]
fn selects_the_extension_by_target_rather_than_by_id() {
    let fixture = OpenApiCliMother::new(openapi_guest_path());

    let output = fixture.generate(&["--target", "not-a-target"]);

    assert!(!output.status.success());
    let stderr = String::from_utf8_lossy(&output.stderr);
    assert!(
        stderr.contains("No installed backend provider advertises target 'not-a-target'"),
        "{stderr}"
    );
}
```

Name the mother struct and helpers to match whatever `generate_extension.rs` already calls its Avro equivalents, so the two files read the same way.

- [ ] **Step 2: Build the guest and run the test to verify it fails**

```bash
cd $MORPHIR
cargo build --locked --release \
  --manifest-path ecosystem/morphir-rust/Cargo.toml \
  -p morphir-openapi-extension --target wasm32-unknown-unknown
cargo test -p morphir --test generate_json_schema
```
Expected: FAIL, because the test file's helpers do not exist yet, then FAIL on assertions until the helpers are correct.

- [ ] **Step 3: Fill in the fixture helpers**

Copy the index-writing and install helpers from `generate_extension.rs` verbatim, changing only the extension ID, artifact file name, and the `backend` capability block shown in Step 1. Do not change `generate_extension.rs` itself; the Avro end-to-end test must keep passing unchanged.

- [ ] **Step 4: Run both end-to-end suites**

Run: `cd $MORPHIR && cargo test -p morphir --test generate_extension --test generate_json_schema`
Expected: PASS. The Avro suite proves the protocol change did not break the single-target case; the new suite proves target dispatch works.

- [ ] **Step 5: Run every check the CI runs**

```bash
cd $RUST && cargo fmt --check && cargo clippy --workspace --all-targets -- -D warnings && cargo test --workspace
cd $MORPHIR && cargo fmt --check && cargo clippy --workspace --all-targets -- -D warnings && cargo test --workspace
```
Expected: PASS everywhere. Read `$MORPHIR/.github/workflows/ci.yml` and `$RUST/.github/workflows/ci.yml` and run any additional job command they define, such as a lint task under `mise`.

- [ ] **Step 6: Commit**

```bash
cd $MORPHIR
git add crates/morphir/tests/generate_json_schema.rs ecosystem/morphir-rust
git commit -m "test(cli): generate JSON Schema through the installed morphir-openapi extension"
```

---

## Self-Review

**Spec coverage.** Protocol change: Tasks 1 through 3. Normalization extraction: Task 4. Extension identity and two advertised targets: Task 5. Options and precedence: Task 6. Shared schema projection and the type-mapping table: Task 7. `json-schema` dialect, one file per root, `$defs` closure, collision-is-an-error: Tasks 7 and 8. Guest dispatch and missing-target behavior: Tasks 5 and 8. Umbrella end-to-end test: Task 9. Deferred to the follow-up plan by design: the OpenAPI 3.1 and 3.0 renderers, paths and operations, the `result_responses` option, the cross-target equivalence assertion, the user guides, the proposal document, and the release.

**Type consistency.** `SchemaOptions` is introduced in Task 6 and read in Tasks 7 and 8. `SchemaProjection`, `Schema`, and `NamedSchema` are defined in Task 7 and consumed in Task 8. `Target::parse` is introduced in Task 5 and its binding is corrected from `_target` to `target` in Task 8 Step 3, which is called out there explicitly. `SchemaDiagnostic` constructors used in Task 7 (`unsupported_form`, `name_collision`) are all defined in Task 5.

**Known adaptation points.** Three places depend on names this plan could not verify without running the code: the exact IR mother function names in `morphir-projection::testing` (Task 7 Step 1), the exact `export_extension!` and `min_sdk_version` values in the Avro crate (Task 5 Step 5), and the helper names in `generate_extension.rs` (Task 9). Each of those steps says to read the existing file first and match it.
