use morphir_core::ir::classic;
use morphir_core::metadata::{
    Assertion, AssertionKey, Carrier, ContextResources, DocumentId, Fact, GraphName, ObjectTerm,
    expand_object, resolve_context,
};
use morphir_core::node_address::{NodeCatalog, NodeUri};
use morphir_decoration::project::DecorationProject;
use morphir_decoration::sidecar::DecorationSidecar;

const V3: &str = include_str!(
    "../../../ecosystem/morphir-rust/crates/morphir-core/tests/fixtures/ir/classic/greeting-example.json"
);
const V4: &str = include_str!(
    "../../../ecosystem/morphir-rust/crates/morphir-core/tests/fixtures/ir/v4/v4-library-distribution.json"
);

fn project_with_ir(ir_text: &str, entry_point: &str) -> (tempfile::TempDir, DecorationProject) {
    let root = tempfile::tempdir().unwrap();
    let ir = root.path().join("morphir-ir.json");
    let config = root.path().join("morphir.json");
    std::fs::write(&ir, ir_text).unwrap();
    std::fs::write(
        &config,
        serde_json::json!({"decorations": {"labels": {
            "ir": "morphir-ir.json", "entryPoint": entry_point,
            "storageLocation": "attributes/labels.json"
        }}})
        .to_string(),
    )
    .unwrap();
    let project = DecorationProject::open(&config, "labels", &ir).unwrap();
    (root, project)
}

#[test]
fn projects_v3_sidecar_with_verified_type_predicate_and_owner() {
    let (_root, project) = project_with_ir(V3, "ElmCompat:Api:apiError");
    let target =
        NodeUri::parse("morphir://ir/pkg/elm-compat?format=3.0.0#/module/api/type/request")
            .unwrap();
    let predicate =
        NodeUri::parse("morphir://ir/pkg/elm-compat?format=3.0.0#/module/api/type/api-error")
            .unwrap();
    let mut sidecar = DecorationSidecar::empty();
    sidecar.insert(target.clone(), serde_json::json!(["internalError"]));
    let unchanged = sidecar.clone();
    let owner = DocumentId::new("attributes/labels.json").unwrap();

    let graph = project.project_sidecar(&sidecar, owner.clone()).unwrap();
    assert_eq!(graph.facts().len(), 1);
    assert_eq!(graph.assertions().len(), 1);
    let key = graph.assertions()[0].key();
    assert_eq!(key.owner(), &owner);
    assert_eq!(key.fact().subject(), &target);
    assert_eq!(key.fact().predicate(), &predicate);
    assert_eq!(key.fact().graph(), &GraphName::Default);
    assert_eq!(
        key.fact().object(),
        &ObjectTerm::typed_json(serde_json::json!(["internalError"]), predicate.clone())
    );
    assert_eq!(
        key.carrier(),
        &Carrier::Sidecar {
            target,
            entry_point: predicate
        }
    );
    assert_eq!(sidecar, unchanged);
}

#[test]
fn projects_v4_sidecar_and_rejects_stale_target_without_partial_graph() {
    let (_root, project) = project_with_ir(V4, "example/v4-test:domain#user-id");
    let target =
        NodeUri::parse("morphir://ir/pkg/example/v4-test?format=4.0.0#/module/domain/type/user-id")
            .unwrap();
    let mut sidecar = DecorationSidecar::empty();
    sidecar.insert(target.clone(), serde_json::json!("customer-1"));
    let owner = DocumentId::new("attributes/labels.json").unwrap();
    let graph = project.project_sidecar(&sidecar, owner.clone()).unwrap();
    assert_eq!(graph.facts().len(), 1);
    assert_eq!(graph.assertions()[0].key().fact().predicate(), &target);
    assert_eq!(
        graph.assertions()[0].key().fact().object(),
        &ObjectTerm::typed_json(serde_json::json!("customer-1"), target.clone())
    );

    let digest = NodeCatalog::new()
        .add_v4_json_snapshot(V4.as_bytes(), None)
        .unwrap();
    let pinned = NodeUri::parse(&format!(
        "morphir://ir/pkg/example/v4-test?format=4.0.0&rev={digest}#/module/domain/type/user-id"
    ))
    .unwrap();
    let mut pinned_sidecar = DecorationSidecar::empty();
    pinned_sidecar.insert(pinned.clone(), serde_json::json!("customer-1"));
    let pinned_graph = project
        .project_sidecar(&pinned_sidecar, owner.clone())
        .unwrap();
    assert_eq!(pinned_graph.facts()[0].subject(), &pinned);
    assert_eq!(
        pinned_graph.assertions()[0].key().carrier(),
        &Carrier::Sidecar {
            target: pinned,
            entry_point: target.clone(),
        }
    );

    let stale =
        NodeUri::parse("morphir://ir/pkg/example/v4-test?format=4.0.0#/module/domain/type/missing")
            .unwrap();
    sidecar.insert(stale, serde_json::json!("customer-2"));
    assert!(project.project_sidecar(&sidecar, owner).is_err());
}

#[test]
fn separately_expanded_typed_fact_coalesces_without_losing_ownership() {
    let (_root, project) = project_with_ir(V4, "example/v4-test:domain#user-id");
    let target =
        NodeUri::parse("morphir://ir/pkg/example/v4-test?format=4.0.0#/module/domain/type/user-id")
            .unwrap();
    let mut sidecar = DecorationSidecar::empty();
    sidecar.insert(target.clone(), serde_json::json!("customer-1"));
    let sidecar_owner = DocumentId::new("attributes/labels.json").unwrap();
    let native_owner = DocumentId::new("morphir-ir.json").unwrap();
    let mut graph = project
        .project_sidecar(&sidecar, sidecar_owner.clone())
        .unwrap();
    let predicate = graph.facts()[0].predicate().clone();
    let context = resolve_context(
        None,
        &serde_json::json!({
            "label": {"@id": predicate.to_string(), "@type": "@json"}
        }),
        &ContextResources::new("contexts"),
        None,
    )
    .unwrap();
    let binding = context.expand_key("label").unwrap();
    let fact = Fact::new(
        target,
        binding.uri().clone(),
        expand_object(
            binding.coercion(),
            serde_json::json!("customer-1"),
            Some(predicate),
        )
        .unwrap(),
        GraphName::Default,
    );
    graph
        .insert(Assertion::new(
            AssertionKey::new(native_owner.clone(), Carrier::DocumentGraph, fact).unwrap(),
        ))
        .unwrap();

    assert_eq!(graph.facts().len(), 1);
    assert_eq!(graph.assertions().len(), 2);
    assert_eq!(graph.assertions()[0].key().owner(), &sidecar_owner);
    assert_eq!(graph.assertions()[1].key().owner(), &native_owner);
}

#[test]
fn proposed_v4_revision_is_not_misclassified_as_v3() {
    let root = tempfile::tempdir().unwrap();
    let ir = root.path().join("morphir-ir.json");
    let config = root.path().join("morphir.json");
    let mut proposed: serde_json::Value = serde_json::from_str(V4).unwrap();
    proposed["formatVersion"] = serde_json::json!("4.1.0");
    std::fs::write(&ir, proposed.to_string()).unwrap();
    std::fs::write(&config, r#"{"decorations":{"labels":{"ir":"morphir-ir.json","entryPoint":"example/v4-test:domain#user-id","storageLocation":"attributes/labels.json"}}}"#).unwrap();
    let error = DecorationProject::open(&config, "labels", &ir)
        .err()
        .unwrap();
    assert!(
        error.to_string().contains("unsupported V4 target IR"),
        "{error}"
    );
}

#[test]
fn unsupported_entry_point_index_only_blocks_projection() {
    let root = tempfile::tempdir().unwrap();
    let target_ir = root.path().join("target-ir.json");
    let type_ir = root.path().join("type-ir.json");
    let config = root.path().join("morphir.json");
    let mut proposed: serde_json::Value = serde_json::from_str(V4).unwrap();
    proposed["formatVersion"] = serde_json::json!("4.1.0");
    std::fs::write(&target_ir, V4).unwrap();
    std::fs::write(&type_ir, proposed.to_string()).unwrap();
    std::fs::write(&config, r#"{"decorations":{"labels":{"ir":"type-ir.json","entryPoint":"example/v4-test:domain#user-id","storageLocation":"attributes/labels.json"}}}"#).unwrap();
    let project = DecorationProject::open(&config, "labels", &target_ir).unwrap();
    let target =
        NodeUri::parse("morphir://ir/pkg/example/v4-test?format=4.0.0#/module/domain/type/user-id")
            .unwrap();
    project
        .set(target, serde_json::json!("customer-1"))
        .unwrap();
    let sidecar = project.load().unwrap();
    let error = project
        .project_sidecar(&sidecar, DocumentId::new("attributes/labels.json").unwrap())
        .err()
        .unwrap();
    assert!(error.to_string().contains("entryPoint"), "{error}");
}

#[test]
fn dependency_entry_point_needs_its_verified_provider_for_projection() {
    let root = tempfile::tempdir().unwrap();
    let target_ir = root.path().join("target-ir.json");
    let type_ir = root.path().join("type-ir.json");
    let config = root.path().join("morphir.json");
    let dependency_spec = classic::PackageSpecification {
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
    };
    let type_distribution = classic::Distribution {
        format_version: 3,
        distribution: classic::DistributionBody::Specs(
            classic::Path::new(vec![classic::Name::from_str("Acme")]),
            vec![(
                classic::Path::new(vec![classic::Name::from_str("External")]),
                dependency_spec,
            )],
            classic::PackageSpecification { modules: vec![] },
        ),
    };
    std::fs::write(&target_ir, V3).unwrap();
    std::fs::write(&type_ir, serde_json::to_vec(&type_distribution).unwrap()).unwrap();
    std::fs::write(&config, r#"{"decorations":{"labels":{"ir":"type-ir.json","entryPoint":"External:Domain:Label","storageLocation":"attributes/labels.json"}}}"#).unwrap();
    let project = DecorationProject::open(&config, "labels", &target_ir).unwrap();
    let target =
        NodeUri::parse("morphir://ir/pkg/elm-compat?format=3.0.0#/module/api/type/request")
            .unwrap();
    let mut sidecar = DecorationSidecar::empty();
    sidecar.insert(target, serde_json::Value::Null);
    let error = project
        .project_sidecar(&sidecar, DocumentId::new("attributes/labels.json").unwrap())
        .err()
        .unwrap();
    assert!(error.to_string().contains("provider"), "{error}");
}
