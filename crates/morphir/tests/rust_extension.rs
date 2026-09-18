//! Publish, install and use the Rust release bundle through the CLI.

use std::{fs, path::PathBuf, process::Command};

#[test]
#[ignore = "requires MORPHIR_RUST_BUNDLE pointing to a packaged Rust WASM guest"]
fn rust_bundle_compiles_and_generates_offline_in_both_ir_versions() {
    let bundle = PathBuf::from(
        std::env::var_os("MORPHIR_RUST_BUNDLE").expect("build the Rust release bundle first"),
    )
    .canonicalize()
    .unwrap();
    let root = tempfile::tempdir().unwrap();
    let project = root.path().join("project");
    let home = root.path().join("home");
    let repository = root.path().join("repository");
    fs::create_dir_all(project.join("src")).unwrap();
    fs::write(
        project.join("morphir.toml"),
        "[project]\nname = 'acme/example'\nversion = '0.1.0'\nsource_directory = 'src'\n\
         [frontend]\nlanguage = 'rust'\nemit_parse_stage = false\n\
         [ir]\nformat_version = 3\n",
    )
    .unwrap();
    fs::write(
        project.join("src/models.rs"),
        r#"
pub enum Decision { Accept(i64), Reject }
pub type Pair = (i64, bool);
pub fn positive(value: i64) -> bool { value > 0 }
pub fn compute(decision: Decision, limit: i64) -> i64 {
    let above = |value: i64| -> bool { value > limit };
    match decision {
        Decision::Accept(value) => if above(value) { value } else { limit },
        Decision::Reject => 0,
    }
}
"#,
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
        "rust-local",
        "--directory",
        repository_path,
    ]);
    run(&[
        "extension",
        "repository",
        "publish",
        "rust-local",
        "--bundle",
        bundle.to_str().unwrap(),
    ]);
    run(&[
        "extension",
        "install",
        "morphir-rust",
        "--repository",
        "rust-local",
    ]);
    // Both providers must activate from Morphir Home after the repository is gone.
    fs::remove_dir_all(&repository).unwrap();
    for version in [3, 4] {
        let compiled = format!("compiled-v{version}");
        let generated = format!("generated-v{version}");
        if version == 3 {
            run(&["compile", "--output", &compiled]);
        } else {
            // The CLI flag overrides the project's v3 setting.
            run(&["compile", "--ir-version", "4", "--output", &compiled]);
        }
        let ir: serde_json::Value = serde_json::from_slice(
            &fs::read(project.join(&compiled).join("morphir-ir.json")).unwrap(),
        )
        .unwrap();
        assert_eq!(ir["formatVersion"], version);
        run(&["generate", "--target", "rust", "--output", &generated]);
        let generated_source = fs::read_to_string(project.join(&generated).join("lib.rs")).unwrap();
        let consumer = project.join(format!("consumer_v{version}.rs"));
        fs::write(
            &consumer,
            format!(
                "{generated_source}\n{}",
                r#"
fn main() {
    let pair: models::Pair = (42, true);
    assert_eq!(pair, (42, true));
    assert!(models::positive(1));
    assert!(!models::positive(0));
    assert_eq!(models::compute(models::Decision::Accept(12), 10), 12);
    assert_eq!(models::compute(models::Decision::Accept(8), 10), 10);
    assert_eq!(models::compute(models::Decision::Reject, 10), 0);
}
"#
            ),
        )
        .unwrap();
        let executable = project.join(format!(
            "consumer_v{version}{}",
            std::env::consts::EXE_SUFFIX
        ));
        let compiled = Command::new("rustc")
            .args(["--edition", "2024"])
            .arg(&consumer)
            .arg("-o")
            .arg(&executable)
            .output()
            .unwrap();
        assert!(
            compiled.status.success(),
            "v{version}: {}",
            String::from_utf8_lossy(&compiled.stderr)
        );
        assert!(Command::new(executable).status().unwrap().success());
    }
}
