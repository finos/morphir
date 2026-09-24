use indexmap::IndexMap;
use morphir_core::ir::{classic, v4};
use morphir_core::naming::{FQName, Name, PackageName, Path};
use morphir_decoration::value_type::ValueValidator;

#[test]
fn v3_custom_type_values_follow_the_configured_entry_point() {
    let distribution: classic::Distribution = serde_json::from_str(include_str!(
        "../../../ecosystem/morphir-rust/crates/morphir-core/tests/fixtures/ir/classic/greeting-example.json"
    ))
    .unwrap();
    let validator = ValueValidator::v3(&distribution, "ElmCompat:Api:apiError").unwrap();
    validator
        .validate(&serde_json::json!(["internalError"]))
        .unwrap();
    validator
        .validate(&serde_json::json!(["invalidRequest", "bad request"]))
        .unwrap();
    assert!(
        validator
            .validate(&serde_json::json!(["invalidRequest", 42]))
            .is_err()
    );
    assert!(validator.validate(&serde_json::json!(["unknown"])).is_err());
    assert!(ValueValidator::v3(&distribution, "ElmCompat:Api:missing").is_err());
}

#[test]
fn v4_record_values_use_the_same_declared_morphir_type() {
    let string = v4::Type::reference(
        v4::TypeAttributes::default(),
        FQName::from_canonical_string("morphir/SDK:string#string").unwrap(),
        vec![],
    );
    let documentation = v4::TypeDefinition::TypeAliasDefinition {
        type_params: vec![],
        type_expr: v4::Type::record(
            v4::TypeAttributes::default(),
            vec![v4::Field::new(Name::from("summary"), string)],
        ),
    };
    let distribution = v4::Distribution::Library(v4::LibraryContent {
        package_name: PackageName::new(Path::new("acme/decorations")),
        dependencies: IndexMap::new(),
        def: v4::PackageDefinition {
            modules: IndexMap::from([(
                "domain".into(),
                v4::AccessControlled {
                    access: v4::Access::Public,
                    value: v4::ModuleDefinition {
                        types: IndexMap::from([(
                            "documentation".into(),
                            v4::AccessControlled {
                                access: v4::Access::Public,
                                value: v4::Documented::new(None, documentation),
                            },
                        )]),
                        values: IndexMap::new(),
                        doc: None,
                    },
                },
            )]),
        },
    });
    let validator =
        ValueValidator::v4(&distribution, "Acme.Decorations:Domain:Documentation").unwrap();
    validator
        .validate(&serde_json::json!({"summary":"Order"}))
        .unwrap();
    assert!(
        validator
            .validate(&serde_json::json!({"summary":42}))
            .is_err()
    );
    assert!(validator.validate(&serde_json::json!({})).is_err());
}

#[test]
fn distinct_sdk_package_spelling_is_not_treated_as_the_sdk() {
    let text = include_str!(
        "../../../ecosystem/morphir-rust/crates/morphir-core/tests/fixtures/ir/v4/v4-library-distribution.json"
    );
    let different_package = text.replace("morphir/SDK", "morphir/sdk");
    let file: morphir_core::ir::v4::IRFile = serde_json::from_str(&different_package).unwrap();
    let validator =
        ValueValidator::v4(&file.distribution, "example/v4-test:domain#user-id").unwrap();
    assert!(
        validator
            .validate(&serde_json::json!("customer-1"))
            .is_err()
    );
}
