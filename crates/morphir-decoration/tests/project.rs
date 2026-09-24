use morphir_core::ir::classic;
use morphir_core::node_address::{NodeCatalog, NodeUri};
use morphir_decoration::project::DecorationProject;
use morphir_decoration::sidecar::DecorationSidecar;

const V3: &str = include_str!(
    "../../../ecosystem/morphir-rust/crates/morphir-core/tests/fixtures/ir/classic/greeting-example.json"
);
const V4: &str = include_str!(
    "../../../ecosystem/morphir-rust/crates/morphir-core/tests/fixtures/ir/v4/v4-library-distribution.json"
);

#[test]
fn configured_project_accepts_v3_specs_target_and_type() {
    let root = tempfile::tempdir().unwrap();
    let config = root.path().join("morphir.json");
    let ir = root.path().join("morphir-ir.json");
    let distribution = classic::Distribution {
        format_version: 3,
        distribution: classic::DistributionBody::Specs(
            classic::Path::new(vec![classic::Name::from_str("Acme")]),
            vec![],
            classic::PackageSpecification {
                modules: vec![classic::package::ModuleSpecEntry {
                    path: classic::Path::new(vec![classic::Name::from_str("Domain")]),
                    specification: classic::ModuleSpecification {
                        types: vec![(
                            classic::Name::from_str("Label"),
                            classic::Documented::new(
                                "",
                                classic::TypeSpecification::Alias(
                                    vec![],
                                    classic::Type::Unit(classic::Attrs::None),
                                ),
                            ),
                        )],
                        values: vec![],
                        doc: None,
                    },
                }],
            },
        ),
    };
    std::fs::write(&ir, serde_json::to_vec(&distribution).unwrap()).unwrap();
    std::fs::write(&config, r#"{"decorations":{"labels":{"ir":"morphir-ir.json","entryPoint":"Acme:Domain:Label","storageLocation":"attributes/labels.json"}}}"#).unwrap();
    let project = DecorationProject::open(&config, "labels", &ir).unwrap();
    let target =
        NodeUri::parse("morphir://ir/pkg/acme?format=3.1.0#/module/domain/type/label").unwrap();
    project
        .set(target.clone(), serde_json::Value::Null)
        .unwrap();
    assert!(
        project
            .load()
            .unwrap()
            .targets()
            .contains_key(&target.to_string())
    );
    assert!(project.migrate_v3().is_err());

    std::fs::remove_file(&project.sidecar_path).unwrap();
    let patch_release = serde_json::to_string(&distribution)
        .unwrap()
        .replace("3.1.0", "3.1.1");
    std::fs::write(&ir, patch_release).unwrap();
    let patched = DecorationProject::open(&config, "labels", &ir).unwrap();
    let target =
        NodeUri::parse("morphir://ir/pkg/acme?format=3.1.1#/module/domain/type/label").unwrap();
    patched.set(target, serde_json::Value::Null).unwrap();
}

#[test]
fn configured_project_sets_typed_v3_decorations_and_preserves_old_file_on_failure() {
    let root = tempfile::tempdir().unwrap();
    let config = root.path().join("morphir.json");
    let ir = root.path().join("morphir-ir.json");
    std::fs::write(&ir, V3).unwrap();
    std::fs::write(&config, r#"{"decorations":{"errors":{"displayName":"Errors","ir":"morphir-ir.json","entryPoint":"ElmCompat:Api:apiError","storageLocation":"attributes/errors.json"}}}"#).unwrap();
    let project = DecorationProject::open(&config, "errors", &ir).unwrap();
    let target =
        NodeUri::parse("morphir://ir/pkg/elm-compat?format=3.0.0#/module/api/type/request")
            .unwrap();
    project
        .set(target.clone(), serde_json::json!(["internalError"]))
        .unwrap();
    assert_eq!(
        project.load().unwrap().targets().get(&target.to_string()),
        Some(&serde_json::json!(["internalError"]))
    );
    let bytes = std::fs::read(&project.sidecar_path).unwrap();
    assert!(
        project
            .set(target, serde_json::json!(["invalidRequest", 99]))
            .is_err()
    );
    assert_eq!(std::fs::read(&project.sidecar_path).unwrap(), bytes);
}

#[test]
fn configured_paths_cannot_leave_the_project_and_invalid_old_sidecar_is_not_empty() {
    let root = tempfile::tempdir().unwrap();
    let config = root.path().join("morphir.json");
    let ir = root.path().join("morphir-ir.json");
    std::fs::write(&ir, V3).unwrap();
    std::fs::write(&config, r#"{"decorations":{"errors":{"ir":"morphir-ir.json","entryPoint":"ElmCompat:Api:apiError","storageLocation":"../elsewhere.json"}}}"#).unwrap();
    assert!(DecorationProject::open(&config, "errors", &ir).is_err());
    std::fs::write(&config, r#"{"decorations":{"errors":{"ir":"morphir-ir.json","entryPoint":"ElmCompat:Api:apiError","storageLocation":"attributes/errors.json"}}}"#).unwrap();
    let project = DecorationProject::open(&config, "errors", &ir).unwrap();
    std::fs::create_dir_all(project.sidecar_path.parent().unwrap()).unwrap();
    std::fs::write(&project.sidecar_path, "invalid").unwrap();
    assert!(
        project
            .set(
                NodeUri::parse("morphir://ir/pkg/elm-compat?format=3.0.0#/module/api/type/request")
                    .unwrap(),
                serde_json::json!(["internalError"])
            )
            .is_err()
    );
    assert_eq!(
        std::fs::read_to_string(&project.sidecar_path).unwrap(),
        "invalid"
    );
    assert!(DecorationSidecar::load(&project.sidecar_path).is_err());
}

#[test]
fn configured_project_sets_typed_v4_decorations() {
    let root = tempfile::tempdir().unwrap();
    let config = root.path().join("morphir.json");
    let ir = root.path().join("morphir-ir.json");
    std::fs::write(&ir, V4).unwrap();
    std::fs::write(&config, r#"{"decorations":{"labels":{"ir":"morphir-ir.json","entryPoint":"example/v4-test:domain#user-id","storageLocation":"attributes/labels.json"}}}"#).unwrap();
    let project = DecorationProject::open(&config, "labels", &ir).unwrap();
    let target =
        NodeUri::parse("morphir://ir/pkg/example/v4-test?format=4.0.0#/module/domain/type/user-id")
            .unwrap();
    project
        .set(target.clone(), serde_json::json!("customer-1"))
        .unwrap();
    assert_eq!(
        project.load().unwrap().targets().get(&target.to_string()),
        Some(&serde_json::json!("customer-1"))
    );
    assert!(project.set(target, serde_json::json!(42)).is_err());
}

#[test]
fn configured_project_accepts_exact_revision_pinned_v4_target() {
    let root = tempfile::tempdir().unwrap();
    let config = root.path().join("morphir.json");
    let ir = root.path().join("morphir-ir.json");
    std::fs::write(&ir, V4).unwrap();
    std::fs::write(&config, r#"{"decorations":{"labels":{"ir":"morphir-ir.json","entryPoint":"example/v4-test:domain#user-id","storageLocation":"attributes/labels.json"}}}"#).unwrap();
    let project = DecorationProject::open(&config, "labels", &ir).unwrap();
    let digest = NodeCatalog::new()
        .add_v4_json_snapshot(V4.as_bytes(), None)
        .unwrap();
    let target = NodeUri::parse(&format!(
        "morphir://ir/pkg/example/v4-test?format=4.0.0&rev={digest}#/module/domain/type/user-id"
    ))
    .unwrap();
    project
        .set(target.clone(), serde_json::json!("customer-1"))
        .unwrap();
    assert_eq!(
        project.load().unwrap().targets().get(&target.to_string()),
        Some(&serde_json::json!("customer-1"))
    );
}

#[test]
fn configured_v3_migration_converts_legacy_nodeids_in_place() {
    let root = tempfile::tempdir().unwrap();
    let config = root.path().join("morphir.json");
    let ir = root.path().join("morphir-ir.json");
    std::fs::write(&ir, V3).unwrap();
    std::fs::write(&config, r#"{"decorations":{"errors":{"ir":"morphir-ir.json","entryPoint":"ElmCompat:Api:apiError","storageLocation":"attributes/errors.json"}}}"#).unwrap();
    let project = DecorationProject::open(&config, "errors", &ir).unwrap();
    std::fs::create_dir_all(project.sidecar_path.parent().unwrap()).unwrap();
    std::fs::write(
        &project.sidecar_path,
        r#"{"ElmCompat:Api:request.type#action":["internalError"]}"#,
    )
    .unwrap();
    project.migrate_v3().unwrap();
    let sidecar = project.load().unwrap();
    assert!(sidecar.targets().contains_key("morphir://ir/pkg/elm-compat?format=3.0.0#/module/api/type/request/type-exp/record/field/action"));
    assert_eq!(sidecar.targets().len(), 1);
}

#[cfg(unix)]
#[test]
fn configured_sidecar_path_is_rechecked_after_project_open() {
    use std::os::unix::fs::symlink;

    let root = tempfile::tempdir().unwrap();
    let outside = tempfile::tempdir().unwrap();
    let config = root.path().join("morphir.json");
    let ir = root.path().join("morphir-ir.json");
    std::fs::write(&ir, V4).unwrap();
    std::fs::write(&config, r#"{"decorations":{"labels":{"ir":"morphir-ir.json","entryPoint":"example/v4-test:domain#user-id","storageLocation":"attributes/labels.json"}}}"#).unwrap();
    let project = DecorationProject::open(&config, "labels", &ir).unwrap();
    symlink(outside.path(), root.path().join("attributes")).unwrap();
    let target =
        NodeUri::parse("morphir://ir/pkg/example/v4-test?format=4.0.0#/module/domain/type/user-id")
            .unwrap();
    assert!(
        project
            .set(target, serde_json::json!("customer-1"))
            .is_err()
    );
    assert!(project.load().is_err());
    assert!(!outside.path().join("labels.json").exists());
}
