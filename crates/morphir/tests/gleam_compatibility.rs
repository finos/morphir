//! Real CLI compilation, generation and incremental cache reuse for Gleam.
use serde_json::Value;
use std::{
    fs,
    path::{Path, PathBuf},
    process::{Command, Output},
};

fn run(project: &Path, home: &Path, args: &[&str]) -> Output {
    Command::new(env!("CARGO_BIN_EXE_morphir"))
        .args(args)
        .current_dir(project)
        .env("MORPHIR_HOME", home)
        .output()
        .unwrap()
}
fn success(output: Output) {
    assert!(
        output.status.success(),
        "stdout={}\nstderr={}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );
}
fn manifest(root: &Path, version: &str) -> Option<PathBuf> {
    for entry in fs::read_dir(root).unwrap() {
        let path = entry.unwrap().path();
        if path.file_name().unwrap() == "manifest.json" {
            let value: Value = serde_json::from_slice(&fs::read(&path).unwrap()).unwrap();
            if value["key"]["irVersion"] == version {
                return Some(path);
            }
        }
        if path.is_dir()
            && let Some(found) = manifest(&path, version)
        {
            return Some(found);
        }
    }
    None
}
#[test]
fn gleam_cli_compiles_both_versions_and_reuses_module_cache() {
    let temp = tempfile::tempdir().unwrap();
    let project = temp.path().join("project");
    let home = temp.path().join("home");
    fs::create_dir_all(project.join("src")).unwrap();
    fs::write(project.join("morphir.toml"), "[project]\nname = 'example/gleam'\nsource_directory = 'src'\n[frontend]\nlanguage = 'gleam'\n").unwrap();
    fs::write(
        project.join("src/model.gleam"),
        "pub type Customer { Customer(name: String) }\n",
    )
    .unwrap();
    fs::write(
        project.join("src/api.gleam"),
        "import model\npub type Alias = model.Customer\n",
    )
    .unwrap();
    for version in ["3", "4"] {
        let args = ["compile", "--ir-version", version, "--json"];
        success(run(&project, &home, &args));
        let ir: Value = serde_json::from_slice(
            &fs::read(project.join(".morphir/out/compile.dest/morphir-ir.json")).unwrap(),
        )
        .unwrap();
        assert_eq!(ir["formatVersion"].as_u64(), Some(version.parse().unwrap()));
        success(run(&project, &home, &args));
        let cached: Value = serde_json::from_slice(
            &fs::read(manifest(&project.join(".morphir/cache/compile"), version).unwrap()).unwrap(),
        )
        .unwrap();
        for name in ["api", "model"] {
            assert_eq!(cached["modules"][name]["status"], "unchanged");
        }
        success(run(
            &project,
            &home,
            &["generate", "--target", "gleam", "--json"],
        ));
        let generated =
            fs::read_to_string(project.join(".morphir/out/generate/gleam.dest/model.gleam"))
                .unwrap();
        assert!(generated.contains("Customer(name: String)"), "{generated}");
    }
}
