use std::path::Path;
use std::process::{Command, Output};

fn cli(cwd: &Path, args: &[&str]) -> Output {
    Command::new(env!("CARGO_BIN_EXE_morphir"))
        .current_dir(cwd)
        .env("MORPHIR_LOG_FILE", "false")
        .env_remove("MORPHIR_OUT_DIR")
        .env_remove("MORPHIR_LOG_DIR")
        // Installed authoring gates must not discover Bun, Git or external validators.
        .env("PATH", "")
        .args(args)
        .output()
        .unwrap()
}

#[test]
fn embedded_source_and_vendored_schema_gates_work_without_other_tools() {
    let work = tempfile::tempdir().unwrap();
    let root = Path::new(env!("CARGO_MANIFEST_DIR")).join("../..");
    let source = root.join("spec/ir/mck");
    let embedded = cli(work.path(), &["mck", "schema", "check"]);
    assert!(
        embedded.status.success(),
        "{}",
        String::from_utf8_lossy(&embedded.stderr)
    );
    assert!(
        String::from_utf8_lossy(&embedded.stdout)
            .contains("183 ok, 13 rejected as expected, 0 failed, 0 skipped")
    );
    let raw = cli(
        work.path(),
        &["mck", "schema", "check", "--kit", source.to_str().unwrap()],
    );
    assert!(
        raw.status.success(),
        "{}",
        String::from_utf8_lossy(&raw.stderr)
    );
    assert_eq!(raw.stdout, embedded.stdout);
    let managed = work.path().join("managed");
    let vendor = cli(
        work.path(),
        &[
            "mck",
            "kit",
            "vendor",
            "--source",
            "embedded",
            "--dest",
            managed.to_str().unwrap(),
        ],
    );
    assert!(
        vendor.status.success(),
        "{}",
        String::from_utf8_lossy(&vendor.stderr)
    );
    let check = || {
        cli(
            work.path(),
            &["mck", "schema", "check", "--kit", managed.to_str().unwrap()],
        )
    };
    let vendored = check();
    assert!(
        vendored.status.success(),
        "{}",
        String::from_utf8_lossy(&vendored.stderr)
    );
    assert_eq!(vendored.stdout, embedded.stdout);
    let schema = managed.join("spec/mck/vocabulary.schema.json");
    std::fs::write(&schema, "{}").unwrap();
    let corrupt = check();
    assert_eq!(corrupt.status.code(), Some(1));
    assert!(String::from_utf8_lossy(&corrupt.stderr).contains("altered"));
}

#[test]
fn old_managed_lock_does_not_silently_gain_required_schema_inputs() {
    use morphir_mck::kit::embedded::embedded_source;
    use morphir_mck::kit::load_kit;
    use morphir_mck::kit::manifest::LockSource;
    use morphir_mck::kit::snapshot::collect;
    let work = tempfile::tempdir().unwrap();
    let old = work.path().join("old");
    let mut snapshot = collect(&load_kit(embedded_source()).unwrap()).unwrap();
    snapshot.files.remove("spec/mck/vocabulary.schema.json");
    let lock = snapshot.lock(LockSource::Local { revision: None });
    snapshot.write(&old, &lock).unwrap();
    let result = cli(
        work.path(),
        &["mck", "schema", "check", "--kit", old.to_str().unwrap()],
    );
    assert_eq!(result.status.code(), Some(1));
    assert!(String::from_utf8_lossy(&result.stderr).contains("vocabulary.schema.json"));
    assert!(!old.join("spec/mck/vocabulary.schema.json").exists());
}

#[test]
fn decimal_response_id_cannot_round_to_a_different_pending_request() {
    use morphir_mck::kit::embedded::embedded_source;
    use morphir_mck::kit::load_kit;
    use morphir_mck::kit::manifest::LockSource;
    use morphir_mck::kit::snapshot::collect;
    let work = tempfile::tempdir().unwrap();
    let root = work.path().join("kit");
    let mut snapshot = collect(&load_kit(embedded_source()).unwrap()).unwrap();
    let path = "spec/ir/mck/protocol.example.json";
    let text = std::str::from_utf8(&snapshot.files[path])
        .unwrap()
        .replacen("\"id\": 1", "\"id\": 9007199254740992", 1)
        .replacen("\"id\": 1", "\"id\": 9007199254740993.0", 1);
    snapshot.files.insert(path.into(), text.into_bytes());
    // Exercise a raw authoring kit so its edited protocol example reaches the gate.
    let lock = snapshot.lock(LockSource::Local { revision: None });
    snapshot.write(&root, &lock).unwrap();
    std::fs::remove_file(root.join("mck-kit.lock.json")).unwrap();
    let result = cli(
        work.path(),
        &[
            "mck",
            "schema",
            "check",
            "--kit",
            root.join("spec/ir/mck").to_str().unwrap(),
        ],
    );
    assert_eq!(result.status.code(), Some(1));
    assert!(String::from_utf8_lossy(&result.stdout).contains("does not answer"));
}
