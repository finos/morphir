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
}
