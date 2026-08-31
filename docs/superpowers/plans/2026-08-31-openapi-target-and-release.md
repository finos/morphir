# OpenAPI target and release — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the `openapi` target to the `morphir-openapi` extension, document both targets, and publish the extension as `0.1.0` through the existing registry-driven release workflow.

**Architecture:** The `openapi` target reuses the schema projection the `json-schema` target already uses, so a type has the same schema in either output. On top of that projection it adds an OpenAPI document envelope, `components/schemas`, and `paths` synthesized from Morphir value specifications. OpenAPI 3.1 is the default; 3.0 is a downgrade renderer over the same projection. Release reuses the registry-driven workflow that published the Avro extension, after the packaging helpers stop hardcoding Avro.

**Tech Stack:** Rust (workspace edition), `serde`/`serde_json`, `thiserror`, `pretty_assertions`, an OpenAPI validator dev-dependency, Python 3.11+ packaging scripts, GitHub Actions, `wasm-tools`, `mise` tasks.

**Spec:** `docs/superpowers/specs/2026-08-31-openapi-json-schema-backend-design.md`

**Prerequisite:** `docs/superpowers/plans/2026-08-31-openapi-json-schema-foundation.md` must be complete. This plan builds on `SchemaOptions`, `SchemaProjection`, `Schema`, `Target`, `SchemaDiagnostic`, and `render_json_schema` from it.

## Global Constraints

- Two repositories. `MORPHIR` = `/Users/damian/.t3/worktrees/morphir/t3code-ccf19da9` (umbrella). `RUST` = `$MORPHIR/ecosystem/morphir-rust` (git submodule with its own history).
- Extension ID `morphir-openapi`, crate `morphir-openapi-extension`, version `0.1.0`, release tag `extension/openapi/v0.1.0`, registry short ID `openapi`.
- Advertised targets stay `["openapi", "json-schema"]` in that order. Advertised IR versions stay `["3", "4"]`.
- OpenAPI default version `3.1.0`. The `version = "3.0"` option renders `3.0.3`.
- Diagnostic codes for the `openapi` target are `OAS001` and onward. `json-schema` codes `JSC001`–`JSC004` from the foundation plan are unchanged.
- Option names use `snake_case`. Option precedence: backend defaults, then the `morphir.toml` table, then CLI `--option` values in order, last wins.
- Operation override keys use canonical Morphir FQName syntax `package:module#local`.
- Every artifact's content ends with exactly one `\n`.
- No AI attribution in commits. EasyCLA rejects `Co-Authored-By: Claude` and "Generated with Claude Code" lines.
- Conventional Commits messages.

---

### Task 1: Extend the options for the OpenAPI target

**Files:**
- Modify: `$RUST/crates/morphir-openapi-extension/src/options.rs`
- Modify: `$RUST/crates/morphir-openapi-extension/tests/options.rs`

**Interfaces:**
- Consumes: `SchemaOptions`, `Unsupported`, `SchemaDiagnostic::invalid_option` (foundation plan).
- Produces, all on `SchemaOptions`:
  - `pub version: OpenApiVersion` — `pub enum OpenApiVersion { V31, V30 }`, serde values `"3.1"` and `"3.0"`, default `V31`
  - `pub projection: Projection` — `pub enum Projection { Schemas, OperationsEntryPoints, OperationsPublic }`, serde `kebab-case`, default `Schemas`
  - `pub result_responses: ResultResponses` — `pub enum ResultResponses { Data, Split }`, serde `kebab-case`, default `Data`
  - `pub error_status: u16` — default `400`, valid range 400 through 599
  - `pub operations: BTreeMap<String, OperationOverride>` — default empty
  - `pub struct OperationOverride { pub method: Option<HttpMethod>, pub path: Option<String>, pub parameters: BTreeMap<String, ParameterBinding> }`
  - `pub enum HttpMethod { Get, Put, Post, Delete, Patch }`, serde lowercase
  - `pub enum ParameterBinding { Path, Query, Header, Body }`, serde lowercase

- [ ] **Step 1: Write the failing tests**

Append to `$RUST/crates/morphir-openapi-extension/tests/options.rs`:

```rust
use morphir_openapi_extension::{HttpMethod, OpenApiVersion, ParameterBinding, Projection, ResultResponses};

#[test]
fn defaults_to_openapi_3_1_schemas_and_data_results() {
    let options = SchemaOptions::default();

    assert_eq!(options.version, OpenApiVersion::V31);
    assert_eq!(options.projection, Projection::Schemas);
    assert_eq!(options.result_responses, ResultResponses::Data);
    assert_eq!(options.error_status, 400);
    assert!(options.operations.is_empty());
}

#[test]
fn decodes_the_documented_option_spellings() {
    let options = SchemaOptions::from_map(&map([
        ("version", json!("3.0")),
        ("projection", json!("operations-entry-points")),
        ("result_responses", json!("split")),
        ("error_status", json!(422)),
    ]))
    .expect("the documented spellings decode");

    assert_eq!(options.version, OpenApiVersion::V30);
    assert_eq!(options.projection, Projection::OperationsEntryPoints);
    assert_eq!(options.result_responses, ResultResponses::Split);
    assert_eq!(options.error_status, 422);
}

#[test]
fn decodes_a_per_operation_override() {
    let options = SchemaOptions::from_map(&map([(
        "operations",
        json!({
            "acme/customer:customer#find-customer": {
                "method": "get",
                "path": "/customers/{customerId}",
                "parameters": {"customerId": "path"}
            }
        }),
    )]))
    .expect("an override table decodes");

    let override_entry = options
        .operations
        .get("acme/customer:customer#find-customer")
        .expect("the override is keyed by canonical FQName");
    assert_eq!(override_entry.method, Some(HttpMethod::Get));
    assert_eq!(override_entry.path.as_deref(), Some("/customers/{customerId}"));
    assert_eq!(
        override_entry.parameters.get("customerId"),
        Some(&ParameterBinding::Path)
    );
}

#[test]
fn rejects_an_error_status_outside_the_error_range() {
    let error = SchemaOptions::from_map(&map([("error_status", json!(200))]))
        .expect_err("200 is not an error status");

    assert_eq!(error.code(), "JSC002");
}

#[test]
fn rejects_an_unknown_openapi_version() {
    let error = SchemaOptions::from_map(&map([("version", json!("2.0"))]))
        .expect_err("only 3.1 and 3.0 decode");

    assert_eq!(error.code(), "JSC002");
}

#[test]
fn rejects_an_override_path_without_a_leading_slash() {
    let error = SchemaOptions::from_map(&map([(
        "operations",
        json!({"acme/customer:customer#find-customer": {"path": "customers"}}),
    )]))
    .expect_err("a path template starts with a slash");

    assert_eq!(error.code(), "JSC002");
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd $RUST && cargo test -p morphir-openapi-extension --test options`
Expected: FAIL. `OpenApiVersion` and the other new items do not exist.

- [ ] **Step 3: Extend the options module**

In `$RUST/crates/morphir-openapi-extension/src/options.rs`, add the fields to `SchemaOptions` with doc comments, keeping `#[serde(default, deny_unknown_fields)]`, and set the documented defaults in the `Default` implementation. Add the enums with the serde spellings listed in this task's **Interfaces** block.

Range and shape checks that serde cannot express go in a `validate` method called at the end of `from_map`, following the Avro precedent at `$RUST/crates/morphir-avro-extension/src/options.rs`:

```rust
impl SchemaOptions {
    /// Validate ranges and shapes after decoding or direct construction.
    ///
    /// Projection entry points must call this when their options did not come
    /// from [`Self::from_map`].
    pub fn validate(&self) -> Result<(), SchemaDiagnostic> {
        if !(400..=599).contains(&self.error_status) {
            return Err(SchemaDiagnostic::invalid_option(format!(
                "error_status ({}) must be in the range 400 through 599",
                self.error_status
            )));
        }
        for (source_name, operation) in &self.operations {
            if let Some(path) = &operation.path {
                if !path.starts_with('/') {
                    return Err(SchemaDiagnostic::invalid_option(format!(
                        "operation path for {source_name} must start with '/': {path}"
                    )));
                }
            }
        }
        Ok(())
    }
}
```

Re-export the new public items from `$RUST/crates/morphir-openapi-extension/src/lib.rs`.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd $RUST && cargo test -p morphir-openapi-extension --test options`
Expected: PASS, 11 tests (5 from the foundation plan plus 6 here).

- [ ] **Step 5: Commit**

```bash
cd $RUST
git add -A
git commit -m "feat(openapi): decode OpenAPI version, projection, and operation options"
```

---

### Task 2: Render the OpenAPI 3.1 document in `schemas` mode

**Files:**
- Create: `$RUST/crates/morphir-openapi-extension/src/render/openapi.rs`
- Modify: `$RUST/crates/morphir-openapi-extension/src/render/mod.rs`
- Modify: `$RUST/crates/morphir-openapi-extension/src/render/json_schema.rs` (extract the shared schema-body writer)
- Modify: `$RUST/crates/morphir-openapi-extension/src/lib.rs`
- Create: `$RUST/crates/morphir-openapi-extension/tests/cross_target.rs`
- Modify: `$RUST/crates/morphir-openapi-extension/tests/golden.rs`
- Create: `$RUST/crates/morphir-openapi-extension/tests/golden/customer.openapi-3.1.json`

**Interfaces:**
- Consumes: `SchemaProjection`, `Schema`, `SchemaOptions` (foundation plan + Task 1).
- Produces:
  - `pub fn render_openapi(projection: &SchemaProjection, options: &SchemaOptions) -> Vec<Artifact>`
  - `pub(crate) fn schema_body(schema: &Schema, reference_base: &str) -> serde_json::Value` shared by both renderers, where `reference_base` is `"#/$defs/"` for JSON Schema and `"#/components/schemas/"` for OpenAPI
  - Artifact path: one document per package, `openapi.json`

- [ ] **Step 1: Write the failing cross-target test**

Create `$RUST/crates/morphir-openapi-extension/tests/cross_target.rs`:

```rust
use std::collections::HashMap;

use morphir_extension_sdk::{Backend, GenerateRequest};
use morphir_openapi_extension::OpenApiExtension;
use morphir_projection::testing::mothers;
use pretty_assertions::assert_eq;
use serde_json::Value;

fn generate(target: &str) -> morphir_extension_sdk::GenerateResult {
    OpenApiExtension
        .generate(GenerateRequest {
            ir: mothers::classic::customer_library(),
            target: target.into(),
            options: HashMap::new(),
        })
        .expect("generation is a successful MEP call")
}

fn rebase(value: &Value, from: &str, to: &str) -> Value {
    match value {
        Value::Object(members) => members
            .iter()
            .map(|(key, member)| {
                if key == "$ref" {
                    let reference = member.as_str().unwrap_or_default().replace(from, to);
                    (key.clone(), Value::String(reference))
                } else {
                    (key.clone(), rebase(member, from, to))
                }
            })
            .collect::<serde_json::Map<_, _>>()
            .into(),
        Value::Array(members) => members.iter().map(|m| rebase(m, from, to)).collect(),
        other => other.clone(),
    }
}

#[test]
fn a_type_has_the_same_schema_in_both_targets() {
    let schema_result = generate("json-schema");
    let openapi_result = generate("openapi");

    let openapi: Value = serde_json::from_str(
        &openapi_result
            .artifacts
            .iter()
            .find(|artifact| artifact.path == "openapi.json")
            .expect("the openapi document is generated")
            .content,
    )
    .expect("valid JSON");
    let components = openapi["components"]["schemas"]
        .as_object()
        .expect("components/schemas is an object");

    let mut compared = 0;
    for artifact in &schema_result.artifacts {
        let document: Value = serde_json::from_str(&artifact.content).expect("valid JSON");
        for (name, definition) in document["$defs"].as_object().into_iter().flatten() {
            let component = components
                .get(name)
                .unwrap_or_else(|| panic!("{name} is missing from components/schemas"));
            assert_eq!(
                rebase(definition, "#/$defs/", "#/components/schemas/"),
                *component,
                "{name} differs between targets"
            );
            compared += 1;
        }
    }
    assert!(compared > 0, "the fixture produced no shared definitions");
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd $RUST && cargo test -p morphir-openapi-extension --test cross_target`
Expected: FAIL. The `openapi` target produces no artifacts.

- [ ] **Step 3: Extract the shared schema body writer**

Move the schema-to-JSON conversion out of `json_schema.rs` into `render/mod.rs` as `pub(crate) fn schema_body(schema: &Schema, reference_base: &str) -> Value`, taking the reference prefix as a parameter. `render_json_schema` calls it with `"#/$defs/"`. Nothing else about the JSON Schema renderer changes, and its goldens must not change.

- [ ] **Step 4: Write the OpenAPI renderer**

Create `$RUST/crates/morphir-openapi-extension/src/render/openapi.rs` producing one `openapi.json` per package:

```json
{
  "openapi": "3.1.0",
  "info": {
    "title": "<canonical Morphir package name>",
    "version": "0.0.0",
    "x-morphir-package": "<canonical Morphir package name>"
  },
  "paths": {},
  "components": {"schemas": {}}
}
```

Rules:
- `components/schemas` holds every named schema in `projection.definitions` and every root, keyed by schema name, with bodies from `schema_body(schema, "#/components/schemas/")`.
- `info.version` is `"0.0.0"` unless the normalized package carries a version. The Morphir package name always goes in `x-morphir-package`.
- In `Projection::Schemas`, `paths` is an empty object. Emit the key rather than omitting it, because some validators require it.
- Serialize with `serde_json::to_string_pretty` and one trailing `\n`.

In `render/mod.rs`, declare `pub mod openapi;` and re-export `render_openapi`. In `generate_request`, replace the `Target::OpenApi => Vec::new()` arm:

```rust
        Target::OpenApi => render_openapi(&projection, &options),
```

- [ ] **Step 5: Add the golden and validity tests**

Append to `$RUST/crates/morphir-openapi-extension/tests/golden.rs`:

```rust
fn generate_openapi(ir: Value, options: HashMap<String, Value>) -> morphir_extension_sdk::GenerateResult {
    OpenApiExtension
        .generate(GenerateRequest {
            ir,
            target: "openapi".into(),
            options,
        })
        .expect("generation is a successful MEP call")
}

#[test]
fn renders_one_openapi_document_per_package() {
    let result = generate_openapi(mothers::classic::customer_library(), HashMap::new());

    assert!(result.success, "{:?}", result.diagnostics);
    assert_eq!(result.artifacts.len(), 1);
    let artifact = &result.artifacts[0];
    assert_eq!(artifact.path, "openapi.json");
    assert!(artifact.content.ends_with('\n'));
    assert!(!artifact.content.ends_with("\n\n"));

    let document: Value = serde_json::from_str(&artifact.content).expect("valid JSON");
    assert_eq!(document["openapi"], "3.1.0");
    assert!(document["components"]["schemas"].is_object());
    assert!(document["paths"].is_object());
    assert_eq!(
        artifact.content,
        golden("customer.openapi-3.1.json", &artifact.content)
    );
}
```

- [ ] **Step 6: Create and read the golden**

Run: `cd $RUST && UPDATE_GOLDEN=1 cargo test -p morphir-openapi-extension --test golden`

Read `$RUST/crates/morphir-openapi-extension/tests/golden/customer.openapi-3.1.json` in full and check that each component schema says what the Morphir fixture means. Do not commit a golden you have not read.

- [ ] **Step 7: Run the tests to verify they pass**

Run: `cd $RUST && cargo test -p morphir-openapi-extension`
Expected: PASS, including `cross_target` and the unchanged JSON Schema goldens.

- [ ] **Step 8: Commit**

```bash
cd $RUST
git add -A
git commit -m "feat(openapi): render OpenAPI 3.1 documents in schemas mode"
```

---

### Task 3: Synthesize paths from entry points

**Files:**
- Create: `$RUST/crates/morphir-openapi-extension/src/schema/operations.rs`
- Modify: `$RUST/crates/morphir-openapi-extension/src/schema/mod.rs`
- Modify: `$RUST/crates/morphir-openapi-extension/src/render/openapi.rs`
- Create: `$RUST/crates/morphir-openapi-extension/tests/operations.rs`
- Create: `$RUST/crates/morphir-openapi-extension/tests/golden/customer.openapi-3.1-entry-points.json`

**Interfaces:**
- Consumes: `morphir_projection::{ValueSpecification, ValueKind, EntryPointMetadata, EntryPointKind}`; `SchemaOptions.projection`, `SchemaOptions.operations` (Task 1).
- Produces:
  - `pub struct Operation { pub source_name: String, pub method: HttpMethod, pub path: String, pub request: Vec<SchemaField>, pub response: Schema, pub entry_point: Option<EntryPointMetadata>, pub doc: Option<String> }`
  - `pub fn project_operations(package: &ProjectionPackage, projection: &mut SchemaProjection, options: &SchemaOptions) -> Result<Vec<Operation>, SchemaDiagnostic>`
  - `SchemaProjection` gains `pub operations: Vec<Operation>`

- [ ] **Step 1: Write the failing tests**

Create `$RUST/crates/morphir-openapi-extension/tests/operations.rs`:

```rust
use std::collections::HashMap;

use morphir_extension_sdk::{Backend, GenerateRequest};
use morphir_openapi_extension::OpenApiExtension;
use morphir_projection::testing::mothers;
use serde_json::{Value, json};

fn document(ir: Value, options: HashMap<String, Value>) -> Value {
    let result = OpenApiExtension
        .generate(GenerateRequest {
            ir,
            target: "openapi".into(),
            options,
        })
        .expect("generation is a successful MEP call");
    assert!(result.success, "{:?}", result.diagnostics);
    serde_json::from_str(&result.artifacts[0].content).expect("valid JSON")
}

fn map(entries: impl IntoIterator<Item = (&'static str, Value)>) -> HashMap<String, Value> {
    entries
        .into_iter()
        .map(|(key, value)| (key.to_owned(), value))
        .collect()
}

#[test]
fn schemas_mode_emits_no_paths() {
    let document = document(mothers::v4::customer_application(), HashMap::new());

    assert_eq!(document["paths"], json!({}));
}

#[test]
fn entry_point_mode_posts_to_a_module_scoped_path() {
    let document = document(
        mothers::v4::customer_application(),
        map([("projection", json!("operations-entry-points"))]),
    );

    let paths = document["paths"].as_object().expect("paths is an object");
    assert!(!paths.is_empty(), "declared entry points become paths");
    let (path, item) = paths.iter().next().expect("at least one path");
    assert!(path.starts_with('/'), "{path}");
    let operation = &item["post"];
    assert!(operation.is_object(), "the default method is POST: {item}");
    assert!(
        operation["requestBody"]["content"]["application/json"]["schema"]["properties"].is_object(),
        "arguments become a request body object"
    );
    assert!(operation["responses"]["200"].is_object());
    assert_eq!(operation["x-morphir-entry-point"], true);
}

#[test]
fn a_library_has_no_declared_entry_points() {
    let document = document(
        mothers::classic::customer_library(),
        map([("projection", json!("operations-entry-points"))]),
    );

    assert_eq!(document["paths"], json!({}));
    assert!(document["components"]["schemas"].as_object().is_some_and(|schemas| !schemas.is_empty()));
}

#[test]
fn a_constant_entry_point_takes_no_request_body() {
    let document = document(
        mothers::v4::customer_application(),
        map([("projection", json!("operations-entry-points"))]),
    );

    let has_constant = document["paths"]
        .as_object()
        .expect("paths is an object")
        .values()
        .any(|item| item["post"]["x-morphir-value-kind"] == "constant");
    if has_constant {
        let constant = document["paths"]
            .as_object()
            .unwrap()
            .values()
            .find(|item| item["post"]["x-morphir-value-kind"] == "constant")
            .unwrap();
        assert!(constant["post"]["requestBody"].is_null());
    }
}
```

If `mothers::v4::customer_application()` is not the exact fixture name, run `grep -rn "pub fn" $RUST/crates/morphir-projection/src/testing/v4.rs` and use the fixture that returns a v4 Application with declared entry points.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd $RUST && cargo test -p morphir-openapi-extension --test operations`
Expected: FAIL. `entry_point_mode_posts_to_a_module_scoped_path` finds an empty `paths` object.

- [ ] **Step 3: Project operations**

Create `$RUST/crates/morphir-openapi-extension/src/schema/operations.rs`. For each module, for each `ValueSpecification` selected by the projection mode:

- `Projection::Schemas` selects nothing.
- `Projection::OperationsEntryPoints` selects only values whose `entry_point` is `Some`.
- `Projection::OperationsPublic` selects every public value specification.

Default mapping, before any override:
- Method `HttpMethod::Post`.
- Path `/{module}/{entryPoint}` where the module segments are joined with `/` and lowercased, and the value name is `field_name(name)`.
- Request: each `ValueSpecification.inputs` entry becomes a `SchemaField` with `field_name(input.name)` and the projected input type. A `ValueKind::Constant` has no inputs and therefore no request body.
- Response `200`: the projected `output` type, or `Schema::Null` when `output` is `None`.
- Every operation carries `x-morphir-fqname` and `x-morphir-value-kind` (`"function"` or `"constant"`). A declared entry point also carries `x-morphir-entry-point: true`, `x-morphir-entry-point-id`, and a lowercase `x-morphir-entry-point-kind` of `main`, `command`, or `handler`.

A path collision between two operations is `SchemaDiagnostic` with code `OAS001` and the message naming both Morphir FQNames. Introduce `SchemaDiagnostic::operation_collision(source_name: &str, message: impl Into<String>)` with code `OAS001` in `diagnostic.rs`.

Add `pub operations: Vec<Operation>` to `SchemaProjection`, populated by `project` when the target is `openapi`. Keep the `json-schema` path free of operation work: `render_json_schema` ignores the field.

- [ ] **Step 4: Render the paths**

In `render/openapi.rs`, turn each `Operation` into a path item:

```json
{
  "/customer/findCustomer": {
    "post": {
      "operationId": "customerFindCustomer",
      "x-morphir-fqname": "acme/customer:customer#find-customer",
      "x-morphir-value-kind": "function",
      "requestBody": {
        "required": true,
        "content": {"application/json": {"schema": {"type": "object", "properties": {}, "required": []}}}
      },
      "responses": {
        "200": {
          "description": "Successful result",
          "content": {"application/json": {"schema": {"$ref": "#/components/schemas/Customer"}}}
        }
      }
    }
  }
}
```

`operationId` is `lower_camel_case(module segments + value name)` and must be unique; a duplicate is the same `OAS001` collision error.

- [ ] **Step 5: Create and read the golden**

Add a golden case for entry-point mode to `tests/golden.rs` following the pattern in Task 2 Step 5, then run:

`cd $RUST && UPDATE_GOLDEN=1 cargo test -p morphir-openapi-extension --test golden`

Read `customer.openapi-3.1-entry-points.json` in full before committing it.

- [ ] **Step 6: Run the tests to verify they pass**

Run: `cd $RUST && cargo test -p morphir-openapi-extension`
Expected: PASS, all suites, with `cross_target` still passing because operations do not change `components/schemas`.

- [ ] **Step 7: Commit**

```bash
cd $RUST
git add -A
git commit -m "feat(openapi): synthesize paths from declared entry points"
```

---

### Task 4: Add public-value operations, result splitting, and overrides

**Files:**
- Modify: `$RUST/crates/morphir-openapi-extension/src/schema/operations.rs`
- Modify: `$RUST/crates/morphir-openapi-extension/src/render/openapi.rs`
- Modify: `$RUST/crates/morphir-openapi-extension/tests/operations.rs`

**Interfaces:**
- Consumes: `Operation`, `project_operations` (Task 3); `SchemaOptions.result_responses`, `error_status`, `operations` (Task 1).
- Produces: no new public types. `Operation.method`, `Operation.path`, and the rendered responses now reflect the option table.

- [ ] **Step 1: Write the failing tests**

Append to `$RUST/crates/morphir-openapi-extension/tests/operations.rs`:

```rust
#[test]
fn public_mode_covers_values_that_are_not_entry_points() {
    let entry_points = document(
        mothers::v4::customer_application(),
        map([("projection", json!("operations-entry-points"))]),
    );
    let public = document(
        mothers::v4::customer_application(),
        map([("projection", json!("operations-public"))]),
    );

    let entry_point_count = entry_points["paths"].as_object().unwrap().len();
    let public_count = public["paths"].as_object().unwrap().len();
    assert!(
        public_count > entry_point_count,
        "public mode covers more values: {public_count} vs {entry_point_count}"
    );
}

#[test]
fn a_result_stays_data_in_the_200_response_by_default() {
    let document = document(
        mothers::v4::customer_application(),
        map([("projection", json!("operations-public"))]),
    );

    for item in document["paths"].as_object().unwrap().values() {
        for operation in item.as_object().unwrap().values() {
            let responses = operation["responses"].as_object().unwrap();
            assert_eq!(
                responses.keys().collect::<Vec<_>>(),
                vec!["200"],
                "the default emits only a 200 response"
            );
        }
    }
}

#[test]
fn split_mode_moves_the_error_branch_to_the_configured_status() {
    let document = document(
        mothers::v4::customer_application(),
        map([
            ("projection", json!("operations-public")),
            ("result_responses", json!("split")),
            ("error_status", json!(422)),
        ]),
    );

    let has_error_response = document["paths"]
        .as_object()
        .unwrap()
        .values()
        .flat_map(|item| item.as_object().unwrap().values())
        .any(|operation| operation["responses"]["422"].is_object());
    assert!(has_error_response, "a Result-returning value gains a 422 response");
}

#[test]
fn an_override_replaces_the_method_and_the_path() {
    let document = document(
        mothers::v4::customer_application(),
        map([
            ("projection", json!("operations-public")),
            (
                "operations",
                json!({
                    "acme/customer:customer#find-customer": {
                        "method": "get",
                        "path": "/customers/{customerId}",
                        "parameters": {"customerId": "path"}
                    }
                }),
            ),
        ]),
    );

    let item = &document["paths"]["/customers/{customerId}"];
    assert!(item["get"].is_object(), "the override selects GET");
    assert!(item["get"]["requestBody"].is_null(), "a path parameter is not a body");
    let parameter = &item["get"]["parameters"][0];
    assert_eq!(parameter["name"], "customerId");
    assert_eq!(parameter["in"], "path");
    assert_eq!(parameter["required"], true);
}

#[test]
fn an_override_naming_an_unknown_value_is_an_error() {
    let result = OpenApiExtension
        .generate(GenerateRequest {
            ir: mothers::v4::customer_application(),
            target: "openapi".into(),
            options: map([
                ("projection", json!("operations-public")),
                ("operations", json!({"acme/customer:customer#no-such-value": {"method": "get"}})),
            ]),
        })
        .expect("generation is a successful MEP call");

    assert!(!result.success);
    assert_eq!(result.diagnostics[0].code.as_deref(), Some("OAS002"));
}
```

Adjust the FQName in the override tests to a value the v4 fixture actually declares. Run `grep -rn "find-customer\|entryPoint" $RUST/crates/morphir-projection/src/testing/v4.rs` to pick a real one.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd $RUST && cargo test -p morphir-openapi-extension --test operations`
Expected: FAIL on the split, override, and unknown-override tests.

- [ ] **Step 3: Apply the option table during operation projection**

In `operations.rs`:
- After building the default operation, look up `options.operations.get(source_name)` and apply `method` and `path` when present.
- A parameter bound to `Path`, `Query`, or `Header` is removed from the request body and rendered as an OpenAPI parameter. A `Path` binding must appear as a `{name}` placeholder in the override path; if it does not, fail with `OAS002`.
- After all operations are projected, any override key that matched no value specification fails with `OAS002`. Add `SchemaDiagnostic::unknown_operation(source_name: &str)` with code `OAS002`.
- Under `ResultResponses::Split`, when the projected output is the `Result` shape, put the `Ok` member's schema in the `200` response and the `Err` member's schema in the `options.error_status` response. Under `ResultResponses::Data`, keep the whole `Result` schema in `200`. Detect `Result` by the source FQName `morphir/SDK:result#result`, the same identity the Avro backend uses; do not detect by shape.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd $RUST && cargo test -p morphir-openapi-extension`
Expected: PASS, all suites.

- [ ] **Step 5: Commit**

```bash
cd $RUST
git add -A
git commit -m "feat(openapi): add public-value operations, result splitting, and overrides"
```

---

### Task 5: Render OpenAPI 3.0 through a downgrade pass

**Files:**
- Create: `$RUST/crates/morphir-openapi-extension/src/render/downgrade.rs`
- Modify: `$RUST/crates/morphir-openapi-extension/src/render/openapi.rs`
- Create: `$RUST/crates/morphir-openapi-extension/tests/downgrade.rs`
- Create: `$RUST/crates/morphir-openapi-extension/tests/golden/customer.openapi-3.0.json`

**Interfaces:**
- Consumes: the 3.1 document produced in Task 2 and Task 3; `SchemaOptions.version` (Task 1).
- Produces: `pub(crate) fn downgrade(document: Value) -> Result<Value, SchemaDiagnostic>` applied when `options.version == OpenApiVersion::V30`.

- [ ] **Step 1: Write the failing tests**

Create `$RUST/crates/morphir-openapi-extension/tests/downgrade.rs`:

```rust
use std::collections::HashMap;

use morphir_extension_sdk::{Backend, GenerateRequest};
use morphir_openapi_extension::OpenApiExtension;
use morphir_projection::testing::mothers;
use serde_json::{Value, json};

fn document(options: HashMap<String, Value>) -> Value {
    let result = OpenApiExtension
        .generate(GenerateRequest {
            ir: mothers::classic::customer_library(),
            target: "openapi".into(),
            options,
        })
        .expect("generation is a successful MEP call");
    assert!(result.success, "{:?}", result.diagnostics);
    serde_json::from_str(&result.artifacts[0].content).expect("valid JSON")
}

fn map(entries: impl IntoIterator<Item = (&'static str, Value)>) -> HashMap<String, Value> {
    entries
        .into_iter()
        .map(|(key, value)| (key.to_owned(), value))
        .collect()
}

fn walk(value: &Value, visit: &mut impl FnMut(&serde_json::Map<String, Value>)) {
    match value {
        Value::Object(members) => {
            visit(members);
            members.values().for_each(|member| walk(member, visit));
        }
        Value::Array(members) => members.iter().for_each(|member| walk(member, visit)),
        _ => {}
    }
}

#[test]
fn declares_the_3_0_version() {
    let document = document(map([("version", json!("3.0"))]));

    assert_eq!(document["openapi"], "3.0.3");
}

#[test]
fn replaces_null_unions_with_the_nullable_keyword() {
    let document = document(map([("version", json!("3.0"))]));

    let mut offending = Vec::new();
    walk(&document, &mut |members| {
        if let Some(Value::Array(types)) = members.get("type") {
            offending.push(types.clone());
        }
        if members.contains_key("prefixItems") || members.contains_key("$defs") {
            offending.push(vec![json!("unsupported 2020-12 keyword")]);
        }
    });

    assert!(offending.is_empty(), "3.0 forbids these forms: {offending:?}");

    let mut nullable_seen = false;
    walk(&document, &mut |members| {
        if members.get("nullable") == Some(&json!(true)) {
            nullable_seen = true;
        }
    });
    assert!(nullable_seen, "an optional field becomes nullable in 3.0");
}

#[test]
fn keeps_the_3_1_document_unchanged_by_default() {
    let document = document(HashMap::new());

    assert_eq!(document["openapi"], "3.1.0");
    let mut nullable_seen = false;
    walk(&document, &mut |members| {
        if members.contains_key("nullable") {
            nullable_seen = true;
        }
    });
    assert!(!nullable_seen, "3.1 uses type unions, not the nullable keyword");
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd $RUST && cargo test -p morphir-openapi-extension --test downgrade`
Expected: FAIL. The `version` option does not yet change the output.

- [ ] **Step 3: Write the downgrade pass**

Create `$RUST/crates/morphir-openapi-extension/src/render/downgrade.rs`. It rewrites the finished 3.1 document:

- `openapi` becomes `"3.0.3"`.
- `{"anyOf": [X, {"type": "null"}]}` becomes `X` with `"nullable": true` added. When `X` is a `$ref`, wrap it: `{"allOf": [{"$ref": "..."}], "nullable": true}`, because 3.0 forbids sibling keywords next to `$ref`.
- `{"type": ["a", "null"]}` becomes `{"type": "a", "nullable": true}`.
- `prefixItems` with `items: false` becomes `{"type": "array", "items": {"oneOf": [...]}, "minItems": n, "maxItems": n}`.
- `const` becomes a single-value `enum`.
- `$defs` must not appear; every named schema already lives in `components/schemas`, so a remaining `$defs` key is a bug. Fail with `SchemaDiagnostic::unsupported_form` naming the schema rather than dropping the key silently.
- `x-morphir-*` extension keys are valid in 3.0 and stay unchanged.

In `render/openapi.rs`, apply the pass when `options.version == OpenApiVersion::V30`, after the full 3.1 document is built. Building 3.1 first and rewriting is deliberate: there is one projection and one document builder, so the two versions cannot drift.

- [ ] **Step 4: Create and read the golden**

Add a 3.0 golden case to `tests/golden.rs`, then run:

`cd $RUST && UPDATE_GOLDEN=1 cargo test -p morphir-openapi-extension --test golden`

Read `customer.openapi-3.0.json` in full before committing it.

- [ ] **Step 5: Run the tests to verify they pass**

Run: `cd $RUST && cargo test -p morphir-openapi-extension && cargo clippy -p morphir-openapi-extension --all-targets -- -D warnings && cargo fmt --check`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
cd $RUST
git add -A
git commit -m "feat(openapi): render OpenAPI 3.0 through a downgrade pass"
```

---

### Task 6: Prove the OpenAPI target works through the CLI and write the user guides

**Files:**
- Modify: `$MORPHIR/crates/morphir/tests/generate_json_schema.rs` (add the OpenAPI cases; rename to `generate_openapi_extension.rs` if the file's name no longer fits)
- Create: `$MORPHIR/docs/generate/openapi.md`
- Create: `$MORPHIR/docs/generate/json-schema.md`
- Create: `$MORPHIR/docs/design/proposals/openapi-and-json-schema-backend.md`
- Modify: `$MORPHIR/docs/design/proposals/index.md`
- Modify: `$MORPHIR/ecosystem/morphir-rust` (submodule pointer)

**Interfaces:**
- Consumes: everything above, plus the foundation plan's CLI end-to-end fixture.
- Produces: user-facing documentation for both targets.

- [ ] **Step 1: Write the failing test**

Append to the umbrella end-to-end test file created in the foundation plan:

```rust
#[test]
fn generates_an_openapi_document_through_the_installed_extension() {
    let fixture = OpenApiCliMother::new(openapi_guest_path());

    let output = fixture.generate(&["--target", "openapi", "--option", "projection=operations-entry-points"]);

    assert!(output.status.success(), "{}", String::from_utf8_lossy(&output.stderr));
    let document = std::fs::read_to_string(fixture.output_dir().join("openapi.json"))
        .expect("the openapi document is written");
    let parsed: serde_json::Value = serde_json::from_str(&document).expect("valid JSON");
    assert_eq!(parsed["openapi"], "3.1.0");
}

#[test]
fn one_installed_extension_serves_both_targets() {
    let fixture = OpenApiCliMother::new(openapi_guest_path());

    let schema = fixture.generate(&["--target", "json-schema"]);
    let openapi = fixture.generate(&["--target", "openapi"]);

    assert!(schema.status.success(), "{}", String::from_utf8_lossy(&schema.stderr));
    assert!(openapi.status.success(), "{}", String::from_utf8_lossy(&openapi.stderr));
}
```

- [ ] **Step 2: Rebuild the guest and run the test to verify it fails, then passes**

```bash
cd $MORPHIR
cargo build --locked --release \
  --manifest-path ecosystem/morphir-rust/Cargo.toml \
  -p morphir-openapi-extension --target wasm32-unknown-unknown
cargo test -p morphir --test generate_json_schema
```
Expected: FAIL before rebuilding the guest with the Task 5 code, PASS after. If it passes on the first run, the guest binary was stale — delete it and rebuild to be sure the test exercises the new code.

- [ ] **Step 3: Write the JSON Schema user guide**

Create `$MORPHIR/docs/generate/json-schema.md` following the structure of `$MORPHIR/docs/generate/avro.md`: front matter with `title`, `sidebar_label`, `sidebar_position`; a status note stating the backend is not published and that installation uses a locally built extension and a local schema-v2 index; build and install commands; the `morphir generate --target json-schema` invocation; the options table; the type-mapping table from the spec; the diagnostic-code table for `JSC001` through `JSC004`; and the file-layout description.

State plainly that there is no public index yet. Do not imply an available release.

- [ ] **Step 4: Write the OpenAPI user guide**

Create `$MORPHIR/docs/generate/openapi.md` with the same structure, plus:
- the three projection modes and what each one emits,
- the default HTTP mapping and a worked `[codegen.openapi.operations."pkg:mod#name"]` override example,
- `result_responses` and `error_status`,
- the `version` option and what the 3.0 downgrade changes,
- the `OAS001` and `OAS002` diagnostic codes.

Both guides must state that the two targets come from the one `morphir-openapi` extension, installed once.

- [ ] **Step 5: Write the proposal document**

Create `$MORPHIR/docs/design/proposals/openapi-and-json-schema-backend.md` following the section shape of `wasm-extension-runtime-and-avro-backend.md`: what the design establishes, the extension boundary, projection modes, type projection, configuration and diagnostics, distribution and release ownership, implementation workstreams, testing and acceptance, alternatives and non-goals, references. Add it to `$MORPHIR/docs/design/proposals/index.md` in the same style as the existing entries.

- [ ] **Step 6: Check the documentation builds and the links resolve**

Run: `cd $MORPHIR && npm run build --prefix website 2>&1 | tail -20`
Expected: a successful Docusaurus build. If the project uses a different documentation command, read `$MORPHIR/package.json` and run the one defined there.

- [ ] **Step 7: Commit**

```bash
cd $MORPHIR
git add crates/morphir/tests docs/generate docs/design/proposals ecosystem/morphir-rust
git commit -m "docs(generate): document the OpenAPI and JSON Schema targets"
```

---

### Task 7: Generalize the packaging helpers beyond Avro

**Files:**
- Modify: `$RUST/scripts/extension_packaging/paths.py:103-125`
- Modify: `$RUST/scripts/extension_packaging/cli.py:13-60`
- Modify: `$RUST/tests/ci/test_package_extension_packaging.py`
- Modify: `$RUST/tests/ci/package_extension_test_support.py`
- Modify: `$RUST/tests/ci/test_package_extension_task.py`
- Modify: `$RUST/.mise/tasks/extension/artifact/avro`

**Interfaces:**
- Consumes: nothing from the Rust crates.
- Produces:
  - `validate_extension_staging(root: Path, short_id: str) -> None`
  - `clean_extension_staging(root: Path, short_id: str) -> None`
  - `clean_head_snapshot(root: Path, snapshot: Path, short_id: str) -> None`
  - CLI flags `--clean-extension-staging SHORT_ID`, `--validate-extension-staging SHORT_ID`, and `--clean-head-snapshot PATH --short-id SHORT_ID`

  Task 8 uses these from a new `openapi` artifact task.

- [ ] **Step 1: Write the failing tests**

Add to `$RUST/tests/ci/test_package_extension_packaging.py`, matching the file's existing test style and helpers:

```python
def test_validate_extension_staging_accepts_any_registered_short_id(tmp_path):
    root = make_repository(tmp_path)
    staging = root / ".morphir" / "build" / "extensions" / "openapi"
    staging.mkdir(parents=True)

    validate_extension_staging(root, "openapi")


def test_clean_extension_staging_refuses_a_traversing_short_id(tmp_path):
    root = make_repository(tmp_path)

    with pytest.raises(PackageError):
        clean_extension_staging(root, "../avro")


def test_head_snapshot_name_is_scoped_to_the_short_id(tmp_path):
    root = make_repository(tmp_path)
    snapshot = tmp_path / "morphir-openapi-head.ABC123"
    snapshot.mkdir()

    clean_head_snapshot(root, snapshot, "openapi")

    assert not snapshot.exists()


def test_head_snapshot_rejects_a_mismatched_short_id(tmp_path):
    root = make_repository(tmp_path)
    snapshot = tmp_path / "morphir-avro-head.ABC123"
    snapshot.mkdir()

    with pytest.raises(PackageError):
        clean_head_snapshot(root, snapshot, "openapi")
```

Use whatever repository fixture helper the file already provides instead of `make_repository` if the name differs; read the top of the file first.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd $RUST && python3 -m pytest tests/ci/test_package_extension_packaging.py -x -q`
Expected: FAIL with `ImportError` or `NameError` on `validate_extension_staging`.

- [ ] **Step 3: Generalize `paths.py`**

Replace `validate_avro_staging` and `clean_avro_staging` with short-ID versions, and validate the short ID against the same identifier pattern the packaging model already enforces, so a traversing value cannot reach the filesystem:

```python
SHORT_ID_PATTERN = re.compile(r"^[a-z0-9]+(?:-[a-z0-9]+)*$")


def require_short_id(short_id: str) -> str:
    """Return a registry short ID that is safe to use as a path component."""
    if not SHORT_ID_PATTERN.fullmatch(short_id):
        raise PackageError(f"invalid extension short ID: {short_id}")
    return short_id


def validate_extension_staging(root: Path, short_id: str) -> None:
    short_id = require_short_id(short_id)
    validate_repository_directory(
        root,
        (".morphir", "build", "extensions", short_id),
        f"{short_id} staging directory",
    )


def clean_extension_staging(root: Path, short_id: str) -> None:
    short_id = require_short_id(short_id)
    clean_repository_directory(
        root,
        (".morphir", "build", "extensions", short_id),
        f"{short_id} staging directory",
    )
```

In `clean_head_snapshot`, take `short_id` and build the expected name from it:

```python
def clean_head_snapshot(root: Path, snapshot: Path, short_id: str) -> None:
    short_id = require_short_id(short_id)
    snapshot = absolute_path(snapshot)
    expected = rf"morphir-{re.escape(short_id)}-head\.[A-Za-z0-9]+"
    if not re.fullmatch(expected, snapshot.name):
        raise PackageError(f"refusing to clean unexpected HEAD snapshot path: {snapshot}")
    # ... the remaining checks are unchanged
```

If `require_identifier` in `scripts/extension_packaging/model.py` already implements this validation, import and reuse it rather than adding a second pattern.

- [ ] **Step 4: Update the CLI and the Avro task that calls it**

In `cli.py`, replace the two boolean flags with value-taking flags:

```python
    parser.add_argument("--clean-extension-staging")
    parser.add_argument("--validate-extension-staging")
```

Update the mutually-exclusive operation count and the argument checks to test `is not None` instead of truthiness, and pass the value through to the new helpers. `--clean-head-snapshot` now also requires `--short-id`.

In `$RUST/.mise/tasks/extension/artifact/avro`, update every call:

```sh
python3 scripts/package_extension.py --validate-extension-staging avro
python3 scripts/package_extension.py --clean-extension-staging avro
python3 "$REPO_ROOT/scripts/package_extension.py" \
    --clean-head-snapshot "$SNAPSHOT_ROOT" --short-id avro
```

and change the snapshot template from `morphir-avro-head.XXXXXX` to keep the same name — `avro` is still the short ID here, so the name is unchanged. Only the flags change.

- [ ] **Step 5: Run the full CI test suite for the scripts**

Run: `cd $RUST && python3 -m pytest tests/ci -q`
Expected: PASS. Every previously passing test still passes; the flag rename shows up in `test_package_extension_task.py`, which asserts the exact command line the task runs.

- [ ] **Step 6: Prove the Avro bundle still builds byte-for-byte**

Run: `cd $RUST && mise run extension:artifact:avro && sha256sum .morphir/build/extensions/avro/*.wasm`
Expected: the task completes and the descriptor's `sha256` matches the file digest. This requires Java 11+ and `wasm-tools`; if either is unavailable, say so in the handoff rather than skipping the step silently.

- [ ] **Step 7: Commit**

```bash
cd $RUST
git add -A
git commit -m "refactor(packaging): scope extension staging helpers to a short ID"
```

---

### Task 8: Add the artifact task and the registry entry

**Files:**
- Create: `$RUST/.mise/tasks/extension/artifact/openapi`
- Modify: `$RUST/.github/extensions.toml`
- Modify: `$RUST/tests/ci/test_extension_release_definition.py`
- Modify: `$RUST/tests/ci/test_extension_release_routing.py`
- Modify: `$RUST/tests/ci/test_extension_release_assets.py`

**Interfaces:**
- Consumes: `validate_extension_staging`, `clean_extension_staging`, `clean_head_snapshot` (Task 7).
- Produces: `mise run extension:artifact:openapi` writing a verified bundle to `.morphir/build/extensions/openapi/`, and a registry entry that routes the `extension/openapi/v0.1.0` tag.

- [ ] **Step 1: Write the failing tests**

Add to `$RUST/tests/ci/test_extension_release_definition.py`:

```python
def test_registry_lists_the_openapi_extension():
    registry = load_registry()

    entry = registry["extensions"]["openapi"]

    assert entry["package"] == "morphir-openapi-extension"
    assert entry["extension_id"] == "morphir-openapi"
    assert entry["targets"] == ["openapi", "json-schema"]
    assert entry["ir_versions"] == ["3", "4"]
    assert entry["mep_versions"] == ["0.1"]


def test_a_multi_target_entry_reaches_the_release_descriptor(tmp_path):
    descriptor = json.loads(
        descriptor_bytes(
            "openapi",
            load_registry()["extensions"]["openapi"],
            "0.1.0",
            "morphir_openapi_extension.wasm",
            "0" * 64,
            None,
        )
    )

    assert descriptor["targets"] == ["openapi", "json-schema"]
    assert descriptor["extensionId"] == "morphir-openapi"
```

Add to `$RUST/tests/ci/test_extension_release_routing.py`:

```python
def test_openapi_tag_selects_only_the_openapi_extension():
    release = resolve_release(
        "extension/openapi/v0.1.0",
        load_registry(),
        workspace_version(),
        {"morphir-openapi-extension": "0.1.0", "morphir-avro-extension": "0.1.1"},
    )

    assert release.short_ids == ["openapi"]
    assert release.version == "0.1.0"


def test_workspace_tag_selects_both_extensions():
    release = resolve_release(
        f"v{workspace_version()}",
        load_registry(),
        workspace_version(),
        {"morphir-openapi-extension": "0.1.0", "morphir-avro-extension": "0.1.1"},
    )

    assert release.short_ids == ["avro", "openapi"]
```

Match the helper names the two files already use for loading the registry and the workspace version; read the top of each file first.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd $RUST && python3 -m pytest tests/ci/test_extension_release_definition.py tests/ci/test_extension_release_routing.py -q`
Expected: FAIL with `KeyError: 'openapi'`.

- [ ] **Step 3: Add the registry entry**

Append to `$RUST/.github/extensions.toml`:

```toml
[extensions.openapi]
package = "morphir-openapi-extension"
artifact = "morphir-openapi-extension"
extension_id = "morphir-openapi"
mep_versions = ["0.1"]
targets = ["openapi", "json-schema"]
ir_versions = ["3", "4"]
release_with_workspace = true
```

- [ ] **Step 4: Add the artifact task**

Create `$RUST/.mise/tasks/extension/artifact/openapi`, copying `$RUST/.mise/tasks/extension/artifact/avro` and changing:
- the `MISE description` to "Build and validate the independently versioned OpenAPI extension bundle",
- `MORPHIR_AVRO_*` environment variable names to `MORPHIR_OPENAPI_*`,
- `STAGING_DIR` to `.morphir/build/extensions/openapi` and `WASM` to `target/wasm32-unknown-unknown/release/morphir_openapi_extension.wasm`,
- the packaging flags to `--validate-extension-staging openapi`, `--clean-extension-staging openapi`, and `--clean-head-snapshot "$SNAPSHOT_ROOT" --short-id openapi`,
- `--short-id avro` to `--short-id openapi` in `run_pipeline`,
- the snapshot template to `morphir-openapi-head.XXXXXX`,
- the archived task path to `.mise/tasks/extension/artifact/openapi`.

Remove the Java and `mise run test:avro-idl` checks: this backend has no Avro IDL step. Keep the Python version check, the `wasm-tools validate` call, and the whole provenance snapshot mechanism unchanged — those are what make the bundle reproducible.

Replace the `require_snapshot_inputs` list entries that name Avro files with their OpenAPI equivalents:

```sh
    require_snapshot_executable ".mise/tasks/extension/artifact/openapi"
    require_snapshot_file "crates/morphir-openapi-extension/Cargo.toml"
    require_snapshot_file "crates/morphir-openapi-extension/src/lib.rs"
    require_snapshot_file "crates/morphir-openapi-extension/tests/guest.rs"
    require_snapshot_tree "crates/morphir-openapi-extension/src"
    require_snapshot_tree "crates/morphir-openapi-extension/tests"
    require_snapshot_tree "crates/morphir-projection/src"
```

Make it executable: `chmod +x $RUST/.mise/tasks/extension/artifact/openapi`.

- [ ] **Step 5: Build the bundle**

Run: `cd $RUST && mise run extension:artifact:openapi`
Expected: the task completes and writes `release.json`, the `.wasm` artifact, and a matching SHA-256 under `.morphir/build/extensions/openapi/`.

Run: `cd $RUST && cat .morphir/build/extensions/openapi/release.json`
Expected: `"extensionId": "morphir-openapi"`, `"targets": ["openapi", "json-schema"]`, `"version": "0.1.0"`.

- [ ] **Step 6: Run the CI script suite**

Run: `cd $RUST && python3 -m pytest tests/ci -q`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
cd $RUST
git add -A
git commit -m "feat(release): register the openapi extension for independent release"
```

---

### Task 9: Release `morphir-openapi` 0.1.0 and re-release Avro

**Files:**
- Modify: `$RUST/CHANGELOG.md`
- Modify: `$RUST/crates/morphir-avro-extension/Cargo.toml` (version to `0.1.1`)
- Modify: `$RUST/Cargo.lock`
- Modify: `$MORPHIR/docs/generate/avro.md` (install instructions for the new Avro version)
- Modify: `$MORPHIR/ecosystem/morphir-rust` (submodule pointer)

**Interfaces:**
- Consumes: the registry entry and artifact task (Task 8).
- Produces: published release assets for `extension/openapi/v0.1.0` and `extension/avro/v0.1.1`.

- [ ] **Step 1: Confirm the release is safe to cut**

```bash
cd $RUST
git status --short
cargo test --workspace
cargo clippy --workspace --all-targets -- -D warnings
cargo fmt --check
python3 -m pytest tests/ci -q
mise run check:pre-push
```
Expected: a clean tree and PASS everywhere. Do not continue past a failure.

- [ ] **Step 2: Bump the Avro version**

The SDK change in the foundation plan altered the Avro crate, so the published `0.1.0` artifact no longer matches its source. Set `version = "0.1.1"` in `$RUST/crates/morphir-avro-extension/Cargo.toml` and run `cd $RUST && cargo check -p morphir-avro-extension` to refresh `Cargo.lock`.

The Avro guest test asserts `info.version == env!("CARGO_PKG_VERSION")`, so it needs no edit.

- [ ] **Step 3: Write the changelog entries**

Add to `$RUST/CHANGELOG.md`, matching the file's existing format:

```markdown
### Added

- `morphir-openapi` extension 0.1.0, a WASM backend exposing the `openapi` and
  `json-schema` targets from one installed extension.
- `morphir-projection` crate holding the Morphir IR normalization shared by
  backend extensions.

### Changed

- **Breaking**: `GenerateRequest` now requires a `target` field. The host states
  the target it selected so that an extension advertising several targets can
  dispatch on it. MEP stays at 0.1.
- `morphir-avro-extension` 0.1.1 rebuilds against the new request shape. Its
  generated output is unchanged.
```

If the repository has a release task for this (`mise run release:changelog-entry`), use it instead of editing by hand.

- [ ] **Step 4: Verify both bundles build from a clean tree**

```bash
cd $RUST
git add -A && git commit -m "chore(release): prepare morphir-openapi 0.1.0 and morphir-avro 0.1.1"
mise run extension:artifact:avro
mise run extension:artifact:openapi
```
Expected: both tasks complete. A clean tree makes each task take the HEAD-snapshot path, which is the same path the release workflow uses, so this is the real rehearsal.

- [ ] **Step 5: Ask before tagging**

Tagging triggers `release.yml`, which creates a public GitHub release and uploads assets. That is outward-facing and hard to reverse.

Report to the user: both bundles built, the digests, and the exact commands you propose to run. Wait for explicit approval before running them.

```bash
cd $RUST
git push origin HEAD
git tag extension/openapi/v0.1.0
git tag extension/avro/v0.1.1
git push origin extension/openapi/v0.1.0 extension/avro/v0.1.1
```

If the repository provides `mise run release:tag-create`, prefer it, because it validates the tag against the Cargo version before creating it.

- [ ] **Step 6: Watch the release workflow**

```bash
cd $RUST
gh run watch "$(gh run list --workflow=release.yml --limit 1 --json databaseId --jq '.[0].databaseId')"
gh release view extension/openapi/v0.1.0
```
Expected: the run succeeds and the release lists `morphir_openapi_extension.wasm` and `release.json`.

- [ ] **Step 7: Point the umbrella repository at the released commit**

```bash
cd $MORPHIR
git -C ecosystem/morphir-rust fetch origin
git add ecosystem/morphir-rust
git commit -m "chore(ecosystem): update Morphir Rust pin to the released openapi extension"
```

Update `$MORPHIR/docs/generate/avro.md` where it names the Avro version or the local-install steps, so the documented commands match `0.1.1`. Leave the "not released" status note in place if a public index still does not exist.

- [ ] **Step 8: Close the beads issues and report the handoff**

```bash
cd $MORPHIR
bd close <ids>
git status --short
```
Report changed files, the verification commands that ran, and their results.

---

## Self-Review

**Spec coverage.** OpenAPI 3.1 default and 3.0 option: Tasks 1, 2, and 5. Projection modes: Tasks 3 and 4. HTTP mapping with overrides: Tasks 3 and 4. `Result` as data with a split option: Task 4. Shared schema core proven by the cross-target assertion: Task 2. External validator coverage: Task 2 Step 5 and the foundation plan's `jsonschema` dev-dependency; an OpenAPI validator dev-dependency is added in Task 2 if one is available for Rust, and the structural assertions in Tasks 3 and 5 cover the document shape when it is not. User guides and proposal: Task 6. Registry entry, packaging generalization, artifact task, tag, and the Avro re-release: Tasks 7 through 9. Not in scope, per the spec: a public extension index.

**Type consistency.** `SchemaOptions` gains fields in Task 1 that Tasks 2 through 5 read. `Operation` and `project_operations` are defined in Task 3 and extended in Task 4. `schema_body` is extracted in Task 2 and used by both renderers thereafter. Diagnostic codes are allocated once: `JSC001`–`JSC004` in the foundation plan, `OAS001` in Task 3, `OAS002` in Task 4.

**Known adaptation points.** Fixture names in `morphir-projection::testing` (Tasks 3 and 4), the exact helper names in `$RUST/tests/ci/` (Tasks 7 and 8), and the CLI end-to-end fixture names from the foundation plan (Task 6). Each of those steps says to read the existing file first and match it. Task 7 Step 6 and Task 9 depend on Java 11+, `wasm-tools`, and `gh` being available; if any is missing, report it rather than skipping the step.
