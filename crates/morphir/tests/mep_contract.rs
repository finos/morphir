//! The MEP contract model in spec/mep compiles and covers the protocol.
use serde_json::Value;
use std::{
    collections::BTreeSet,
    fs,
    path::{Path, PathBuf},
    process::Command,
};

fn contract_dir() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../spec/mep/contract")
}

/// Copy a directory tree, leaving out the Morphir and Gleam output folders.
fn copy_dir(from: &Path, to: &Path) {
    fs::create_dir_all(to).unwrap();
    for entry in fs::read_dir(from).unwrap_or_else(|error| panic!("{}: {error}", from.display())) {
        let entry = entry.unwrap();
        let name = entry.file_name();
        if name == ".morphir" || name == "build" {
            continue;
        }
        let target = to.join(&name);
        if entry.file_type().unwrap().is_dir() {
            copy_dir(&entry.path(), &target);
        } else {
            fs::copy(entry.path(), target).unwrap();
        }
    }
}

fn committed_ir() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../spec/mep/generated/mep.ir.json")
}

/// Compile a copy of the contract in a temporary directory, so the test never
/// writes into the repository and ignores the user's Morphir config, and
/// return the IR file exactly as the CLI wrote it.
fn compile_contract_bytes() -> Vec<u8> {
    let work = tempfile::tempdir().unwrap();
    let project = work.path().join("contract");
    copy_dir(&contract_dir(), &project);
    let home = work.path().join("home");
    fs::create_dir_all(&home).unwrap();
    let mut command = Command::new(env!("CARGO_BIN_EXE_morphir"));
    command.current_dir(&project);
    for (key, _) in std::env::vars_os() {
        if key
            .to_string_lossy()
            .get(..8)
            .is_some_and(|prefix| prefix.eq_ignore_ascii_case("MORPHIR_"))
        {
            command.env_remove(key);
        }
    }
    command
        .args([
            "compile",
            "--config",
            "morphir.toml",
            "--ir-version",
            "4",
            "--types-only",
        ])
        .env("MORPHIR_HOME", work.path().join("morphir-home"))
        .env("MORPHIR_LOG_FILE", "false")
        .env("HOME", &home)
        .env("USERPROFILE", &home)
        .env("XDG_CONFIG_HOME", home.join(".config"))
        .env("APPDATA", home.join("AppData/Roaming"))
        .env("LOCALAPPDATA", home.join("AppData/Local"));
    let output = command.output().unwrap();
    assert!(
        output.status.success(),
        "morphir compile failed\nstdout:\n{}\nstderr:\n{}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );
    let ir = project.join(".morphir/out/compile.dest/morphir-ir.json");
    fs::read(&ir).unwrap_or_else(|error| panic!("{}: {error}", ir.display()))
}

/// The compiled contract IR, parsed.
fn compile_contract() -> Value {
    serde_json::from_slice(&compile_contract_bytes()).unwrap()
}

/// The value inside an access wrapper such as `{"Public": ...}`.
fn unwrap_access(value: &Value) -> &Value {
    let object = value.as_object().expect("an access-controlled object");
    assert_eq!(object.len(), 1, "expected one access key, got {value}");
    object.values().next().unwrap()
}

/// The `mep` module's type definitions, keyed by kebab-case type name.
///
/// IR v4 shape: `distribution.Library.def.modules.mep.<access>.types`, where
/// each type is `{<access>: {"doc": ..., "CustomTypeDefinition": ...}}`.
fn mep_types(ir: &Value) -> &serde_json::Map<String, Value> {
    assert_eq!(ir["formatVersion"], 4, "expected IR v4");
    let library = &ir["distribution"]["Library"];
    assert_eq!(library["packageName"], "morphir/mep");
    unwrap_access(&library["def"]["modules"]["mep"])["types"]
        .as_object()
        .expect("module mep has a types map")
}

/// Every type name the `mep` module defines, in kebab-case.
fn type_names(ir: &Value) -> BTreeSet<String> {
    mep_types(ir).keys().cloned().collect()
}

/// The field labels of a record, in declaration order and in kebab-case.
///
/// The Gleam frontend emits a record as a custom type with one constructor
/// that has the type's own name; each argument is a `[label, type]` pair.
fn field_labels(ir: &Value, type_name: &str) -> Vec<String> {
    let definition = mep_types(ir)
        .get(type_name)
        .unwrap_or_else(|| panic!("module mep has no type {type_name}"));
    let constructors = unwrap_access(definition)["CustomTypeDefinition"]["constructors"]
        .as_object()
        .unwrap_or_else(|| panic!("{type_name} is not a custom type: {definition}"));
    let arguments = constructors
        .get(type_name)
        .and_then(Value::as_array)
        .unwrap_or_else(|| panic!("{type_name} has no record constructor: {constructors:?}"));
    arguments
        .iter()
        .map(|argument| {
            argument[0]
                .as_str()
                .unwrap_or_else(|| panic!("{type_name} has an unlabelled argument: {argument}"))
                .to_owned()
        })
        .collect()
}

const HANDSHAKE_TYPES: &[&str] = &[
    "json",
    "peer-kind",
    "peer-info",
    "describe-params",
    "initialize-params",
    "initialize-result",
    "extension-type",
    "extension-info",
    "method",
    "error-code",
    "rpc-error",
];

#[test]
fn the_contract_covers_the_handshake() {
    let ir = compile_contract();
    let names = type_names(&ir);
    for expected in HANDSHAKE_TYPES {
        assert!(
            names.contains(*expected),
            "mep.gleam is missing {expected}; has {names:?}"
        );
    }
    // Fields follow the SDK struct declaration order.
    let records: &[(&str, &[&str])] = &[
        ("peer-info", &["kind", "name", "version"]),
        ("describe-params", &["protocol-versions"]),
        ("initialize-params", &["protocol-versions", "host"]),
        (
            "initialize-result",
            &["protocol-version", "extension", "capabilities"],
        ),
        (
            "extension-info",
            &[
                "id",
                "name",
                "version",
                "description",
                "types",
                "author",
                "homepage",
                "license",
                "min-sdk-version",
            ],
        ),
        ("rpc-error", &["code", "message", "data"]),
    ];
    assert_records(&ir, records);
}

/// The constructor names of a custom type, in declaration order.
fn constructor_names(ir: &Value, type_name: &str) -> Vec<String> {
    let definition = mep_types(ir)
        .get(type_name)
        .unwrap_or_else(|| panic!("module mep has no type {type_name}"));
    unwrap_access(definition)["CustomTypeDefinition"]["constructors"]
        .as_object()
        .unwrap_or_else(|| panic!("{type_name} is not a custom type: {definition}"))
        .keys()
        .cloned()
        .collect()
}

/// Every method in `protocol.rs` plus the two notifications that the
/// protocol draft (docs/design/draft/extensions/protocol.md) defines and the
/// SDK does not handle yet, and every error code likewise.
#[test]
fn the_contract_covers_every_method_and_error_code() {
    let ir = compile_contract();
    assert_eq!(
        constructor_names(&ir, "method"),
        [
            "initialize",
            "describe",
            "initialized",
            "ping",
            "info",
            "capabilities",
            "compile",
            "generate",
            "validate",
            "transform",
            "workspace-discover",
            "shutdown",
            "exit",
            "cancel-request",
            "progress",
        ]
    );
    assert_eq!(
        constructor_names(&ir, "error-code"),
        [
            "parse-error",
            "invalid-request",
            "method-not-found",
            "invalid-params",
            "internal-error",
            "extension-error",
            "compilation-error",
            "generation-error",
            "validation-error",
            "transformation-error",
            "extension-failure",
            "protocol-version-mismatch",
            "permission-denied",
            "capability-unavailable",
            "not-initialized",
            "request-cancelled",
        ]
    );
    assert_eq!(
        constructor_names(&ir, "request-id"),
        ["numeric-request-id", "string-request-id"]
    );
    assert_eq!(
        constructor_names(&ir, "progress-kind"),
        ["progress-begin", "progress-report", "progress-end"]
    );
    assert_records(
        &ir,
        &[
            ("cancel-params", &["id"]),
            (
                "progress-params",
                &["request-id", "kind", "message", "percentage"],
            ),
        ],
    );
}

/// Check that each record's field labels match the SDK struct, in order.
fn assert_records(ir: &Value, records: &[(&str, &[&str])]) {
    for (type_name, labels) in records {
        assert_eq!(
            field_labels(ir, type_name),
            *labels,
            "fields of {type_name}"
        );
    }
}

const CAPABILITY_TYPES: &[&str] = &[
    "language-capability",
    "frontend-capability",
    "backend-capability",
    "workspace-capability",
    "extension-capabilities",
    "capability-claim-set",
    "claims-requirements",
];

#[test]
fn the_contract_covers_capabilities_and_claims() {
    let ir = compile_contract();
    let names = type_names(&ir);
    for expected in CAPABILITY_TYPES {
        assert!(
            names.contains(*expected),
            "mep.gleam is missing {expected}; has {names:?}"
        );
    }
    // Fields follow the SDK struct declaration order (types.rs and claims/mod.rs).
    let records: &[(&str, &[&str])] = &[
        ("language-capability", &["id", "file-extensions"]),
        (
            "frontend-capability",
            &[
                "languages",
                "ir-versions",
                "compile",
                "incremental",
                "fragments",
                "multi-document",
            ],
        ),
        (
            "backend-capability",
            &["targets", "ir-versions", "generate"],
        ),
        ("workspace-capability", &["protocol-versions", "discover"]),
        (
            "extension-capabilities",
            &[
                "frontend",
                "backend",
                "workspace",
                "streaming",
                "incremental",
                "cancellation",
                "progress",
                "extra",
            ],
        ),
        ("claims-requirements", &["host"]),
        (
            "capability-claim-set",
            &[
                "claims-version",
                "protocol-versions",
                "extension",
                "capabilities",
                "requires",
                "critical",
            ],
        ),
    ];
    assert_records(&ir, records);
}

const COMPILE_TYPES: &[&str] = &[
    "source-document",
    "source-set",
    "compile-package",
    "compile-dependency",
    "compile-options",
    "compile-request",
    "compile-result",
    "baseline-module",
    "compile-baseline",
    "module-status",
    "module-result",
    "diagnostic-severity",
    "source-position",
    "source-range",
    "source-location",
    "related-information",
    "diagnostic",
    "generate-request",
    "generate-result",
    "artifact",
];

#[test]
fn the_contract_covers_compile_diagnostics_and_generate() {
    let ir = compile_contract();
    let names = type_names(&ir);
    for expected in COMPILE_TYPES {
        assert!(
            names.contains(*expected),
            "mep.gleam is missing {expected}; has {names:?}"
        );
    }
    // Fields follow the SDK struct declaration order (types.rs).
    let records: &[(&str, &[&str])] = &[
        (
            "source-document",
            &["uri", "language-id", "version", "text"],
        ),
        ("compile-package", &["name", "exposed-modules"]),
        (
            "compile-dependency",
            &["package-name", "ir-version", "distribution"],
        ),
        ("compile-options", &["types-only", "ir-version", "extra"]),
        ("source-set", &["root", "documents"]),
        (
            "compile-request",
            &[
                "language-id",
                "sources",
                "package",
                "dependencies",
                "options",
                "baseline",
            ],
        ),
        (
            "compile-result",
            &[
                "success",
                "ir-version",
                "ir",
                "diagnostics",
                "modules",
                "module-results",
                "context-digest",
            ],
        ),
        (
            "baseline-module",
            &[
                "name",
                "uri",
                "source-digest",
                "interface-digest",
                "depends-on",
                "ir",
                "frontend-state",
            ],
        ),
        ("compile-baseline", &["modules", "context-digest"]),
        (
            "module-result",
            &[
                "name",
                "uri",
                "status",
                "source-digest",
                "interface-digest",
                "depends-on",
                "ir",
                "frontend-state",
                "diagnostics",
            ],
        ),
        ("generate-request", &["ir", "target", "options"]),
        ("generate-result", &["success", "artifacts", "diagnostics"]),
        (
            "diagnostic",
            &["severity", "code", "message", "location", "related"],
        ),
        ("source-location", &["uri", "range"]),
        ("source-range", &["start", "end"]),
        ("source-position", &["line", "character"]),
        ("related-information", &["location", "message"]),
        ("artifact", &["path", "content", "binary"]),
    ];
    assert_records(&ir, records);
}

/// Gleam prelude constructors, plus `Some` and `None` from `gleam/option`,
/// in the kebab-case form the IR uses.
const RESERVED_CONSTRUCTORS: &[&str] = &["true", "false", "nil", "ok", "error", "some", "none"];

/// The frontend rejects a constructor declared twice, but it accepts one
/// that shadows the prelude, so this test checks that.
#[test]
fn no_constructor_shadows_the_prelude() {
    let ir = compile_contract();
    for (type_name, definition) in mep_types(&ir) {
        let constructors = unwrap_access(definition)["CustomTypeDefinition"]["constructors"]
            .as_object()
            .into_iter()
            .flat_map(|constructors| constructors.keys());
        for constructor in constructors {
            assert!(
                !RESERVED_CONSTRUCTORS.contains(&constructor.as_str()),
                "{type_name} declares {constructor}, which shadows a prelude constructor"
            );
        }
    }
}

/// The committed IR is byte for byte what the CLI writes for the contract
/// today. The bytes are compared as written, not re-serialized.
#[test]
fn the_committed_ir_matches_a_fresh_compile() {
    let fresh = compile_contract_bytes();
    let committed = fs::read(committed_ir()).unwrap();
    if fresh != committed {
        let first_difference = fresh
            .iter()
            .zip(&committed)
            .position(|(a, b)| a != b)
            .unwrap_or(fresh.len().min(committed.len()));
        panic!(
            "spec/mep/generated/mep.ir.json is out of date (first difference at byte {first_difference}; \
             fresh {} bytes, committed {} bytes); run `mise run spec:mep` and commit it",
            fresh.len(),
            committed.len()
        );
    }
}

/// The `///` lines directly above `declaration`, without the markers, joined
/// into one line so a phrase can span a line break.
fn doc_comment_before(source: &str, declaration: &str) -> String {
    let lines: Vec<&str> = source.lines().collect();
    let index = lines
        .iter()
        .position(|line| {
            line.starts_with(declaration)
                && !line[declaration.len()..].starts_with(|c: char| c.is_alphanumeric())
        })
        .unwrap_or_else(|| panic!("mep.gleam has no `{declaration}`"));
    let mut doc: Vec<&str> = lines[..index]
        .iter()
        .rev()
        .take_while(|line| line.starts_with("///") && !line.starts_with("////"))
        .map(|line| line.trim_start_matches("///").trim_start())
        .collect();
    doc.reverse();
    doc.join(" ")
}

/// Every type whose wire form differs from the default rule (snake_case
/// labels become lowerCamelCase members, every member required and always
/// written) says so in its doc comment. Each phrase names the rule.
#[test]
fn every_wire_exception_is_documented() {
    let source = fs::read_to_string(contract_dir().join("src/mep.gleam")).unwrap();
    let rules: &[(&str, &[&str])] = &[
        ("Json", &["the JSON value itself"]),
        // Handshake
        ("PeerKind", &["Wire values", "read as `Unspecified`"]),
        ("PeerInfo", &["absent kind is read as `Unspecified`"]),
        ("ExtensionType", &["Wire values"]),
        (
            "ExtensionInfo",
            &["snake_case", "left out of the message when absent"],
        ),
        (
            "Method",
            &["wire value", "notification", "`$/cancelRequest`"],
        ),
        ("ErrorCode", &["integer code"]),
        // Cancellation and progress
        ("RequestId", &["the number or the string itself"]),
        ("ProgressKind", &["Wire values"]),
        ("ProgressParams", &["left out when absent", "0 through 100"]),
        ("RpcError", &["left out of the message when absent"]),
        // Capabilities and claims
        ("FrontendCapability", &["only when it is true"]),
        ("WorkspaceCapability", &["full SemVer"]),
        (
            "ExtensionCapabilities",
            &["beside the named members", "always written", "refuses"],
        ),
        ("ClaimsRequirements", &["comparator", "left out when empty"]),
        (
            "CapabilityClaimSet",
            &[
                "statementVersion",
                "`MAJOR.MINOR`",
                "`capabilities` is open",
                "names `claimsVersion`",
                "dropped",
                "not checked",
                "left out when empty",
            ],
        ),
        // Compile
        ("CompilePackage", &["absent", "empty list exposes none"]),
        (
            "CompileOptions",
            &[
                "beside the named members",
                "`sourceRootUri`",
                "always written",
            ],
        ),
        ("SourceSet", &["left out when absent"]),
        ("CompileRequest", &["read as empty", "left out when absent"]),
        ("CompileResult", &["left out when empty", "read as empty"]),
        ("BaselineModule", &["read as empty", "left out when absent"]),
        (
            "CompileBaseline",
            &["read as empty", "left out when absent"],
        ),
        ("ModuleStatus", &["Wire values"]),
        ("ModuleResult", &["left out when absent", "read as empty"]),
        // Generate
        ("GenerateRequest", &["read as empty"]),
        ("GenerateResult", &["read as empty"]),
        ("Artifact", &["base64", "read as false"]),
        // Diagnostics
        (
            "Diagnostic",
            &["left out when absent", "left out when empty"],
        ),
        ("DiagnosticSeverity", &["Wire values"]),
        ("SourcePosition", &["zero-based", "UTF-16"]),
    ];
    for (type_name, phrases) in rules {
        let doc = doc_comment_before(&source, &format!("pub type {type_name} "));
        for phrase in *phrases {
            assert!(
                doc.contains(phrase),
                "{type_name}'s doc comment must mention `{phrase}`; it reads:\n{doc}"
            );
        }
    }
}
