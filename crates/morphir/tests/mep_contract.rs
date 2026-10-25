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
        (
            "initialize-params",
            &["protocol-versions", "host", "model-transport"],
        ),
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
            "compile-model",
            "generate",
            "generate-model",
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

#[test]
fn model_operations_have_explicit_carriers_and_scoped_evidence() {
    let ir = compile_contract();
    assert_records(
        &ir,
        &[
            (
                "model-transport-tuple",
                &[
                    "operation",
                    "profile",
                    "codec",
                    "envelope-version",
                    "ir-version",
                ],
            ),
            (
                "model-transport-limits",
                &[
                    "max-encoded-bytes",
                    "max-decoded-bytes",
                    "max-depth",
                    "max-nodes",
                ],
            ),
            (
                "model-transport-support",
                &["tuples", "limits", "guarantees"],
            ),
            (
                "model-payload",
                &[
                    "codec",
                    "layout",
                    "decoded-byte-length",
                    "sha256",
                    "content",
                ],
            ),
            (
                "morphir-model",
                &[
                    "envelope-version",
                    "model-id",
                    "revision",
                    "ir-version",
                    "profile",
                    "payload",
                    "evidence",
                    "critical",
                ],
            ),
            ("model-guarantee-requirement", &["guarantee", "scope"]),
            (
                "model-guarantee-evidence",
                &[
                    "guarantee",
                    "model-id",
                    "model-revision",
                    "context-digest",
                    "scope",
                    "producer",
                    "evidence",
                ],
            ),
            ("compile-model-dependency", &["package-name", "model"]),
            (
                "compile-model-request",
                &[
                    "language-id",
                    "sources",
                    "package",
                    "dependencies",
                    "options",
                    "context-digest",
                    "output",
                ],
            ),
            (
                "generate-model-request",
                &[
                    "model",
                    "input",
                    "target",
                    "context-digest",
                    "required-guarantees",
                    "options",
                ],
            ),
        ],
    );
    assert_eq!(
        constructor_names(&ir, "model-operation"),
        ["compile-model-operation", "generate-model-operation"]
    );
    assert_eq!(
        constructor_names(&ir, "model-codec"),
        ["ion-binary-codec", "morphir-json-codec"]
    );
    assert_eq!(
        constructor_names(&ir, "model-layout"),
        ["single-document-model"]
    );
    assert_eq!(
        constructor_names(&ir, "compile-model-result"),
        ["model-compiled", "model-compilation-failed"]
    );
    // Negotiation remains optional; successful compilation has a required model
    // and the failure constructor cannot carry a partial or null model.
    let types = mep_types(&ir);
    for name in ["initialize-params", "extension-capabilities"] {
        let fields = unwrap_access(&types[name])["CustomTypeDefinition"]["constructors"][name]
            .as_array()
            .unwrap();
        let field = fields
            .iter()
            .find(|field| field[0] == "model-transport")
            .unwrap();
        assert_eq!(field[1]["Reference"]["fqname"], "morphir/SDK:maybe#maybe");
        assert_eq!(
            field[1]["Reference"]["args"][0]["Reference"]["fqname"],
            "morphir/mep:mep#model-transport-support"
        );
    }
    let constructors =
        &unwrap_access(&types["compile-model-result"])["CustomTypeDefinition"]["constructors"];
    let success = constructors["model-compiled"].as_array().unwrap();
    assert_eq!(success[0][0], "model");
    assert_eq!(
        success[0][1]["Reference"]["fqname"],
        "morphir/mep:mep#morphir-model"
    );
    let failure = constructors["model-compilation-failed"].as_array().unwrap();
    assert_eq!(failure.len(), 1);
    assert_eq!(failure[0][0], "diagnostics");
    // The existing IR Distribution sum owns Library/Specs/Application. The
    // carrier must not invent a second outer structural-state enum.
    assert!(!type_names(&ir).contains("model-stage"));
    assert!(!type_names(&ir).contains("model-distribution-kind"));
}

#[test]
fn model_draft_adopts_semver_without_relabeling_the_legacy_protocol() {
    let manifest: toml::Value =
        toml::from_str(&fs::read_to_string(contract_dir().join("gleam.toml")).unwrap()).unwrap();
    let version = semver::Version::parse(manifest["version"].as_str().unwrap()).unwrap();
    assert_eq!(version.to_string(), "0.2.0-draft.1");
    let readme = fs::read_to_string(contract_dir().parent().unwrap().join("README.md")).unwrap();
    assert!(readme.contains("0.2.0-draft.1"));
    assert!(readme.contains("0.1.0-draft.1"));
    assert!(readme.contains("legacy `0.1`"));
    assert!(!readme.contains("Published contracts carry no prerelease tags"));
}

#[test]
fn model_reference_corpus_binds_real_payload_assets() {
    use base64::Engine as _;
    use sha2::{Digest, Sha256};
    let root = contract_dir().parent().unwrap().join("mck");
    let corpus: Value =
        serde_json::from_slice(&fs::read(root.join("model-transport.cases.json")).unwrap())
            .unwrap();
    assert_eq!(corpus["status"], "reference");
    assert_eq!(corpus["contractVersion"], "0.1.0-draft.1");
    assert_eq!(corpus["mepVersion"], "0.2.0-draft.1");
    let mut paths = BTreeSet::new();
    for asset in corpus["assets"].as_array().unwrap() {
        let path = asset["path"].as_str().unwrap();
        assert!(paths.insert(path));
        assert!(
            !Path::new(path).is_absolute()
                && !Path::new(path)
                    .components()
                    .any(|part| matches!(part, std::path::Component::ParentDir))
        );
        let bytes = fs::read(root.join(path)).unwrap();
        assert_eq!(
            asset["decodedByteLength"].as_u64().unwrap(),
            bytes.len() as u64
        );
        let hash: String = Sha256::digest(&bytes)
            .iter()
            .map(|byte| format!("{byte:02x}"))
            .collect();
        assert_eq!(asset["sha256"], hash);
        assert_eq!(
            base64::engine::general_purpose::STANDARD
                .decode(asset["content"].as_str().unwrap())
                .unwrap(),
            bytes
        );
        if path.ends_with(".ionb") {
            assert!(bytes.starts_with(&[0xe0, 1, 0, 0xea]));
        }
    }
    assert!(!paths.is_empty());
    let cases = corpus["cases"].as_array().unwrap();
    let mut ids = BTreeSet::new();
    let mut accepted = 0;
    let mut rejected = 0;
    for case in cases {
        assert!(ids.insert(case["id"].as_str().unwrap()));
        assert!(!case["description"].as_str().unwrap().is_empty());
        match case["expected"]["admission"].as_str().unwrap() {
            "accept" => accepted += 1,
            "reject" => {
                rejected += 1;
                assert!(!case["expected"]["code"].as_str().unwrap().is_empty());
            }
            value => panic!("unknown reference admission {value}"),
        }
    }
    // Inventory pins the intended boundaries, not a second admission runner.
    let kinds: BTreeSet<_> = cases
        .iter()
        .map(|case| case["kind"].as_str().unwrap())
        .collect();
    assert_eq!(
        kinds,
        BTreeSet::from([
            "compatibility",
            "evidence",
            "integrity",
            "limits",
            "negotiation",
            "outcome",
            "preservation"
        ])
    );
    assert_eq!(ids.len(), 35);
    let case = |id: &str| cases.iter().find(|case| case["id"] == id).unwrap();
    assert_eq!(
        case("model-0026")["request"]["method"],
        "morphir.backend.generate"
    );
    assert!(case("model-0026")["request"]["params"].get("ir").is_some());
    assert_eq!(case("model-0026")["expected"]["admission"], "accept");
    assert_eq!(
        case("model-0033")["request"]["params"]["model"]["critical"][0],
        "payload.futureMember"
    );
    assert_eq!(
        case("model-0033")["expected"]["code"],
        "unknown_critical_path"
    );
    let aggregate = case("model-0035");
    let model = &aggregate["request"]["params"]["model"];
    let model_bytes = model["payload"]["decodedByteLength"].as_u64().unwrap();
    let evidence_bytes = model["evidence"][0]["evidence"]["decodedByteLength"]
        .as_u64()
        .unwrap();
    let bound = aggregate["hostOffer"]["modelTransport"]["limits"]["maxDecodedBytes"]
        .as_u64()
        .unwrap();
    assert!(
        model_bytes <= bound && evidence_bytes <= bound && model_bytes + evidence_bytes > bound
    );
    assert!(accepted >= 3 && rejected >= 10);
    // This checks fixed corpus integrity. Host/guest behavior is deliberately
    // not inferred from fixture labels; executable MCK admission is #965.
}

/// Fixture integrity alone cannot establish that a positive model contains a
/// supported IR document. Exercise the existing codec, not another MEP runner.
#[test]
fn positive_model_json_matches_the_existing_ir_contract() {
    use base64::Engine as _;
    use morphir_core::format_version::{
        Compatibility, NormalizedFormatVersion, ScalarValue, SupportTable,
    };
    use morphir_core::ir::json::read_ir_file;

    let root = contract_dir().parent().unwrap().join("mck");
    let plain = fs::read_to_string(root.join("fixtures/plain-ir.json")).unwrap();
    let supported_ir = |text: &str| {
        read_ir_file(text).expect("positive model must decode through the existing IR reader");
        let document: Value = serde_json::from_str(text).unwrap();
        let scalar = ScalarValue::from_json(&document["formatVersion"]).unwrap();
        let normalized =
            NormalizedFormatVersion::from_scalar(&scalar, &SupportTable::reference()).unwrap();
        assert!(
            normalized.is_supported(),
            "positive model is outside the reference IR support table"
        );
        normalized.release
    };
    supported_ir(&plain);
    let corpus: Value =
        serde_json::from_slice(&fs::read(root.join("model-transport.cases.json")).unwrap())
            .unwrap();
    let mut checked = 0;
    for case in corpus["cases"].as_array().unwrap() {
        if case["expected"]["admission"] != "accept" {
            continue;
        }
        let model = &case["request"]["params"]["model"];
        if model["payload"]["codec"] != "morphir-json" {
            continue;
        }
        let bytes = base64::engine::general_purpose::STANDARD
            .decode(model["payload"]["content"].as_str().unwrap())
            .unwrap();
        let text = String::from_utf8(bytes).unwrap();
        let release = supported_ir(&text);
        assert_eq!(model["irVersion"], release.to_string());
        assert_eq!(
            case["request"]["params"]["input"]["irVersion"],
            model["irVersion"]
        );
        checked += 1;
    }
    assert!(checked > 0, "keep an accepted explicit JSON model example");

    // IR 4.0.0 remains draft work. Its existing wire contract still rejects an
    // unminted minor; the MEP envelope must not silently invent one.
    let scalar = ScalarValue::from_json(&Value::String("4.1.0".into())).unwrap();
    let unsupported =
        NormalizedFormatVersion::from_scalar(&scalar, &SupportTable::reference()).unwrap();
    assert_eq!(unsupported.compatibility, Compatibility::UnsupportedMinor);
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
                "model-transport",
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
            // `data` comes from the protocol draft; the Rust SDK does not
            // carry it yet (morphir-xo35).
            "diagnostic",
            &["severity", "code", "message", "location", "related", "data"],
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
/// written) says so in its doc comment, and so does every type with an
/// integer field whose domain is narrower than Gleam's `Int`, naming the SDK
/// width. Each phrase names the rule.
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
        (
            "RequestId",
            &[
                "the number or the string itself",
                "non-negative; u64 in the SDK",
            ],
        ),
        ("ProgressKind", &["Wire values"]),
        ("ProgressParams", &["left out when absent", "0 through 100"]),
        (
            "RpcError",
            &["left out of the message when absent", "i32 in the SDK"],
        ),
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
        ("SourceDocument", &["non-negative; u64 in the SDK"]),
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
        // Rich model wire mappings are explicit rather than inferred tags.
        ("InitializeParams", &["modelTransport", "left out"]),
        (
            "ModelOperation",
            &["Wire values", "0.2.0-draft.1", "legacy `0.1`"],
        ),
        (
            "ModelCodec",
            &["Wire values", "application/ion", "application/json"],
        ),
        (
            "ModelLayout",
            &["single-document", "external symbol tables"],
        ),
        (
            "ModelTransportSupport",
            &["read as empty", "not guarantees"],
        ),
        (
            "ModelTransportLimits",
            &["2147483647", "summed across", "Depth"],
        ),
        (
            "ModelPayload",
            &["BOTH codecs", "2147483647", "64 lowercase", "ordered"],
        ),
        (
            "MorphirModel",
            &[
                "read as empty",
                "critical child",
                "logical immutable revision",
            ],
        ),
        (
            "ModelGuaranteeEvidence",
            &[
                "checking/trust policy",
                "exact scope",
                "never authentication",
            ],
        ),
        (
            "CompileModelRequest",
            &["read as empty", "options.irVersion"],
        ),
        (
            "CompileModelResult",
            &["REQUIRED", "even null", "read as empty"],
        ),
        ("GenerateModelRequest", &["read as empty", "required scope"]),
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
        (
            "SourcePosition",
            &["zero-based", "UTF-16", "non-negative; u32 in the SDK"],
        ),
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
