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

fn compile(documents: Vec<SourceDocument>) -> serde_json::Value {
    let result = GleamExtension
        .compile(CompileRequest {
            language_id: "gleam".into(),
            sources: SourceSet {
                root: Some("file:///src".into()),
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
