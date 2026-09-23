//! The complete V3 data model must survive compilation and regeneration.
use morphir_core::ir::v4::{self, TypeDefinition};
use morphir_extension_sdk::prelude::*;
use morphir_gleam_binding::GleamExtension;
use std::{collections::BTreeMap, fs, path::PathBuf, process::Command};

const MODULES: &[(&str, usize)] = &[
    ("access_controlled", 2),
    ("documented", 1),
    ("name", 1),
    ("path", 1),
    ("qname", 1),
    ("fqname", 1),
    ("literal", 1),
    ("type_", 8),
    ("value", 6),
    ("module", 4),
    ("package", 3),
    ("distribution", 1),
];

fn fixture() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../examples/gleam/ir-v3")
}

fn sources() -> Vec<SourceDocument> {
    MODULES
        .iter()
        .map(|(name, _)| {
            let path = format!("morphir/ir/{name}.gleam");
            SourceDocument {
                uri: format!("file:///src/{path}"),
                language_id: "gleam".into(),
                version: 1,
                text: fs::read_to_string(fixture().join("src").join(path))
                    .expect("complete V3 source fixture"),
            }
        })
        .collect()
}

fn semantics_fixture() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../spec/ir/semantics/v3")
}

fn sdk_module(name: &str, type_parameters: &[&str]) -> v4::ModuleSpecification {
    v4::ModuleSpecification {
        annotations: vec![],
        types: [(
            name.into(),
            v4::Documented::new(
                None,
                v4::TypeSpecification::OpaqueTypeSpecification {
                    annotations: vec![],
                    type_params: type_parameters
                        .iter()
                        .map(|name| morphir_core::naming::Name::from(name))
                        .collect(),
                },
            ),
        )]
        .into(),
        values: Default::default(),
        doc: None,
    }
}

fn sdk_basics_module() -> v4::ModuleSpecification {
    let primitive = |name: &str| {
        v4::Type::Reference(
            Default::default(),
            morphir_core::naming::FQName {
                package_path: morphir_core::naming::PackageName::parse("morphir/SDK").into(),
                module_path: morphir_core::naming::ModuleName::parse("basics").into(),
                local_name: morphir_core::naming::Name::from(name),
            },
            vec![],
        )
    };
    let signature = |output: &str| {
        v4::Documented::new(
            None,
            v4::ValueSpecification {
                annotations: vec![],
                inputs: [
                    ("left".into(), primitive("int")),
                    ("right".into(), primitive("int")),
                ]
                .into(),
                output: primitive(output),
            },
        )
    };
    v4::ModuleSpecification {
        annotations: vec![],
        types: ["int", "bool"]
            .into_iter()
            .map(|name| {
                (
                    name.into(),
                    v4::Documented::new(
                        None,
                        v4::TypeSpecification::OpaqueTypeSpecification {
                            annotations: vec![],
                            type_params: vec![],
                        },
                    ),
                )
            })
            .collect(),
        values: [
            ("add".into(), signature("int")),
            ("equal".into(), signature("bool")),
        ]
        .into(),
        doc: None,
    }
}

fn compile_arity_rule() -> serde_json::Value {
    let root = semantics_fixture();
    let mut documents = MODULES
        .iter()
        .map(|(name, _)| {
            let path = format!("morphir/ir/{name}.gleam");
            SourceDocument {
                uri: format!("file:///src/{path}"),
                language_id: "gleam".into(),
                version: 1,
                text: fs::read_to_string(root.join("src").join(path)).unwrap(),
            }
        })
        .collect::<Vec<_>>();
    documents.push(SourceDocument {
        uri: "file:///src/morphir/validation/arity.gleam".into(),
        language_id: "gleam".into(),
        version: 1,
        text: fs::read_to_string(root.join("src/morphir/validation/arity.gleam")).unwrap(),
    });
    let sdk = v4::PackageSpecification {
        modules: [
            ("basics".into(), sdk_basics_module()),
            ("dict".into(), sdk_module("dict", &["key", "value"])),
            ("maybe".into(), sdk_module("maybe", &["value"])),
        ]
        .into(),
    };
    let dependency = CompileDependency {
        package_name: "morphir/SDK".into(),
        ir_version: "4".into(),
        distribution: serde_json::to_value(v4::IRFile {
            format_version: Default::default(),
            distribution: v4::Distribution::Specs(v4::SpecsContent {
                package_name: morphir_core::naming::PackageName::parse("morphir/SDK"),
                dependencies: Default::default(),
                spec: sdk,
            }),
        })
        .unwrap(),
    };
    let result = GleamExtension
        .compile(CompileRequest {
            language_id: "gleam".into(),
            sources: SourceSet {
                root: None,
                documents,
            },
            package: CompilePackage {
                name: "morphir/ir-specification".into(),
                exposed_modules: None,
            },
            dependencies: vec![dependency],
            options: CompileOptions {
                ir_version: "3".into(),
                types_only: false,
                extra: [("emitParseStage".into(), false.into())].into(),
            },
            ..Default::default()
        })
        .unwrap();
    assert!(result.success, "{:?}", result.diagnostics);
    assert!(
        !result
            .diagnostics
            .iter()
            .any(|diagnostic| diagnostic.code.as_deref() == Some("GLEAM_VALUE_SKIPPED"))
    );
    result.ir.unwrap()
}

#[test]
fn v3_arity_rule_compiles_with_typed_bodies_and_explicit_sdk_specification() {
    let compiled = compile_arity_rule();
    let package = package(&compiled);
    let rule = &package.modules["morphir/validation/arity"].value;
    assert!(rule.types.contains_key("arity-outcome"));
    assert_eq!(rule.values.len(), 3);
    for name in ["check-arity", "count", "compare-count"] {
        let definition = &rule.values[name].value.value;
        assert!(definition.output_type.is_some(), "{name}");
        assert!(
            matches!(definition.body, v4::ValueBody::Expression(_)),
            "{name}"
        );
    }
    let v4::ValueBody::Expression(v4::Value::PatternMatch(attributes, _, cases)) =
        &rule.values["count"].value.value.body
    else {
        panic!("recursive count must retain its case expression")
    };
    assert_eq!(cases.len(), 2);
    assert!(attributes.inferred_type.is_some());
}

#[test]
fn compiled_v3_arity_rule_matches_five_fixed_cases() {
    use morphir_core::ir::classic;
    use morphir_runtime::{EvaluationLimits, RuntimeValue, evaluate_v3};
    let path =
        |text: &str| classic::Path::new(text.split('/').map(classic::Name::from_str).collect());
    let rule_name = |local: &str| {
        classic::FQName::new(
            path("morphir/ir-specification"),
            path("morphir/validation/arity"),
            classic::Name::from_str(local),
        )
    };
    let distribution: classic::Distribution = serde_json::from_value(compile_arity_rule()).unwrap();
    let cases: serde_json::Value = serde_json::from_str(
        &fs::read_to_string(semantics_fixture().join("cases/arity.json")).unwrap(),
    )
    .unwrap();
    assert_eq!(
        cases["rule"],
        "morphir/ir-specification:morphir/validation/arity#check-arity"
    );
    let fixed = cases["cases"].as_array().unwrap();
    assert_eq!(fixed.len(), 5);
    for case in fixed {
        let expected_arity = case["expectedArity"].as_i64().unwrap();
        let arguments = case["arguments"]
            .as_array()
            .unwrap()
            .iter()
            .map(|argument| {
                assert_eq!(argument, "Unit");
                RuntimeValue::Constructor(
                    classic::FQName::new(
                        path("morphir/ir-specification"),
                        path("morphir/ir/type"),
                        classic::Name::from_str("unit"),
                    ),
                    vec![RuntimeValue::Unit],
                )
            })
            .collect();
        let expected = if case["expected"]["kind"] == "Valid" {
            RuntimeValue::Constructor(rule_name("valid"), vec![])
        } else {
            RuntimeValue::Constructor(
                rule_name("mismatch"),
                vec![
                    RuntimeValue::Integer(case["expected"]["expected"].as_i64().unwrap()),
                    RuntimeValue::Integer(case["expected"]["actual"].as_i64().unwrap()),
                ],
            )
        };
        let actual = evaluate_v3(
            &distribution,
            &rule_name("check-arity"),
            vec![
                RuntimeValue::Integer(expected_arity),
                RuntimeValue::List(arguments),
            ],
            EvaluationLimits::default(),
        )
        .unwrap();
        assert_eq!(actual, expected, "{}", case["id"]);
    }
}

#[test]
fn compiled_v3_arity_rule_reports_missing_dependency_and_budget_separately() {
    use morphir_core::ir::classic;
    use morphir_runtime::{EvaluationError, EvaluationLimits, RuntimeValue, evaluate_v3};
    let path =
        |text: &str| classic::Path::new(text.split('/').map(classic::Name::from_str).collect());
    let entrypoint = classic::FQName::new(
        path("morphir/ir-specification"),
        path("morphir/validation/arity"),
        classic::Name::from_str("check-arity"),
    );
    let compiled: classic::Distribution = serde_json::from_value(compile_arity_rule()).unwrap();
    let arguments = vec![
        RuntimeValue::Integer(1),
        RuntimeValue::List(vec![RuntimeValue::Unit]),
    ];
    assert_eq!(
        evaluate_v3(
            &compiled,
            &entrypoint,
            arguments.clone(),
            EvaluationLimits {
                fuel: 1,
                max_call_depth: 256
            }
        ),
        Err(EvaluationError::FuelExhausted),
    );
    let mut missing_sdk = compiled;
    let classic::DistributionBody::Library(_, dependencies, _) = &mut missing_sdk.distribution;
    dependencies.clear();
    assert_eq!(
        evaluate_v3(
            &missing_sdk,
            &entrypoint,
            arguments,
            EvaluationLimits::default()
        ),
        Err(EvaluationError::MissingDependency(path("morphir/SDK"))),
    );
}

fn compile(documents: Vec<SourceDocument>) -> serde_json::Value {
    let result = GleamExtension
        .compile(CompileRequest {
            language_id: "gleam".into(),
            sources: SourceSet {
                root: None,
                documents,
            },
            package: CompilePackage {
                name: "morphir/ir-model".into(),
                exposed_modules: None,
            },
            options: CompileOptions {
                ir_version: "3".into(),
                types_only: true,
                extra: [("emitParseStage".into(), false.into())].into(),
            },
            ..Default::default()
        })
        .unwrap();
    assert!(result.success, "{:?}", result.diagnostics);
    let ir = result.ir.unwrap();
    assert_eq!(ir["formatVersion"], 3);
    ir
}

fn package(ir: &serde_json::Value) -> v4::PackageDefinition {
    let classic = serde_json::from_value(ir.clone()).unwrap();
    let migrated =
        morphir_core::migration::migrate_distribution(&classic, Default::default()).unwrap();
    let v4::Distribution::Library(library) = migrated.value.distribution else {
        panic!("library")
    };
    library.def
}

fn generate(ir: serde_json::Value) -> Vec<Artifact> {
    let result = GleamExtension
        .generate(GenerateRequest {
            ir,
            target: "gleam".into(),
            options: Default::default(),
        })
        .unwrap();
    assert!(result.success, "{:?}", result.diagnostics);
    assert_eq!(result.artifacts.len(), MODULES.len());
    result.artifacts
}

#[test]
fn complete_v3_model_preserves_definitions_and_generated_source() {
    let ir = compile(sources());
    let original = package(&ir);
    assert_eq!(original.modules.len(), MODULES.len());
    for (module, count) in MODULES {
        let canonical = morphir_core::naming::ModuleName::parse(module).to_string();
        let definition = &original.modules[&format!("morphir/ir/{canonical}")].value;
        assert_eq!(definition.types.len(), *count, "{module}");
        assert!(definition.values.is_empty(), "{module}");
    }
    for (module, name, constructors) in [
        (
            "type",
            "type",
            "variable reference tuple record extensible_record function unit",
        ),
        (
            "value",
            "value",
            "literal constructor tuple list record variable reference field field_function apply lambda let_definition let_recursion destructure if_then_else pattern_match update_record unit",
        ),
        (
            "value",
            "pattern",
            "wildcard_pattern as_pattern tuple_pattern constructor_pattern empty_list_pattern head_tail_pattern literal_pattern unit_pattern",
        ),
        (
            "literal",
            "literal",
            "bool_literal char_literal string_literal whole_number_literal float_literal decimal_literal",
        ),
        (
            "type",
            "specification",
            "type_alias_specification opaque_type_specification custom_type_specification derived_type_specification",
        ),
        (
            "type",
            "definition",
            "type_alias_definition custom_type_definition",
        ),
        ("distribution", "distribution", "library"),
    ] {
        let definition = &original.modules[&format!("morphir/ir/{module}")]
            .value
            .types[name]
            .value
            .value;
        let TypeDefinition::CustomTypeDefinition {
            constructors: actual,
            ..
        } = definition
        else {
            panic!("{module}.{name} must be an ADT")
        };
        assert_eq!(
            actual
                .value
                .iter()
                .map(|c| c.name.to_snake_case())
                .collect::<Vec<_>>(),
            constructors.split_whitespace().collect::<Vec<_>>(),
            "{module}.{name}"
        );
    }
    assert_semantic_boundaries(&original);
    let artifacts = generate(ir);
    for artifact in &artifacts {
        let expected = fs::read_to_string(fixture().join("golden").join(&artifact.path))
            .expect("fixed generation golden");
        assert_eq!(
            artifact.content.replace("\r\n", "\n"),
            expected.replace("\r\n", "\n"),
            "{}",
            artifact.path
        );
    }
    let regenerated = compile(
        artifacts
            .into_iter()
            .map(|artifact| SourceDocument {
                uri: format!("file:///src/{}", artifact.path),
                text: artifact.content,
                language_id: "gleam".into(),
                version: 1,
            })
            .collect(),
    );
    // Documentation formatting may change; every type body and access must survive.
    let types = |package: v4::PackageDefinition| -> BTreeMap<_, BTreeMap<_, _>> {
        package
            .modules
            .into_iter()
            .map(|(name, module)| {
                (
                    name,
                    module
                        .value
                        .types
                        .into_iter()
                        .map(|(name, ty)| (name, (ty.access, ty.value.value)))
                        .collect(),
                )
            })
            .collect()
    };
    assert_eq!(types(original), types(package(&regenerated)));
}

fn reference(module: &str, name: &str, parameters: Vec<v4::Type>) -> v4::Type {
    use morphir_core::naming::{FQName, ModuleName, Name, PackageName};
    v4::Type::Reference(
        Default::default(),
        FQName {
            package_path: PackageName::parse("morphir/ir-model").into(),
            module_path: ModuleName::parse(&format!("morphir/ir/{module}")).into(),
            local_name: Name::from(name),
        },
        parameters,
    )
}

fn assert_semantic_boundaries(package: &v4::PackageDefinition) {
    use morphir_core::naming::{FQName, Name, Path};
    let definition = |module: &str, name: &str| {
        &package.modules[&format!("morphir/ir/{module}")].value.types[&Name::from(name).to_string()]
            .value
            .value
    };
    let unit = v4::Type::Unit(Default::default());
    for (name, attributes) in [
        ("raw_value", unit.clone()),
        ("typed_value", reference("type", "type", vec![unit.clone()])),
    ] {
        assert_eq!(
            definition("value", name),
            &TypeDefinition::TypeAliasDefinition {
                type_params: vec![],
                type_expr: reference("value", "value", vec![unit.clone(), attributes]),
            }
        );
    }
    let TypeDefinition::CustomTypeDefinition { constructors, .. } =
        definition("distribution", "distribution")
    else {
        panic!("distribution")
    };
    let args = &constructors.value[0].args;
    assert_eq!(args.len(), 3);
    assert_eq!(
        args[0].arg_type,
        reference("package", "package_name", vec![])
    );
    assert_eq!(
        args[1].arg_type,
        v4::Type::Reference(
            Default::default(),
            FQName {
                package_path: Path::new("morphir/SDK"),
                module_path: Path::new("dict"),
                local_name: Name::from("dict"),
            },
            vec![
                reference("package", "package_name", vec![]),
                reference("package", "specification", vec![unit.clone()])
            ]
        )
    );
    assert_eq!(
        args[2].arg_type,
        reference(
            "package",
            "definition",
            vec![unit.clone(), reference("type", "type", vec![unit])]
        )
    );

    let TypeDefinition::CustomTypeDefinition {
        type_params,
        constructors,
    } = definition("value", "definition")
    else {
        panic!("value definition")
    };
    assert_eq!(type_params, &[Name::from("ta"), Name::from("va")]);
    let args = &constructors.value[0].args;
    let variable = |name| v4::Type::Variable(Default::default(), Name::from(name));
    let ty = reference("type", "type", vec![variable("ta")]);
    assert_eq!(
        args[0].arg_type,
        v4::Type::Reference(
            Default::default(),
            FQName {
                package_path: Path::new("morphir/SDK"),
                module_path: Path::new("list"),
                local_name: Name::from("list"),
            },
            vec![v4::Type::Tuple(
                Default::default(),
                vec![
                    reference("name", "name", vec![]),
                    variable("va"),
                    ty.clone()
                ]
            )]
        )
    );
    assert_eq!(args[1].arg_type, ty);
    assert_eq!(
        args[2].arg_type,
        reference("value", "value", vec![variable("ta"), variable("va")])
    );
}

#[test]
fn experimental_v3_arity_package_has_fixed_source_and_outcome_type() {
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../spec/ir/semantics/v3");
    let documents = MODULES
        .iter()
        .map(|(name, _)| format!("morphir/ir/{name}.gleam"))
        .chain(std::iter::once("morphir/validation/arity.gleam".to_owned()))
        .map(|path| SourceDocument {
            uri: format!("file:///src/{path}"),
            language_id: "gleam".into(),
            version: 1,
            text: fs::read_to_string(root.join("src").join(&path)).expect("pilot source file"),
        })
        .collect();
    let result = GleamExtension
        .compile(CompileRequest {
            language_id: "gleam".into(),
            sources: SourceSet {
                root: None,
                documents,
            },
            package: CompilePackage {
                name: "morphir/ir-specification".into(),
                exposed_modules: None,
            },
            options: CompileOptions {
                ir_version: "3".into(),
                types_only: true,
                extra: [("emitParseStage".into(), false.into())].into(),
            },
            ..Default::default()
        })
        .unwrap();
    assert!(result.success, "{:?}", result.diagnostics);
    let model = package(&result.ir.unwrap());
    let rule = &model.modules["morphir/validation/arity"].value;
    assert!(rule.types.contains_key("arity-outcome"));
    assert!(rule.values.is_empty());
    assert_eq!(
        result
            .diagnostics
            .iter()
            .filter(|d| d.code.as_deref() == Some("GLEAM_VALUE_SKIPPED"))
            .count(),
        3
    );
    let cases: serde_json::Value =
        serde_json::from_slice(&fs::read(root.join("cases/arity.json")).unwrap()).unwrap();
    assert_eq!(cases["cases"].as_array().unwrap().len(), 5);
}

#[test]
#[ignore = "requires Gleam and access to the pinned gleam_stdlib package"]
fn source_and_regenerated_v3_model_pass_gleam_check() {
    let artifacts = generate(compile(sources()));
    for documents in [
        sources(),
        artifacts
            .into_iter()
            .map(|artifact| SourceDocument {
                uri: format!("file:///src/{}", artifact.path),
                text: artifact.content,
                language_id: "gleam".into(),
                version: 1,
            })
            .collect(),
    ] {
        let project = tempfile::tempdir().unwrap();
        fs::copy(
            fixture().join("gleam.toml"),
            project.path().join("gleam.toml"),
        )
        .unwrap();
        fs::copy(
            fixture().join("manifest.toml"),
            project.path().join("manifest.toml"),
        )
        .unwrap();
        for document in documents {
            let path = project
                .path()
                .join(document.uri.strip_prefix("file:///").unwrap());
            fs::create_dir_all(path.parent().unwrap()).unwrap();
            fs::write(path, document.text).unwrap();
        }
        let compiler = std::env::var_os("MORPHIR_TEST_GLEAM").unwrap_or_else(|| "gleam".into());
        let output = Command::new(compiler)
            .args(["check", "--target", "javascript"])
            .current_dir(project.path())
            .output()
            .expect("run Gleam compiler");
        assert!(
            output.status.success(),
            "{}\n{}",
            String::from_utf8_lossy(&output.stdout),
            String::from_utf8_lossy(&output.stderr)
        );
    }
}
