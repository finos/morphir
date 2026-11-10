//! Data integrity of the fixed F# readiness workflow case.
//!
//! This test reads committed files only. It compiles nothing, generates
//! nothing and records no expectation; the conformance runner in
//! finos/morphir-dotnet executes the case through its adapters.

use morphir_toolchain_contract::{
    DeliveryKind, LockedDelivery, Operation, Protocol, Sha256, TargetPath, read_receipt,
    read_recipe,
};
use serde_json::{Value, json};
use std::path::{Path, PathBuf};

const CASE_DIR: &str = "spec/toolchain/workflows/fsharp-compile-generate";

fn root() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../..")
}

fn read(path: &Path) -> Vec<u8> {
    std::fs::read(path).unwrap_or_else(|error| panic!("failed to read {}: {error}", path.display()))
}

fn json(path: &Path) -> Value {
    serde_json::from_slice(&read(path))
        .unwrap_or_else(|error| panic!("{} is not JSON: {error}", path.display()))
}

fn case() -> Value {
    json(&root().join(CASE_DIR).join("case.json"))
}

fn step<'a>(case: &'a Value, id: &str) -> &'a Value {
    case["steps"]
        .as_array()
        .unwrap()
        .iter()
        .find(|step| step["id"] == id)
        .unwrap_or_else(|| panic!("the case has no step {id}"))
}

/// A case file named relative to the case directory: portable, inside the
/// case, and with the stated digest.
fn checked_file(relative: &str, digest: &Value) -> Vec<u8> {
    TargetPath::parse(relative).unwrap_or_else(|message| panic!("{message}"));
    let bytes = read(&root().join(CASE_DIR).join(relative));
    assert_eq!(
        Sha256::of_bytes(&bytes).to_string(),
        digest.as_str().unwrap(),
        "{relative} has its stated SHA-256"
    );
    bytes
}

#[test]
fn the_case_follows_its_schema() {
    let schema = json(
        &root().join("website/static/schemas/toolchain-workflow-case-0.1.0-draft.1.schema.json"),
    );
    let validator = jsonschema::validator_for(&schema).expect("schema compiles");
    let case = case();
    let errors = validator
        .iter_errors(&case)
        .map(|error| format!("{error} at {}", error.instance_path))
        .collect::<Vec<_>>();
    assert!(errors.is_empty(), "{errors:?}");
}

#[test]
fn every_listed_file_exists_with_its_digest() {
    let case = case();
    for source in case["sources"].as_array().unwrap() {
        let bytes = checked_file(source["file"].as_str().unwrap(), &source["sha256"]);
        std::str::from_utf8(&bytes).expect("sources are UTF-8");
        TargetPath::parse(source["uri"].as_str().unwrap()).unwrap();
    }
    let ir = &step(&case, "compile")["expected"]["ir"];
    checked_file(ir["file"].as_str().unwrap(), &ir["sha256"]);
    for step in case["steps"].as_array().unwrap() {
        for set in step["expected"]["sets"].as_array().into_iter().flatten() {
            for file in set["files"].as_array().unwrap() {
                checked_file(file["file"].as_str().unwrap(), &file["sha256"]);
            }
        }
    }
}

#[test]
fn the_expected_ir_is_well_formed_for_its_declared_version() {
    let case = case();
    let compile = step(&case, "compile");
    let ir_entry = &compile["expected"]["ir"];
    let ir = json(
        &root()
            .join(CASE_DIR)
            .join(ir_entry["file"].as_str().unwrap()),
    );
    assert_eq!(ir["formatVersion"], ir_entry["formatVersion"]);
    // IR 4.0.0 is written with the canonical integer formatVersion 4.
    let tuple_version =
        semver::Version::parse(compile["modelTuple"]["irVersion"].as_str().unwrap()).unwrap();
    assert_eq!(ir["formatVersion"], json!(tuple_version.major));
    assert_eq!(ir["formatVersion"], 4, "the IR v4 shape is checked here");
    // The IR v4 schema itself is applied by `mise run examples:validate` in the
    // docs job, which runs for schema changes and for changes to this case.
    // Here: an IR v4 library distribution of this package and its modules.
    let distribution = ir["distribution"].as_object().expect("a distribution");
    assert_eq!(
        distribution.keys().collect::<Vec<_>>(),
        ["Library"],
        "a library distribution"
    );
    let library = &distribution["Library"];
    assert_eq!(library["packageName"], case["package"]["name"]);
    assert!(library["dependencies"].is_object());
    let modules = library["def"]["modules"].as_object().expect("a module map");
    // The exposed modules here are single words, whose IR v4 module names are
    // their lowercase spelling.
    let exposed = case["package"]["exposedModules"]
        .as_array()
        .unwrap()
        .iter()
        .map(|module| module.as_str().unwrap().to_lowercase())
        .collect::<Vec<_>>();
    assert_eq!(modules.keys().cloned().collect::<Vec<_>>(), exposed);
    // The provenance names the corpus variant the case reuses.
    let provenance = &ir_entry["provenance"];
    assert_eq!(provenance["commit"], case["basis"]["commit"]);
    assert_eq!(case["basis"]["variant"]["input"], compile["input"]);
    assert_eq!(
        case["basis"]["variant"]["version"],
        tuple_version.major.to_string()
    );
}

#[test]
fn pending_generation_steps_record_no_expected_files() {
    let case = case();
    for id in ["generate-built-in", "generate-external"] {
        let expected = &step(&case, id)["expected"];
        assert_eq!(expected["status"], "pending", "{id}");
        assert!(expected["sets"].as_array().unwrap().is_empty(), "{id}");
        assert!(!expected["reason"].as_str().unwrap().trim().is_empty());
    }
}

fn tuple_json(protocol: &Protocol) -> Value {
    match protocol {
        Protocol::ModelTransport(tuple) => json!({
            "operation": tuple.operation().model_method(),
            "profile": tuple.profile().as_str(),
            "codec": tuple.codec().as_str(),
            "envelopeVersion": tuple.envelope_version().to_string(),
            "irVersion": tuple.ir_version().to_string()
        }),
        Protocol::Legacy(_) => panic!("the F# recipe uses MEP 0.2.0-draft.1"),
    }
}

#[test]
fn the_tuples_agree_with_the_signed_fsharp_recipe() {
    let repository =
        json(&root().join("docs/spec/toolchain/fixtures/0.1.0-draft.1/signed/repository.json"));
    let recipe = read_recipe(
        repository["targetFiles"]["toolchains/recipes/fsharp/1.0.0.json"]
            .as_str()
            .unwrap()
            .as_bytes(),
    )
    .unwrap();
    let case = case();
    assert_eq!(recipe.preset().as_str(), case["preset"]);

    let compile = step(&case, "compile");
    let frontend = recipe
        .providers()
        .iter()
        .find(|provider| {
            matches!(provider.operation(), Operation::Compile { language } if language.as_str() == compile["language"])
                && provider.delivery().kind() == DeliveryKind::Process
        })
        .expect("the recipe binds a process frontend");
    assert_eq!(
        frontend.delivery().protocol().version().as_str(),
        compile["protocolVersion"]
    );
    assert_eq!(
        tuple_json(frontend.delivery().protocol()),
        compile["modelTuple"]
    );

    let built_in_step = step(&case, "generate-built-in");
    for host in recipe.hosts() {
        let built_in = host
            .built_ins()
            .iter()
            .find(|built_in| matches!(built_in.operation(), Operation::Generate { target } if target.as_str() == built_in_step["target"]))
            .expect("every offering keeps the built-in F# generator");
        assert_eq!(
            built_in.extension_id().as_str(),
            built_in_step["provider"]["extensionId"]
        );
        let input = built_in.model_input();
        assert_eq!(
            json!({ "profile": input.profile.as_str(), "codec": input.codec.as_str(), "irVersion": input.ir_version.to_string() }),
            built_in_step["modelInput"]
        );
    }

    let external_step = step(&case, "generate-external");
    let backend = recipe
        .providers()
        .iter()
        .find(|provider| {
            matches!(provider.operation(), Operation::Generate { target } if target.as_str() == external_step["target"])
                && provider.delivery().kind().as_str() == external_step["provider"]["delivery"]
        })
        .expect("the recipe binds an external process backend");
    assert_eq!(
        backend.delivery().protocol().version().as_str(),
        external_step["protocolVersion"]
    );
    assert_eq!(
        tuple_json(backend.delivery().protocol()),
        external_step["modelTuple"]
    );
}

#[test]
fn receipts_name_this_workflow() {
    let receipt = read_receipt(&read(
        &root().join("docs/spec/toolchain/fixtures/0.1.0-draft.1/receipt/win-x64-qualified.json"),
    ))
    .unwrap();
    let workflow = receipt.checks()[0].workflow().unwrap();
    assert_eq!(workflow.as_str(), case()["workflow"]);
    // The qualified receipt's generate provider is the built-in this case selects.
    assert!(receipt.providers().iter().any(|provider| matches!(
        provider.identity().delivery(),
        LockedDelivery::BuiltIn { .. }
    )
        && provider.identity().extension_id().as_str() == "morphir.fsharp"));
}
