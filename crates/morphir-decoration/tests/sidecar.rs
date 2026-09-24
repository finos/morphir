use morphir_core::ir::classic;
use morphir_core::naming::{PackageName, Path};
use morphir_core::node_address::{ArtifactSelector, NodeCatalog, NodeIndex, NodeUri};
use morphir_decoration::sidecar::{DecorationSidecar, SidecarError};
use morphir_decoration::value_type::ValueValidator;

fn classic_index() -> (classic::Distribution, NodeIndex) {
    let distribution: classic::Distribution = serde_json::from_str(include_str!(
        "../../../ecosystem/morphir-rust/crates/morphir-core/tests/fixtures/ir/classic/greeting-example.json"
    ))
    .unwrap();
    let index = NodeIndex::v3(
        &distribution,
        ArtifactSelector::Package(PackageName::new(Path::new("elm-compat"))),
    )
    .unwrap();
    (distribution, index)
}

#[test]
fn versioned_sidecar_round_trips_without_changing_values() {
    let source = r#"{
      "formatVersion":"1.0.0-draft.1",
      "targets":{
        "morphir://ir/pkg/acme/orders?format=4.0.0#/module/domain/type/order":{"summary":"Order"}
      }
    }"#;
    let parsed = DecorationSidecar::parse(source).unwrap();
    let rendered = parsed.to_json().unwrap();
    assert_eq!(DecorationSidecar::parse(&rendered).unwrap(), parsed);
    assert!(rendered.contains("\"summary\": \"Order\""));
}

#[test]
fn missing_invalid_and_duplicate_sidecars_do_not_look_empty() {
    let dir = tempfile::tempdir().unwrap();
    assert!(matches!(
        DecorationSidecar::load(&dir.path().join("absent.json")),
        Err(SidecarError::Io { .. })
    ));
    assert!(DecorationSidecar::parse("not JSON").is_err());
    assert!(DecorationSidecar::parse(r#"{"formatVersion":"1.0.0-draft.9","targets":{}}"#).is_err());
    assert!(
        DecorationSidecar::parse(r#"{"formatVersion":"1.0.0-draft.1","targets":{"a":1,"a":2}}"#)
            .is_err()
    );
}

#[test]
fn failed_validation_preserves_the_old_file() {
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("decorations.json");
    let old = r#"{"legacy":"original"}"#;
    std::fs::write(&path, old).unwrap();
    let (distribution, index) = classic_index();
    let next = DecorationSidecar::migrate_v3(
        r#"{"ElmCompat:Api:request.type#action":42}"#,
        &distribution,
        &index,
    )
    .unwrap();
    let failure = next.save_for_index(&path, &index, |_| {
        Err(SidecarError::InvalidValue("rejected".into()))
    });
    assert!(failure.is_err());
    assert_eq!(std::fs::read_to_string(&path).unwrap(), old);
}

#[test]
fn legacy_v3_conversion_is_shape_checked_and_collision_safe() {
    let (distribution, index) = classic_index();
    let migrated = DecorationSidecar::migrate_v3(
        r#"{"ElmCompat:Api:request.type#action":["pII"]}"#,
        &distribution,
        &index,
    )
    .unwrap();
    assert_eq!(migrated.targets().len(), 1);
    assert!(migrated.targets().contains_key("morphir://ir/pkg/elm-compat?format=3.0.0#/module/api/type/request/type-exp/record/field/action"));
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("attributes/decoration.json");
    migrated.save_for_index(&path, &index, |_| Ok(())).unwrap();
    assert_eq!(DecorationSidecar::load(&path).unwrap(), migrated);
    let original_bytes = std::fs::read(&path).unwrap();
    let stale = DecorationSidecar::parse(r#"{"formatVersion":"1.0.0-draft.1","targets":{"morphir://ir/pkg/elm-compat?format=3.0.0#/module/api/type/missing":1}}"#).unwrap();
    assert!(matches!(
        stale.save_for_index(&path, &index, |_| Ok(())),
        Err(SidecarError::InvalidTarget { .. })
    ));
    assert_eq!(std::fs::read(&path).unwrap(), original_bytes);
    assert!(matches!(
        DecorationSidecar::migrate_v3(
            r#"{"ElmCompat:Api:request.type#action":["pII"],"ElmCompat:Api:request/type#action":["nPI"]}"#,
            &distribution,
            &index,
        ),
        Err(SidecarError::DuplicateTarget(_))
    ));
    assert!(matches!(
        DecorationSidecar::migrate_v3(
            r#"{"ElmCompat:Api:request.type#missing":["pII"]}"#,
            &distribution,
            &index,
        ),
        Err(SidecarError::InvalidTarget { .. })
    ));
}

#[test]
fn typed_save_checks_all_values_before_replacing_the_file() {
    let (distribution, index) = classic_index();
    let validator = ValueValidator::v3(&distribution, "ElmCompat:Api:apiError").unwrap();
    let target = index
        .addresses()
        .find(|address| address.to_string().ends_with("#/module/api/type/request"))
        .unwrap()
        .clone();
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("decorations.json");
    let mut sidecar = DecorationSidecar::empty();
    sidecar.insert(target.clone(), serde_json::json!(["internalError"]));
    sidecar.save_typed(&path, &index, &validator).unwrap();
    let old_bytes = std::fs::read(&path).unwrap();
    sidecar.insert(target, serde_json::json!(["invalidRequest", 99]));
    assert!(matches!(
        sidecar.save_typed(&path, &index, &validator),
        Err(SidecarError::InvalidValue(_))
    ));
    assert_eq!(std::fs::read(&path).unwrap(), old_bytes);
}

#[test]
fn pinned_sidecar_target_uses_the_exact_supplied_snapshot() {
    let (distribution, _) = classic_index();
    let validator = ValueValidator::v3(&distribution, "ElmCompat:Api:apiError").unwrap();
    let mut catalog = NodeCatalog::new();
    let digest = catalog.add_v3_json_snapshot(include_str!("../../../ecosystem/morphir-rust/crates/morphir-core/tests/fixtures/ir/classic/greeting-example.json").as_bytes(), None).unwrap();
    let pinned = NodeUri::parse(&format!(
        "morphir://ir/pkg/elm-compat?format=3.0.0&rev={digest}#/module/api/type/request"
    ))
    .unwrap();
    let mut sidecar = DecorationSidecar::empty();
    sidecar.insert(pinned, serde_json::json!(["internalError"]));
    let dir = tempfile::tempdir().unwrap();
    sidecar
        .save_typed_with_catalog(&dir.path().join("pinned.json"), &catalog, &validator)
        .unwrap();
}
