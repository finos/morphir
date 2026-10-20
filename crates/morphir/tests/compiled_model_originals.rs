//! A genuine compiler writer declares its complete original inventory.
use std::{
    fs,
    process::{Command, Output, Stdio},
    time::{Duration, Instant},
};

fn compile(root: &std::path::Path) -> Output {
    struct Child(Option<std::process::Child>);
    impl Drop for Child {
        fn drop(&mut self) {
            if let Some(child) = &mut self.0 {
                let _ = child.kill();
                let _ = child.wait();
            }
        }
    }
    let mut child = Child(Some(
        Command::new(env!("CARGO_BIN_EXE_morphir"))
            .args(["compile", "--json"])
            .current_dir(root)
            .env("MORPHIR_HOME", root.join("home"))
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .spawn()
            .unwrap(),
    ));
    let deadline = Instant::now() + Duration::from_secs(60);
    loop {
        if child.0.as_mut().unwrap().try_wait().unwrap().is_some() {
            return child.0.take().unwrap().wait_with_output().unwrap();
        }
        assert!(
            Instant::now() < deadline,
            "actual compile exceeded its test deadline"
        );
        std::thread::sleep(Duration::from_millis(10));
    }
}

#[test]
fn actual_yaml_compile_declares_complete_primary_and_captures_exact_original_bytes() {
    let temp = tempfile::tempdir().unwrap();
    let root = temp.path();
    fs::create_dir(root.join("models")).unwrap();
    fs::write(root.join("morphir.toml"),"[project]\nname='acme/originals'\nversion='1.0.0'\nsource_directory='models'\nexposed_modules=['api']\n[frontend]\nlanguage='gleam'\n[ir]\nlayout='single-file'\nformat='yaml'\n").unwrap();
    fs::write(
        root.join("models/api.gleam"),
        "pub type Answer { Answer }\n",
    )
    .unwrap();
    let result = compile(root);
    assert!(
        result.status.success(),
        "{}",
        String::from_utf8_lossy(&result.stderr)
    );
    let record: serde_json::Value =
        serde_json::from_slice(&fs::read(root.join(".morphir/out/compile.json")).unwrap()).unwrap();
    assert_eq!(
        record["morphirModelOriginals"],
        serde_json::json!({"contractVersion":"0.1.0-draft.1","companions":[]}),
        "completeness must come from the real writer's positive policy"
    );
    use morphir::commands::ui::model_originals::{
        CaptureControl, CaptureScope, SelectedModule, capture_compiled,
    };
    let output =
        cap_std::fs::Dir::open_ambient_dir(root.join(".morphir/out"), cap_std::ambient_authority())
            .unwrap();
    let capture = capture_compiled(
        &output,
        &SelectedModule::parse("").unwrap(),
        CaptureScope::Complete,
        &CaptureControl::new(),
    )
    .unwrap()
    .ready()
    .expect("the real writer declared complete coverage");
    assert_eq!(capture.companions().len(), 0);
    assert_eq!(capture.primary().path().as_str(), "morphir-ir.yaml");
    let original = fs::read(root.join(".morphir/out/compile.dest/morphir-ir.yaml")).unwrap();
    assert_eq!(
        capture.file_bytes(capture.primary().path()).unwrap(),
        original
    );
}
