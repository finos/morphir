//! Data integrity of the fixed F# readiness workflow case.
//!
//! This test reads committed files only. It compiles nothing, generates
//! nothing and records no expectation; the conformance runner in
//! finos/morphir-dotnet executes the case through its adapters.

use morphir_toolchain_contract::{
    LockedDelivery, Operation, Protocol, Sha256, TargetPath, read_receipt, read_recipe,
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
    let tuple_version = semver::Version::parse(
        case_provider(compile, "process")["modelTuple"]["irVersion"]
            .as_str()
            .unwrap(),
    )
    .unwrap();
    // Every covered provider exchanges the same IR version.
    for provider in compile["providers"].as_array().unwrap() {
        let model = if provider["delivery"] == "built-in" {
            &provider["modelOutput"]
        } else {
            &provider["modelTuple"]
        };
        assert_eq!(model["irVersion"], json!(tuple_version.to_string()));
    }
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
    let expected = &step(&case, "generate")["expected"];
    assert_eq!(expected["status"], "pending");
    assert!(expected["sets"].as_array().unwrap().is_empty());
    assert!(
        expected["reason"]
            .as_str()
            .unwrap()
            .starts_with("Maintainer question M1")
    );
}

/// A step names each delivery it covers once, and frozen sets that name
/// deliveries name disjoint ones. A set without `appliesTo` stands alone.
#[test]
fn each_delivery_has_at_most_one_provider_and_one_set_per_step() {
    let case = case();
    for step in case["steps"].as_array().unwrap() {
        let deliveries = step["providers"]
            .as_array()
            .unwrap()
            .iter()
            .map(|provider| provider["delivery"].as_str().unwrap())
            .collect::<Vec<_>>();
        let unique = deliveries.iter().collect::<std::collections::BTreeSet<_>>();
        assert_eq!(unique.len(), deliveries.len(), "{}", step["id"]);
        let sets = step["expected"]["sets"]
            .as_array()
            .cloned()
            .unwrap_or_default();
        let mut covered = std::collections::BTreeSet::new();
        for set in &sets {
            match set["appliesTo"]["delivery"].as_array() {
                None => assert_eq!(sets.len(), 1, "a set for every delivery stands alone"),
                Some(named) => {
                    for delivery in named {
                        let delivery = delivery.as_str().unwrap();
                        assert!(deliveries.contains(&delivery), "{delivery}");
                        assert!(covered.insert(delivery.to_owned()), "{delivery} twice");
                    }
                }
            }
        }
    }
}

fn model_json(model: &morphir_toolchain_contract::ModelFormat) -> Value {
    json!({
        "profile": model.profile.as_str(),
        "codec": model.codec.as_str(),
        "irVersion": model.ir_version.to_string()
    })
}

fn case_provider<'a>(step: &'a Value, delivery: &str) -> &'a Value {
    step["providers"]
        .as_array()
        .unwrap()
        .iter()
        .find(|provider| provider["delivery"] == delivery)
        .unwrap_or_else(|| panic!("{} covers {delivery}", step["id"]))
}

fn tuple_json(protocol: &Protocol) -> Value {
    let tuple = protocol.tuple();
    json!({
        "operation": tuple.operation().model_method(),
        "profile": tuple.profile().as_str(),
        "codec": tuple.codec().as_str(),
        "envelopeVersion": tuple.envelope_version().to_string(),
        "irVersion": tuple.ir_version().to_string()
    })
}

/// Every provider a recipe can select for an operation of the case is one
/// the case covers, with the same identity, protocol and model. So whatever
/// a generation selected, the case runs with that provider.
fn check_recipe_against_case(recipe: &morphir_toolchain_contract::ToolsetRecipe) {
    let case = case();
    assert_eq!(recipe.preset().as_str(), case["preset"]);
    for operation in recipe.operations() {
        let (id, built_in_member) = match operation {
            Operation::Compile { .. } => ("compile", "modelOutput"),
            Operation::Generate { .. } => ("generate", "modelInput"),
        };
        let step = step(&case, id);
        for host in recipe.hosts() {
            if let Some(built_in) = host
                .built_ins()
                .iter()
                .find(|built_in| built_in.operation() == operation)
            {
                let covered = case_provider(step, "built-in");
                assert_eq!(built_in.extension_id().as_str(), covered["extensionId"]);
                assert_eq!(model_json(built_in.model()), covered[built_in_member]);
            }
        }
        for provider in recipe
            .providers()
            .iter()
            .filter(|provider| provider.operation() == operation)
        {
            let covered = case_provider(step, provider.delivery().kind().as_str());
            let protocol = provider.delivery().protocol();
            assert_eq!(protocol.version().to_string(), covered["protocolVersion"]);
            assert_eq!(tuple_json(protocol), covered["modelTuple"]);
        }
    }
}

#[test]
fn every_provider_the_signed_fsharp_recipe_can_select_is_covered() {
    let repository =
        json(&root().join("docs/spec/toolchain/fixtures/0.1.0-draft.1/signed/repository.json"));
    let recipe = read_recipe(
        repository["targetFiles"]["toolchains/recipes/fsharp/1.0.0.json"]
            .as_str()
            .unwrap()
            .as_bytes(),
    )
    .unwrap();
    check_recipe_against_case(&recipe);
    // The managed offerings compile in process; Native AOT does not.
    for host in recipe.hosts() {
        let compiles = host
            .built_ins()
            .iter()
            .any(|built_in| matches!(built_in.operation(), Operation::Compile { .. }));
        assert_eq!(compiles, host.deployment().as_str() != "native-aot");
    }
}

#[test]
fn every_provider_the_synthetic_fsharp_recipe_can_select_is_covered() {
    let recipe = read_recipe(&read(
        &root().join("docs/spec/toolchain/fixtures/0.1.0-draft.1/recipe/fsharp-synthetic.json"),
    ))
    .unwrap();
    check_recipe_against_case(&recipe);
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
