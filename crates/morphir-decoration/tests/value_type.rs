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
    let error = validator
        .validate(&serde_json::json!(["invalidRequest", 42]))
        .unwrap_err();
    assert_eq!(error.path, "$[1]");
    assert!(error.message.contains("String"));
    assert!(ValueValidator::v3(&distribution, "ElmCompat:Api:missing").is_err());
    let error = validator
        .validate(&serde_json::json!(["unknown"]))
        .unwrap_err();
    assert_eq!(error.path, "$");
    assert!(error.message.contains("unknown constructor"));
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
    let error = validator
        .validate(&serde_json::json!({"summary":42}))
        .unwrap_err();
    assert_eq!(error.path, "$.summary");
    assert!(error.message.contains("String"));
    assert!(validator.validate(&serde_json::json!({})).is_err());
    assert!(ValueValidator::v4(&distribution, "Acme.Decorations:Domain:Missing").is_err());
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

#[test]
fn nested_aliases_resolve_arguments_before_shadowing_type_parameter_names() {
    let reference = |name: &str, args| {
        v4::Type::reference(
            v4::TypeAttributes::default(),
            FQName::from_canonical_string(name).unwrap(),
            args,
        )
    };
    let variable = || v4::Type::variable(v4::TypeAttributes::default(), Name::from("a"));
    let alias = |params, body| v4::AccessControlled {
        access: v4::Access::Public,
        value: v4::Documented::new(
            None,
            v4::TypeDefinition::TypeAliasDefinition {
                type_params: params,
                type_expr: body,
            },
        ),
    };
    let definitions = IndexMap::from([
        (
            "root".into(),
            alias(
                vec![],
                reference(
                    "acme/decorations:domain#outer",
                    vec![reference("morphir/SDK:string#string", vec![])],
                ),
            ),
        ),
        (
            "outer".into(),
            alias(
                vec![Name::from("a")],
                reference("acme/decorations:domain#inner", vec![variable()]),
            ),
        ),
        (
            "inner".into(),
            alias(
                vec![Name::from("a")],
                v4::Type::record(
                    v4::TypeAttributes::default(),
                    vec![v4::Field::new(Name::from("value"), variable())],
                ),
            ),
        ),
    ]);
    let distribution = v4::Distribution::Library(v4::LibraryContent {
        package_name: PackageName::new(Path::new("acme/decorations")),
        dependencies: IndexMap::new(),
        def: v4::PackageDefinition {
            modules: IndexMap::from([(
                "domain".into(),
                v4::AccessControlled {
                    access: v4::Access::Public,
                    value: v4::ModuleDefinition {
                        types: definitions,
                        values: IndexMap::new(),
                        doc: None,
                    },
                },
            )]),
        },
    });
    let validator = ValueValidator::v4(&distribution, "acme/decorations:domain#root").unwrap();
    validator
        .validate(&serde_json::json!({"value":"text"}))
        .unwrap();
    assert!(
        validator
            .validate(&serde_json::json!({"value":12}))
            .is_err()
    );
}

fn target_names_validator(key_name: &str) -> ValueValidator {
    let reference = |name: &str, args| {
        v4::Type::reference(
            v4::TypeAttributes::default(),
            FQName::from_canonical_string(name).unwrap(),
            args,
        )
    };
    let names = || {
        reference(
            "morphir/SDK:dict#dict",
            vec![
                reference(key_name, vec![]),
                reference("morphir/SDK:string#string", vec![]),
            ],
        )
    };
    let definition = v4::TypeDefinition::TypeAliasDefinition {
        type_params: vec![],
        type_expr: v4::Type::record(
            v4::TypeAttributes::default(),
            vec![
                v4::Field::new(Name::from("frontend"), names()),
                v4::Field::new(Name::from("backend"), names()),
            ],
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
                            "target-names".into(),
                            v4::AccessControlled {
                                access: v4::Access::Public,
                                value: v4::Documented::new(None, definition),
                            },
                        )]),
                        values: IndexMap::new(),
                        doc: None,
                    },
                },
            )]),
        },
    });
    ValueValidator::v4(&distribution, "acme/decorations:domain#target-names").unwrap()
}

#[test]
fn target_names_accepts_arbitrary_language_keys_and_rejects_non_string_names() {
    let validator = target_names_validator("morphir/SDK:string#string");
    validator
        .validate(&serde_json::json!({
            "frontend": {"en-US": "Customer", "zh-Hant-TW": "客戶"},
            "backend": {"x-custom": "customer_record"}
        }))
        .unwrap();
    let error = validator
        .validate(&serde_json::json!({
            "frontend": {"en-US": 42},
            "backend": {}
        }))
        .unwrap_err();
    assert_eq!(error.path, "$.frontend[\"en-US\"]");
    assert!(error.message.contains("String"));
}

#[test]
fn target_names_rejects_dict_key_types_without_json_member_spelling() {
    let validator = target_names_validator("morphir/SDK:basics#int");
    let error = validator
        .validate(&serde_json::json!({"frontend": {}, "backend": {}}))
        .unwrap_err();
    assert_eq!(error.path, "$.frontend");
    assert!(error.message.contains("Dict keys other than String"));
}
