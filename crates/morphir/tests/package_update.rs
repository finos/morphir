//! Real-process acceptance for authenticated scoped updates.
use std::path::Path;
use std::process::{Command, Output};

fn morphir(directory: &Path, args: &[&str]) -> Output {
    Command::new(env!("CARGO_BIN_EXE_morphir"))
        .current_dir(directory)
        .env("MORPHIR_HOME", directory.join("home"))
        .env("MORPHIR_LOG_FILE", "false")
        .env_remove("MORPHIR_LOG_DIR")
        .env_remove("MORPHIR_OUT_DIR")
        .arg("--no-banner")
        .args(args)
        .output()
        .expect("Morphir runs")
}

#[test]
fn package_update_help_describes_previous_lock_targets_and_new_output() {
    let workspace = tempfile::tempdir().unwrap();
    let output = morphir(workspace.path(), &["package", "update", "--help"]);
    assert!(
        output.status.success(),
        "{}",
        String::from_utf8_lossy(&output.stderr)
    );
    let help = String::from_utf8(output.stdout).unwrap();
    for flag in [
        "--lock",
        "--target",
        "--policy",
        "--registry",
        "--state",
        "--output",
        "--assurance",
    ] {
        assert!(help.contains(flag), "{help}");
    }
    assert!(
        !help.contains("--root"),
        "root comes from the previous lock: {help}"
    );
}

#[test]
fn malformed_update_targets_are_rejected_before_opening_inputs() {
    let workspace = tempfile::tempdir().unwrap();
    for target in [
        "../escape",
        "example.com/finance/eligibility@latest",
        "example.com/finance/eligibility@1.2.0@1.3.0",
        "",
    ] {
        let output = morphir(
            workspace.path(),
            &[
                "package",
                "update",
                "--lock",
                "absent.lock",
                "--target",
                target,
                "--policy",
                "absent.json",
                "--registry",
                "absent",
                "--state",
                "state",
                "--output",
                "new.lock",
                "--assurance",
                "portable",
            ],
        );
        assert_eq!(output.status.code(), Some(2));
        let error = String::from_utf8_lossy(&output.stderr);
        assert!(
            error.contains("invalid value") && error.contains("--target"),
            "{error}"
        );
        assert!(!workspace.path().join("state").exists());
        assert!(!workspace.path().join("new.lock").exists());
    }
}

#[test]
fn update_requires_explicit_targets_and_portable_assurance() {
    let workspace = tempfile::tempdir().unwrap();
    let args = [
        "package",
        "update",
        "--lock",
        "absent.lock",
        "--policy",
        "absent.json",
        "--registry",
        "absent",
        "--state",
        "state",
        "--output",
        "new.lock",
        "--assurance",
        "portable",
    ];
    let output = morphir(workspace.path(), &args);
    assert_eq!(output.status.code(), Some(2));
    assert!(String::from_utf8_lossy(&output.stderr).contains("--target"));
    let mut args = args.to_vec();
    *args.last_mut().unwrap() = "hardened";
    args.extend(["--target", "example.com/finance/eligibility"]);
    let output = morphir(workspace.path(), &args);
    assert_eq!(output.status.code(), Some(2));
    let error = String::from_utf8_lossy(&output.stderr);
    assert!(
        error.contains("hardened") && error.contains("portable"),
        "{error}"
    );
    assert!(!workspace.path().join("state").exists());
    assert!(!workspace.path().join("new.lock").exists());
}

#[path = "../../morphir-mck/tests/support/package_update.rs"]
#[allow(dead_code)]
mod fixture;
use fixture::mvp;

fn source() -> std::path::PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR")).join("../..")
}

fn success(output: Output) -> serde_json::Value {
    assert!(
        output.status.success(),
        "{}",
        String::from_utf8_lossy(&output.stderr)
    );
    serde_json::from_slice(&output.stdout).expect("one JSON result")
}

fn initialize(directory: &Path, prepared: &mvp::Prepared) {
    success(morphir(
        directory,
        &[
            "package",
            "trust",
            "init",
            "--policy",
            prepared.initialization_policy.to_str().unwrap(),
            "--root",
            prepared.root.to_str().unwrap(),
            "--state",
            prepared.state.to_str().unwrap(),
            "--json",
        ],
    ));
}

fn update(directory: &Path, prepared: &fixture::Prepared, output: &Path) -> Output {
    let p = &prepared.restore;
    let mut args = vec![
        "package",
        "update",
        "--lock",
        p.lock.to_str().unwrap(),
        "--policy",
        p.policy.to_str().unwrap(),
        "--registry",
        p.registry.to_str().unwrap(),
        "--state",
        p.state.to_str().unwrap(),
        "--output",
        output.to_str().unwrap(),
        "--assurance",
        "portable",
        "--json",
    ];
    for target in &prepared.targets {
        args.extend(["--target", target]);
    }
    morphir(directory, &args)
}

fn restore(directory: &Path, prepared: &mvp::Prepared, lock: &Path, output: &Path) -> Output {
    morphir(
        directory,
        &[
            "package",
            "restore",
            "--lock",
            lock.to_str().unwrap(),
            "--policy",
            prepared.policy.to_str().unwrap(),
            "--registry",
            prepared.registry.to_str().unwrap(),
            "--state",
            prepared.state.to_str().unwrap(),
            "--output",
            output.to_str().unwrap(),
            "--assurance",
            "portable",
            "--json",
        ],
    )
}

fn inventory(root: &Path) -> std::collections::BTreeMap<std::path::PathBuf, Vec<u8>> {
    walkdir::WalkDir::new(root)
        .into_iter()
        .map(Result::unwrap)
        .filter(|entry| entry.file_type().is_file())
        .map(|entry| {
            (
                entry.path().strip_prefix(root).unwrap().to_owned(),
                std::fs::read(entry.path()).unwrap(),
            )
        })
        .collect()
}

#[test]
fn fixed_update_cases_preserve_input_lock_and_registry_and_publish_only_complete_locks() {
    let source = source();
    let corpus = fixture::load(&source);
    assert_eq!(corpus.profile, mvp::PROFILE);
    for case in &corpus.cases {
        let workspace = tempfile::tempdir().unwrap();
        let prepared = fixture::prepare(&source, workspace.path(), case);
        let before = inventory(&prepared.restore.registry);
        let old_lock = std::fs::read(&prepared.restore.lock).unwrap();
        let prior_output = std::fs::read(&prepared.output).ok();
        if prepared.restore.initialize {
            initialize(workspace.path(), &prepared.restore);
        }
        fixture::after_initialize(case, &prepared);
        let result = update(workspace.path(), &prepared, &prepared.output);
        match case.expected {
            fixture::Expected::Updated => {
                let report = success(result);
                assert_eq!(report["profile"], "local-library-mvp");
                assert_eq!(report["profileVersion"], "0.1.0-draft.1");
                assert_eq!(
                    report["packages"].as_array().unwrap().len(),
                    4,
                    "{}",
                    case.id
                );
                let expected = std::fs::read(
                    source
                        .join(fixture::PATH)
                        .join("signed")
                        .join(case.expected_lock.as_ref().unwrap()),
                )
                .unwrap();
                assert_eq!(
                    std::fs::read(&prepared.output).unwrap(),
                    expected,
                    "{}",
                    case.id
                );
                // A full lock that cannot restore its selected frozen nodes is not successful delivery.
                let restored = success(restore(
                    workspace.path(),
                    &prepared.restore,
                    &prepared.output,
                    &prepared.restore.output,
                ));
                assert_eq!(restored["packages"], report["packages"], "{}", case.id);
            }
            fixture::Expected::Refused => {
                let text = String::from_utf8_lossy(&result.stderr)
                    .replace(['│', '×'], " ")
                    .split_whitespace()
                    .collect::<Vec<_>>()
                    .join(" ");
                assert_eq!(
                    result.status.code(),
                    Some(case.exit_code),
                    "{}: {text}",
                    case.id
                );
                assert!(
                    text.contains(case.diagnostic.as_ref().unwrap()),
                    "{}: {text}",
                    case.id
                );
                assert_eq!(
                    std::fs::read(&prepared.output).ok(),
                    prior_output,
                    "{} published or altered a lock",
                    case.id
                );
            }
        }
        assert_eq!(
            std::fs::read(&prepared.restore.lock).unwrap(),
            old_lock,
            "{} changed old lock",
            case.id
        );
        assert_eq!(
            inventory(&prepared.restore.registry),
            before,
            "{} changed registry",
            case.id
        );
    }
}

#[test]
fn updated_lock_is_deterministic_consumable_and_never_replaces_the_original() {
    let source = source();
    let corpus = fixture::load(&source);
    let case = corpus
        .cases
        .iter()
        .find(|case| case.expected == fixture::Expected::Updated)
        .unwrap();
    let workspace = tempfile::tempdir().unwrap();
    let prepared = fixture::prepare(&source, workspace.path(), case);
    let old_lock = std::fs::read(&prepared.restore.lock).unwrap();
    initialize(workspace.path(), &prepared.restore);
    success(update(workspace.path(), &prepared, &prepared.output));
    let expected = std::fs::read(&prepared.output).unwrap();
    let second = workspace.path().join("consumer/second.lock");
    success(update(workspace.path(), &prepared, &second));
    assert_eq!(std::fs::read(second).unwrap(), expected);
    let refusal = update(workspace.path(), &prepared, &prepared.restore.lock);
    assert!(!refusal.status.success());
    assert_eq!(std::fs::read(&prepared.restore.lock).unwrap(), old_lock);
    success(restore(
        workspace.path(),
        &prepared.restore,
        &prepared.output,
        &prepared.restore.output,
    ));
    let consumer = workspace.path().join("consumer");
    std::fs::write(
        consumer.join("morphir.toml"),
        "[project]\nname = \"examples/library-consumer\"\nversion = \"0.1.0\"\n",
    )
    .unwrap();
    let provider = prepared
        .restore
        .output
        .join("example.com/finance/eligibility/1.3.0/ir.json");
    success(morphir(
        &consumer,
        &[
            "gleam",
            "--json",
            "generate",
            "--input",
            provider.to_str().unwrap(),
            "--output",
            "generated",
        ],
    ));
    assert_eq!(
        std::fs::read(consumer.join("generated/decision.gleam")).unwrap(),
        std::fs::read(source.join(mvp::PATH).join("expected/decision.gleam")).unwrap()
    );
    let compiled = success(morphir(
        &consumer,
        &[
            "gleam",
            "--json",
            "compile",
            "--input",
            "generated",
            "--output",
            "compiled",
        ],
    ));
    assert_eq!(compiled["success"], true);
    assert_eq!(
        compiled["ir"]["distribution"]["Library"]["packageName"],
        "examples/library-consumer"
    );
    assert_eq!(std::fs::read(&prepared.output).unwrap(), expected);
    assert_eq!(std::fs::read(&prepared.restore.lock).unwrap(), old_lock);
}

#[test]
fn failed_update_remains_blocked_in_a_new_process_after_package_bytes_are_repaired() {
    let source = source();
    let corpus = fixture::load(&source);
    let case = corpus
        .cases
        .iter()
        .find(|case| {
            case.setup == fixture::Setup::Fresh && case.expected == fixture::Expected::Updated
        })
        .unwrap();
    let workspace = tempfile::tempdir().unwrap();
    let prepared = fixture::prepare(&source, workspace.path(), case);
    let before = inventory(&prepared.restore.registry);
    let old_lock = std::fs::read(&prepared.restore.lock).unwrap();
    let expected: serde_json::Value =
        serde_json::from_slice(&std::fs::read(source.join(fixture::EXPECTED_LOCK)).unwrap())
            .unwrap();
    let acquisition = expected["acquisitions"]
        .as_array()
        .unwrap()
        .iter()
        .find(|a| a["release"]["packagePath"] == fixture::TARGET)
        .unwrap();
    let payload = prepared
        .restore
        .registry
        .join(acquisition["source"]["path"].as_str().unwrap())
        .join("ir.json");
    let original = std::fs::read(&payload).unwrap();
    let mut corrupt = original.clone();
    corrupt.push(b'\n');
    std::fs::write(&payload, corrupt).unwrap();
    initialize(workspace.path(), &prepared.restore);
    let output = update(workspace.path(), &prepared, &prepared.output);
    assert!(!output.status.success());
    assert!(String::from_utf8_lossy(&output.stderr).contains("content digest mismatch"));
    assert!(!prepared.output.exists());
    std::fs::write(&payload, original).unwrap();
    assert_eq!(inventory(&prepared.restore.registry), before);
    let output = update(workspace.path(), &prepared, &prepared.output);
    assert!(!output.status.success());
    assert!(String::from_utf8_lossy(&output.stderr).contains("unresolved prior operation"));
    assert!(!prepared.output.exists());
    assert_eq!(std::fs::read(&prepared.restore.lock).unwrap(), old_lock);
}
