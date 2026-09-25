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

/// Compile a copy of the contract in a temporary directory, so the test never
/// writes into the repository and ignores the user's Morphir config.
fn compile_contract() -> Value {
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
    serde_json::from_slice(
        &fs::read(&ir).unwrap_or_else(|error| panic!("{}: {error}", ir.display())),
    )
    .unwrap()
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
    for (type_name, labels) in records {
        assert_eq!(
            field_labels(&ir, type_name),
            *labels,
            "fields of {type_name}"
        );
    }
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
