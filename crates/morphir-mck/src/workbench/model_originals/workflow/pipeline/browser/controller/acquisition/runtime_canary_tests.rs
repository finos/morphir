//! Diagnostic Node-only import of the actual selected materialized package.
//! No Chromium, Page, source action or browser qualification is performed.
use super::super::super::adapter::execution_loans::with_source_controller_artifact_control;
use super::super::source_inputs::SelectedRuntimePackage;
use super::*;
use crate::transport::process::{CommandSpec, OneShotProcess, ProcessFinish, ProcessProgress};
use std::{
    ffi::OsString,
    time::{Duration, Instant},
};

fn import_selected(node: &Path, root: &Path, environment: Vec<(OsString, OsString)>) {
    // Literal diagnostic, not source/driver input: only the actual selected
    // package entry path is an argument. It never launches a browser.
    let spec = CommandSpec::new(node.to_path_buf(),vec![
        "--input-type=module".into(),"--eval".into(),
        "const {pathToFileURL}=await import('node:url');await import(pathToFileURL(process.argv[1]).href);".into(),
        root.join("artifacts/runtime/index.mjs").into_os_string(),
    ],root.to_path_buf(),environment).unwrap();
    let mut process = OneShotProcess::spawn(
        spec,
        Limits {
            max_frame: 4096,
            stderr_capture: 4096,
            ..Limits::DEFAULT
        },
    )
    .unwrap();
    let deadline = Instant::now() + Duration::from_secs(10);
    let mut terminated = false;
    loop {
        match process.advance() {
            ProcessProgress::Finished(_) => break,
            ProcessProgress::ExitObserved(_) => {
                process.reap_retained().unwrap();
            }
            ProcessProgress::Faulted(cause) => {
                panic!("actual selected import process fault: {cause:?}")
            }
            ProcessProgress::Working => {}
        }
        if Instant::now() >= deadline && !terminated {
            process.request_termination().unwrap();
            terminated = true;
        }
        assert!(
            Instant::now() < deadline + Duration::from_secs(2),
            "actual import failed to finish after termination"
        );
        std::thread::sleep(Duration::from_millis(1));
    }
    let ProcessFinish::Finished(actual) = process.into_finished() else {
        panic!("actual direct child/readers must finish")
    };
    assert!(
        !terminated,
        "actual import exceeded its diagnostic deadline"
    );
    assert!(actual.first_fault().is_none());
    assert!(
        actual.status().success(),
        "actual import stderr: {}",
        String::from_utf8_lossy(actual.stderr())
    );
}

#[test]
#[ignore = "requires exact selected archive and Node; actual Node import only, no Chromium"]
fn selected_runtime_materialization_02_source_environment_excludes_outside_optional_module_canary()
{
    let archive = fs::read(
        std::env::var_os("MORPHIR_MCK_BROWSER_PLAYWRIGHT_ARCHIVE")
            .expect("explicit selected archive"),
    )
    .unwrap();
    let node = PathBuf::from(
        std::env::var_os("MORPHIR_MCK_BROWSER_NODE").expect("explicit selected Node"),
    );
    let root = tempfile::tempdir().unwrap();
    let base = root.path().canonicalize().unwrap();
    let chromium_fixture = base.join("literal-executable");
    fs::write(
        &chromium_fixture,
        b"literal filesystem fixture, never executed",
    )
    .unwrap();
    fs::set_permissions(&chromium_fixture, fs::Permissions::from_mode(0o700)).unwrap();
    fs::write(base.join("driver.mjs"), b"foreign driver must survive").unwrap();
    with_source_controller_artifact_control(|lifetime, loans| {
        let package = SelectedRuntimePackage::prepare(&archive, &lifetime, loans).unwrap();
        let input = SelectedControllerTargetInput {
            chromium: ControllerFileInput {
                path: &chromium_fixture,
                byte_length: fs::metadata(&chromium_fixture).unwrap().len(),
            },
            node: ControllerFileInput {
                path: &node,
                byte_length: fs::metadata(&node).unwrap().len(),
            },
            root: &base,
        };
        let prepared = FundedControllerAcquisition::prepare_selected(
            input,
            Limits {
                max_frame: 128,
                stderr_capture: 64,
                ..Limits::DEFAULT
            },
            lifetime,
            package,
            loans,
        )
        .unwrap_or_else(|_| panic!("selected filesystem preparation"));
        let mut failure = prepared
            .acquire_selected(loans)
            .err()
            .expect("foreign driver refuses after full runtime materialization");
        assert_eq!(
            failure.runtime_materialization().unwrap().completed_files(),
            115
        );
        // This deliberately unselected ancestor module is test-owned. Its
        // execution proves Node's real fallback lookup, never package trust.
        let outside = base.join("node_modules/bufferutil");
        fs::create_dir_all(&outside).unwrap();
        let marker = base.join("outside-bufferutil-was-loaded");
        let marker_literal = serde_json::to_string(marker.to_str().unwrap()).unwrap();
        fs::write(outside.join("index.js"),format!("require('node:fs').writeFileSync({marker_literal},'outside');module.exports={{}};\n")).unwrap();
        import_selected(&node, &base, vec![]);
        assert_eq!(
            fs::read(&marker).unwrap(),
            b"outside",
            "absent-flags control must exercise actual optional-module lookup"
        );
        fs::remove_file(&marker).unwrap();
        import_selected(
            &node,
            &base,
            super::super::source_operation::source_driver_environment(),
        );
        let selected_lookup_refused = !marker.exists();
        // Complete actual cleanup before the assertion, including the
        // deliberate failing RED. Outside/foreign test-owned files remain.
        assert!(failure.cleanup_owned_entries().is_complete());
        assert!(!base.join("artifacts").exists());
        assert!(outside.join("index.js").is_file());
        assert_eq!(
            fs::read(base.join("driver.mjs")).unwrap(),
            b"foreign driver must survive"
        );
        let cleaned = failure
            .finish_cleanup()
            .ok()
            .expect("actual owned handles consumed");
        assert!(matches!(
            cleaned.release(),
            SourceFileRelease::HandlesReleasedUnverified { .. }
        ));
        assert!(
            selected_lookup_refused,
            "maintained source-specific environment allowed unselected bufferutil execution"
        );
    });
}
