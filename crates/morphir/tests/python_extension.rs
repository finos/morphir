//! Publish, install and use the Python release bundle through the CLI.

use std::{fs, path::PathBuf, process::Command};

#[test]
#[ignore = "requires MORPHIR_PYTHON_BUNDLE pointing to a packaged Python WASM guest"]
fn python_bundle_compiles_and_generates_offline() {
    let bundle = PathBuf::from(
        std::env::var_os("MORPHIR_PYTHON_BUNDLE").expect("build the Python release bundle first"),
    )
    .canonicalize()
    .unwrap();
    let root = tempfile::tempdir().unwrap();
    let project = root.path().join("project");
    let home = root.path().join("home");
    let repository = root.path().join("repository");
    fs::create_dir(&project).unwrap();
    fs::create_dir_all(project.join("src/domain")).unwrap();
    fs::write(
        project.join("morphir.toml"),
        "[project]\nname = \"acme/example\"\nversion = \"0.1.0\"\nsource_directory = \"src\"\n\
         [frontend]\nlanguage = \"python\"\nemit_parse_stage = false\n",
    )
    .unwrap();
    fs::write(
        project.join("src/domain/models.py"),
        concat!(
            "from dataclasses import dataclass\n",
            "@dataclass(frozen=True)\nclass Point:\n    coordinates: tuple[int, int]\n",
        ),
    )
    .unwrap();
    fs::write(
        project.join("src/domain/rules.py"),
        concat!(
            "from .models import Point\n",
            "def choose(flag: bool, first: Point, second: Point) -> Point:\n",
            "    if flag:\n        return first\n    else:\n        return second\n",
        ),
    )
    .unwrap();
    let run = |args: &[&str]| {
        let output = Command::new(env!("CARGO_BIN_EXE_morphir"))
            .args(args)
            .current_dir(&project)
            .env("MORPHIR_HOME", &home)
            .output()
            .unwrap();
        assert!(
            output.status.success(),
            "{args:?}: stdout={} stderr={}",
            String::from_utf8_lossy(&output.stdout),
            String::from_utf8_lossy(&output.stderr)
        );
    };
    let repository_path = repository.to_str().unwrap();
    run(&["extension", "repository", "init", repository_path]);
    run(&[
        "extension",
        "repository",
        "add",
        "python-local",
        "--directory",
        repository_path,
    ]);
    run(&[
        "extension",
        "repository",
        "publish",
        "python-local",
        "--bundle",
        bundle.to_str().unwrap(),
    ]);
    run(&[
        "extension",
        "install",
        "morphir-python",
        "--repository",
        "python-local",
    ]);
    fs::remove_dir_all(&repository).unwrap();
    run(&[
        "compile",
        "--language",
        "python",
        "--input",
        "src",
        "--output",
        "compiled",
    ]);
    run(&[
        "generate",
        "--target",
        "python",
        "--input",
        "compiled/morphir-ir.json",
        "--output",
        "generated",
    ]);
    assert!(project.join("generated/domain/models.py").is_file());
    assert!(project.join("generated/domain/rules.py").is_file());
    run(&[
        "compile",
        "--language",
        "python",
        "--input",
        "generated",
        "--output",
        "recompiled",
    ]);
    let read_ir = |directory: &str| -> serde_json::Value {
        serde_json::from_slice(&fs::read(project.join(directory).join("morphir-ir.json")).unwrap())
            .unwrap()
    };
    assert_eq!(read_ir("compiled"), read_ir("recompiled"));

    fs::write(project.join("morphir.toml"), "[workspace]\nmembers = ['packages/*']\ndefault_member = 'packages/toml'\n[frontend]\nlanguage = 'python'\n").unwrap();
    for (name, filename, config) in [
        (
            "toml",
            "morphir.toml",
            "[project]\nname = 'acme/toml'\nversion = '1.0.0'\nsource_directory = 'models'\nexposed_modules = ['domain.rules']\n",
        ),
        (
            "yaml",
            "morphir.yaml",
            "project:\n  name: acme/yaml\n  version: 1.0.0\n  source_directory: models\n  exposed_modules: [domain.rules]\n",
        ),
        (
            "json",
            "morphir.json",
            r#"{"name":"acme/json","sourceDirectory":"models","exposedModules":["domain.rules"]}"#,
        ),
    ] {
        let member = project.join("packages").join(name);
        fs::create_dir_all(member.join("models/domain")).unwrap();
        fs::copy(
            project.join("src/domain/models.py"),
            member.join("models/domain/models.py"),
        )
        .unwrap();
        fs::copy(
            project.join("src/domain/rules.py"),
            member.join("models/domain/rules.py"),
        )
        .unwrap();
        fs::write(member.join(filename), config).unwrap();
        let selected = format!("packages/{name}");
        let output_dir = format!("selected-{name}");
        let generated_dir = format!("workspace-generated-{name}");
        let overridden_dir = format!("overridden-{name}");
        run(&[
            "compile",
            "--project",
            &selected,
            "--language",
            "python",
            "--output",
            &output_dir,
        ]);
        let ir = read_ir(&output_dir);
        let library = &ir["distribution"]["Library"];
        assert_eq!(library["packageName"], format!("acme/{name}"));
        assert!(
            library["def"]["modules"]["domain/models"]
                .get("Private")
                .is_some()
        );
        assert!(
            library["def"]["modules"]["domain/rules"]
                .get("Public")
                .is_some()
        );
        tokio::runtime::Runtime::new().unwrap().block_on(async {
            use morphir::commands::ui::provider::{
                WorkspaceCapability, native::NativeWorkspaceProvider,
            };
            let provider = NativeWorkspaceProvider::discover_with_options(
                &project,
                "python-model",
                morphir_devkit::ConfigLoadOptions::project_only(),
            )
            .unwrap();
            let source = provider.initial_sources().pop().unwrap();
            let snapshot = provider.open(&source).await.unwrap();
            let id = &snapshot
                .projects
                .iter()
                .find(|item| item.relative_path == selected)
                .unwrap()
                .id;
            let model = provider.load_project_model(&source, id).await.unwrap();
            assert_eq!(
                serde_json::from_str::<serde_json::Value>(&model.content).unwrap(),
                ir
            );
        });
        run(&[
            "generate",
            "--project",
            &selected,
            "--target",
            "python",
            "--output",
            &generated_dir,
        ]);
        assert!(
            project
                .join(&generated_dir)
                .join("domain/models.py")
                .is_file()
        );
        run(&[
            "compile",
            "--project",
            &selected,
            "--language",
            "python",
            "--input",
            &generated_dir,
            "--package-name",
            "acme/override",
            "--output",
            &overridden_dir,
        ]);
        assert_eq!(
            read_ir(&overridden_dir)["distribution"]["Library"]["packageName"],
            "acme/override"
        );

        fs::write(
            member.join(filename),
            config.replace("domain.rules", "Missing"),
        )
        .unwrap();
        let failed = Command::new(env!("CARGO_BIN_EXE_morphir"))
            .args(["compile", "--project", &selected, "--language", "python"])
            .current_dir(&project)
            .env("MORPHIR_HOME", &home)
            .output()
            .unwrap();
        assert!(
            !failed.status.success(),
            "Unknown exposure was accepted for {filename}"
        );
        assert!(String::from_utf8_lossy(&failed.stderr).contains("unknown source module"));
        let private_config = config
            .replace("'domain.rules'", "")
            .replace("\"domain.rules\"", "")
            .replace("domain.rules", "");
        fs::write(member.join(filename), private_config).unwrap();
        let private_output = format!("all-private-{name}");
        run(&[
            "compile",
            "--project",
            &selected,
            "--language",
            "python",
            "--output",
            &private_output,
        ]);
        assert!(
            read_ir(&private_output)["distribution"]["Library"]["def"]["modules"]
                .as_object()
                .unwrap()
                .values()
                .all(|module| module.get("Private").is_some())
        );
        fs::write(member.join(filename), config).unwrap();
    }
    run(&["compile", "--output", "default-member"]);
    assert_eq!(
        read_ir("default-member")["distribution"]["Library"]["packageName"],
        "acme/toml"
    );
}
