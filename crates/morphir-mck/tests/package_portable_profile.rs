use morphir_mck::package::local_registry::{
    CorpusSource, RepositorySource, inspect_portable_profile,
};
use serde_json::{Value, json};
use std::{collections::BTreeMap, path::Path};

const PROFILE: &str = "spec/package/mck/portable-local-registry-cases.json";

struct Overlay {
    source: RepositorySource,
    files: BTreeMap<String, Vec<u8>>,
}
impl CorpusSource for Overlay {
    fn read(&self, path: &str) -> Result<Vec<u8>, String> {
        self.files
            .get(path)
            .cloned()
            .map(Ok)
            .unwrap_or_else(|| self.source.read(path))
    }
}
fn source() -> Overlay {
    Overlay {
        source: RepositorySource::new(Path::new(env!("CARGO_MANIFEST_DIR")).join("../..")).unwrap(),
        files: BTreeMap::new(),
    }
}
fn mutate(change: impl FnOnce(&mut Value)) -> Overlay {
    let mut source = source();
    let mut profile: Value = serde_json::from_slice(&source.read(PROFILE).unwrap()).unwrap();
    change(&mut profile);
    source
        .files
        .insert(PROFILE.into(), serde_json::to_vec(&profile).unwrap());
    source
}
fn rejects(source: &Overlay, expected: &str) {
    let summary = inspect_portable_profile(source);
    assert!(
        summary.errors.join(" ").contains(expected),
        "{:?}",
        summary.errors
    );
}

#[test]
fn portable_inventory_is_planning_and_never_executable_coverage() {
    let source = source();
    let summary = inspect_portable_profile(&source);
    assert!(summary.errors.is_empty(), "{:?}", summary.errors);
    assert_eq!(summary.kind, "definition-planning-summary");
    assert_eq!(summary.derived_case_count, 46);
    assert_eq!(summary.source_asset_count, 90);
    assert_eq!(summary.source_bound_asset_count, 6);
    assert_eq!(summary.source_pending_asset_count, 84);
    assert!(summary.case_count > 150);
    assert_eq!(summary.pending_definition_count, summary.case_count);
    let serialized = serde_json::to_value(summary).unwrap();
    assert!(serialized.get("contentHash").is_none());
}

#[test]
fn duplicate_case_ids_and_required_memberships_are_rejected() {
    rejects(
        &mutate(|p| {
            let c = p["cases"][0].clone();
            p["cases"].as_array_mut().unwrap().push(c);
        }),
        "duplicate case",
    );
    rejects(
        &mutate(|p| {
            let c = p["requiredGroups"]["common"][0].clone();
            p["requiredGroups"]["common"]
                .as_array_mut()
                .unwrap()
                .push(c);
        }),
        "duplicate required membership",
    );
}

#[test]
fn missing_unknown_and_wrong_group_memberships_are_rejected() {
    rejects(
        &mutate(|p| {
            p["requiredGroups"]["common"]
                .as_array_mut()
                .unwrap()
                .remove(0);
        }),
        "missing required membership",
    );
    rejects(
        &mutate(|p| {
            p["requiredGroups"]["common"]
                .as_array_mut()
                .unwrap()
                .push(json!("portable-local-registry.wire.unknown"));
        }),
        "unknown required membership",
    );
    rejects(
        &mutate(|p| {
            let c = p["requiredGroups"]["common"]
                .as_array_mut()
                .unwrap()
                .remove(0);
            p["requiredGroups"]["posix"].as_array_mut().unwrap().push(c);
        }),
        "required membership",
    );
}

#[test]
fn environment_identity_and_all_required_groups_are_checked() {
    rejects(
        &mutate(|p| p["environments"][0]["filesystem"] = json!("ntfs")),
        "environment identity",
    );
    rejects(
        &mutate(|p| p["environments"][0]["requiredGroups"] = json!(["common"])),
        "environment groups",
    );
    rejects(
        &mutate(|p| {
            let e = p["environments"][0].clone();
            p["environments"].as_array_mut().unwrap().push(e);
        }),
        "duplicate environment",
    );
    rejects(
        &mutate(|p| {
            p["environments"].as_array_mut().unwrap().remove(0);
        }),
        "missing environment",
    );
    rejects(
        &mutate(|p| p["environments"][0]["id"] = json!("caller-claimed-os")),
        "environment identity",
    );
}

#[test]
fn derivations_preserve_source_operations_and_remove_only_publication_setup() {
    rejects(
        &mutate(|p| {
            p["cases"][0]["provenance"]["caseId"] =
                json!("local-registry.publication.two-writers-one-predecessor");
        }),
        "source derivation",
    );
    rejects(
        &mutate(|p| {
            p["cases"][0]["derivation"]["removeSetup"] = json!(["/operations"]);
        }),
        "derivation",
    );
}

#[test]
fn planning_cannot_be_promoted_by_claiming_bound_fixtures_or_hashes() {
    rejects(&mutate(|p| p["status"] = json!("executable")), "schema");
    rejects(
        &mutate(|p| p["contentHash"] = json!("sha256:fake")),
        "schema",
    );
    rejects(
        &mutate(|p| p["cases"][0]["definition"]["kind"] = json!("bound")),
        "schema",
    );
}
