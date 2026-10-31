//! A conformance fixture guest for the Morphir CLI worker host.
//!
//! It is built with `morphir-extension-sdk` for `wasm32-wasip1`, so it imports
//! WASI preview 1 through the Rust standard library and the Morphir host
//! functions through the SDK. It is not a published extension. Its frontend
//! claims a language that no host knows, `morphir-fixture-flags` with files
//! `.flags`, so that a host that runs it shows that it holds no list of
//! languages or extensions.
//!
//! A `.flags` document holds Boolean constants, one per line:
//!
//! ```text
//! # comment
//! ready = true
//! blocked = false
//! ```
//!
//! Compile gives one Morphir IR 3 module per document, with one Boolean
//! constant per line. Generate turns that IR back into `.flags` documents, so
//! generated output compiles back to the same IR.
//!
//! Each compile also uses the host: it reads the workspace information, writes
//! and reads the session IR cache, logs through the Extism kernel and through
//! `morphir_log`, and calls WASI (clock, random seed, arguments, environment,
//! stderr). It reports what it saw as one `fixture.host` info diagnostic.

use morphir_extension_sdk::prelude::*;
use morphir_extension_sdk::{
    Artifact, BackendCapability, CompileRequest, CompileResult, Diagnostic, DiagnosticSeverity,
    FrontendCapability, GenerateRequest, GenerateResult, LanguageCapability, export_extension,
};
use serde_json::{Value, json};

/// The language that this fixture compiles. No host has code for it.
const LANGUAGE: &str = "morphir-fixture-flags";
const FILE_EXTENSION: &str = ".flags";
const TARGET: &str = "morphir-fixture-flags";

#[derive(Default)]
pub struct FixtureGuest;

impl Extension for FixtureGuest {
    fn info() -> ExtensionInfo {
        ExtensionInfo {
            id: "morphir-sdk-fixture".into(),
            name: "Morphir SDK conformance fixture".into(),
            version: "0.1.0".into(),
            description: Some(
                "Worker host conformance fixture built with morphir-extension-sdk".into(),
            ),
            types: vec![],
            author: None,
            homepage: None,
            license: Some("Apache-2.0".into()),
            min_sdk_version: None,
        }
    }

    fn capabilities() -> ExtensionCapabilities {
        ExtensionCapabilities {
            frontend: Some(FrontendCapability {
                languages: vec![LanguageCapability {
                    id: LANGUAGE.into(),
                    file_extensions: vec![FILE_EXTENSION.into()],
                }],
                ir_versions: vec!["3".into()],
                compile: true,
                incremental: false,
                fragments: false,
                multi_document: true,
            }),
            backend: Some(BackendCapability {
                targets: vec![TARGET.into()],
                ir_versions: vec!["3".into()],
                generate: true,
            }),
            ..Default::default()
        }
    }
}

impl Frontend for FixtureGuest {
    fn compile(&self, request: CompileRequest) -> morphir_extension_sdk::Result<CompileResult> {
        let mut diagnostics = vec![host_report()];
        if request.language_id != LANGUAGE {
            diagnostics.push(error(
                "fixture.language",
                format!("this fixture compiles {LANGUAGE}, not {}", request.language_id),
            ));
            return Ok(failed(diagnostics));
        }
        if request.options.ir_version != "3" && request.options.ir_version != "3.0.0" {
            diagnostics.push(error(
                "fixture.ir_version",
                format!("this fixture writes IR 3, not {}", request.options.ir_version),
            ));
            return Ok(failed(diagnostics));
        }
        let mut documents: Vec<_> = request.sources.documents.iter().collect();
        documents.sort_by(|left, right| left.uri.cmp(&right.uri));
        let mut modules = Vec::new();
        for document in documents {
            match module(&document.uri, &document.text) {
                Ok(module) => modules.push(module),
                Err(message) => diagnostics.push(error("fixture.syntax", message)),
            }
        }
        if diagnostics.len() > 1 {
            return Ok(failed(diagnostics));
        }
        let ir = json!({
            "formatVersion": 3,
            "distribution": ["Library", path(&request.package.name), [], {"modules": modules}],
        });
        Ok(CompileResult {
            success: true,
            ir_version: Some("3".into()),
            ir: Some(ir),
            diagnostics,
            modules: vec![],
            module_results: vec![],
            context_digest: None,
        })
    }

    fn supported_languages() -> Vec<String> {
        vec![LANGUAGE.into()]
    }

    fn file_extensions() -> Vec<String> {
        vec![FILE_EXTENSION.into()]
    }
}

impl Backend for FixtureGuest {
    fn generate(&self, request: GenerateRequest) -> morphir_extension_sdk::Result<GenerateResult> {
        match artifacts(&request.ir) {
            Ok(artifacts) => Ok(GenerateResult {
                success: true,
                artifacts,
                diagnostics: vec![],
            }),
            Err(message) => Ok(GenerateResult {
                success: false,
                artifacts: vec![],
                diagnostics: vec![error("fixture.unsupported_ir", message)],
            }),
        }
    }

    fn target_languages() -> Vec<String> {
        vec![TARGET.into()]
    }
}

export_extension!(FixtureGuest, frontend, backend);

/// The Boolean type reference of the Morphir SDK, in IR 3 JSON.
fn bool_type() -> Value {
    json!(["Reference", {}, [[["morphir"], ["s", "d", "k"]], [["basics"]], ["bool"]], []])
}

/// A Morphir name: lower-case words, split at `_`, `-`, `.` and capitals.
fn name(text: &str) -> Value {
    let mut words: Vec<String> = Vec::new();
    let mut word = String::new();
    for character in text.chars() {
        if character == '_' || character == '-' || character == '.' {
            if !word.is_empty() {
                words.push(std::mem::take(&mut word));
            }
        } else if character.is_uppercase() {
            if !word.is_empty() {
                words.push(std::mem::take(&mut word));
            }
            word.extend(character.to_lowercase());
        } else {
            word.push(character);
        }
    }
    if !word.is_empty() {
        words.push(word);
    }
    json!(words)
}

/// A Morphir path from a `/`-separated package name.
fn path(text: &str) -> Value {
    Value::Array(text.split('/').filter(|part| !part.is_empty()).map(name).collect())
}

/// The module name of a document: its file name without `.flags`.
fn module_name(uri: &str) -> std::result::Result<String, String> {
    let file = uri.rsplit('/').next().unwrap_or(uri);
    match file.strip_suffix(FILE_EXTENSION) {
        Some(stem) if !stem.is_empty() => Ok(stem.to_string()),
        _ => Err(format!("{uri}: a document name must end with {FILE_EXTENSION}")),
    }
}

fn module(uri: &str, text: &str) -> std::result::Result<Value, String> {
    let module = module_name(uri)?;
    let mut values = Vec::new();
    for (index, line) in text.lines().enumerate() {
        let line = line.trim();
        if line.is_empty() || line.starts_with('#') {
            continue;
        }
        let parse = || -> Option<(&str, bool)> {
            let (key, value) = line.split_once('=')?;
            let key = key.trim();
            let valid = !key.is_empty()
                && key.chars().next()?.is_ascii_lowercase()
                && key.chars().all(|c| c.is_ascii_alphanumeric() || c == '_');
            let value = match value.trim() {
                "true" => true,
                "false" => false,
                _ => return None,
            };
            valid.then_some((key, value))
        };
        let Some((key, value)) = parse() else {
            return Err(format!(
                "{uri}:{}: expected `name = true` or `name = false`",
                index + 1
            ));
        };
        values.push(json!([name(key), {"access": "Public", "value": {"doc": "", "value": {
            "inputTypes": [],
            "outputType": bool_type(),
            "body": ["Literal", bool_type(), ["BoolLiteral", value]],
        }}}]));
    }
    Ok(json!([[name(&module)], {"access": "Public", "value": {
        "types": [], "values": values, "doc": null,
    }}]))
}

/// Joins the words of a Morphir name with `_`, the form that compiles back
/// to the same name.
fn words(value: &Value) -> Option<String> {
    let words: Option<Vec<&str>> = value.as_array()?.iter().map(Value::as_str).collect();
    Some(words?.join("_"))
}

fn artifacts(ir: &Value) -> std::result::Result<Vec<Artifact>, String> {
    let unsupported = || "expected a Morphir IR 3 Library of Boolean constants".to_string();
    if ir["formatVersion"] != json!(3) || ir["distribution"][0] != json!("Library") {
        return Err(unsupported());
    }
    let modules = ir["distribution"][3]["modules"].as_array().ok_or_else(unsupported)?;
    let mut artifacts = Vec::new();
    for module in modules {
        let module_path = module[0].as_array().ok_or_else(unsupported)?;
        let file: Option<Vec<String>> = module_path.iter().map(words).collect();
        let file = file.ok_or_else(unsupported)?.join("/");
        let mut content = String::new();
        for value in module[1]["value"]["values"].as_array().ok_or_else(unsupported)? {
            let key = words(&value[0]).ok_or_else(unsupported)?;
            let body = &value[1]["value"]["value"]["body"];
            let literal = body[2][1].as_bool().filter(|_| body[0] == json!("Literal"));
            let literal = literal.ok_or_else(unsupported)?;
            content.push_str(&format!("{key} = {literal}\n"));
        }
        artifacts.push(Artifact {
            path: format!("{file}{FILE_EXTENSION}"),
            content,
            binary: false,
        });
    }
    Ok(artifacts)
}

fn error(code: &str, message: String) -> Diagnostic {
    Diagnostic {
        severity: DiagnosticSeverity::Error,
        code: Some(code.into()),
        message,
        location: None,
        related: vec![],
    }
}

fn failed(diagnostics: Vec<Diagnostic>) -> CompileResult {
    CompileResult {
        success: false,
        ir_version: None,
        ir: None,
        diagnostics,
        modules: vec![],
        module_results: vec![],
        context_digest: None,
    }
}

/// Uses the host functions and WASI, and reports what the host answered.
fn host_report() -> Diagnostic {
    let report = observe_host();
    Diagnostic {
        severity: DiagnosticSeverity::Info,
        code: Some("fixture.host".into()),
        message: report.to_string(),
        location: None,
        related: vec![],
    }
}

#[cfg(target_arch = "wasm32")]
fn observe_host() -> Value {
    use morphir_extension_sdk::host;
    let workspace = host::get_workspace_info();
    let key = "fixture/cache-probe";
    let probe = json!({"probe": [1, 2, 3]});
    host::cache_ir(key, &probe);
    let cached = host::get_cached_ir(key);
    host::log("info", "fixture guest: Extism kernel log");
    let logged = log::send("info", "fixture guest: morphir_log");
    // WASI preview 1: clock_time_get, random_get (the map's seed),
    // args_sizes_get, environ_sizes_get and fd_write on stderr.
    let clock = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .is_ok();
    let mut seeded = std::collections::HashMap::new();
    seeded.insert("seed", 1);
    let arguments = std::env::args().count();
    let environment = std::env::vars().count();
    eprintln!("fixture guest: WASI stderr");
    json!({
        "workspaceRoot": workspace.as_ref().is_some_and(|info| !info.root.is_empty()),
        "cacheRoundTrip": cached == Some(probe),
        "morphirLog": logged,
        "wasiClock": clock,
        "wasiRandomSeed": seeded.len() == 1,
        "wasiArguments": arguments,
        "wasiEnvironment": environment,
    })
}

#[cfg(not(target_arch = "wasm32"))]
fn observe_host() -> Value {
    json!({"native": true})
}

/// `morphir_log`, the fourth Morphir host function. The SDK at the pinned
/// revision does not declare it, so the fixture declares it as a guest would.
#[cfg(target_arch = "wasm32")]
mod log {
    use morphir_extension_sdk::extism_pdk::{self, *};

    #[host_fn]
    extern "ExtismHost" {
        fn morphir_log(level: String, message: String);
    }

    pub fn send(level: &str, message: &str) -> bool {
        unsafe { morphir_log(level.to_string(), message.to_string()).is_ok() }
    }
}
