//! Selected artifact filesystem controls only. No Chromium, Page or UI is launched.
use super::super::super::adapter::execution_loans::{
    with_source_controller_artifact_control, with_source_controller_cleanup_control,
};
use super::super::source_inputs::SelectedRuntimePackage;
use super::*;

#[test]
#[ignore = "requires exact selected archive and Node executable; actual filesystem only"]
fn selected_runtime_materialization_01_full_actual_tree_then_driver_refusal_retains_and_cleans_outputs()
 {
    let archive = fs::read(
        std::env::var_os("MORPHIR_MCK_BROWSER_PLAYWRIGHT_ARCHIVE").expect("explicit archive"),
    )
    .unwrap();
    let node = PathBuf::from(
        std::env::var_os("MORPHIR_MCK_BROWSER_NODE").expect("explicit selected Node"),
    );
    let root = tempfile::tempdir().unwrap();
    let base = root.path().canonicalize().unwrap();
    let executable = base.join("literal-executable");
    fs::write(&executable, b"literal filesystem fixture, never executed").unwrap();
    fs::set_permissions(&executable, fs::Permissions::from_mode(0o700)).unwrap();
    fs::write(base.join("driver.mjs"), b"foreign driver must survive").unwrap();
    with_source_controller_artifact_control(|lifetime, loans| {
        let package = SelectedRuntimePackage::prepare(&archive, &lifetime, loans).unwrap();
        let input = SelectedControllerTargetInput {
            chromium: ControllerFileInput {
                path: &executable,
                byte_length: fs::metadata(&executable).unwrap().len(),
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
        .unwrap_or_else(|_| panic!("prepaid selected filesystem preparation"));
        let mut failure = prepared
            .acquire_selected(loans)
            .err()
            .expect("create-only driver refusal after materialization");
        assert!(matches!(
            failure.fault(),
            ControllerAcquisitionFault::Io(io::ErrorKind::AlreadyExists)
        ));
        let runtime = failure
            .runtime_materialization()
            .expect("actual runtime outcomes retained");
        assert_eq!(runtime.completed_files(), 115);
        assert_eq!(runtime.observed_eofs(), 115);
        for output in runtime.outputs() {
            assert_eq!(output.written_bytes(), output.declared_length());
            assert_eq!(output.readback_bytes(), output.declared_length());
            assert_eq!(output.stage(), runtime_sink::RuntimeOutputStage::Verified);
            if matches!(output.path(), "index.mjs" | "lib/coreBundle.js") {
                assert!(matches!(
                    output.disposal(),
                    runtime_sink::RuntimeOutputDisposal::Transferred
                ));
            } else {
                assert!(matches!(
                    output.disposal(),
                    runtime_sink::RuntimeOutputDisposal::Released(
                        runtime_sink::RuntimeClose::Returned
                    )
                ));
            }
        }
        for descriptor in runtime.files() {
            let bytes = fs::read(base.join("artifacts/runtime").join(descriptor.path())).unwrap();
            assert_eq!(bytes.len() as u64, descriptor.byte_length());
            assert_eq!(
                <[u8; 32]>::from(Sha256::digest(&bytes)),
                *descriptor.sha256()
            );
        }
        assert!(failure.cleanup_owned_entries().is_complete());
        assert!(!base.join("profile").exists());
        assert!(!base.join("artifacts").exists());
        assert_eq!(
            fs::read(base.join("driver.mjs")).unwrap(),
            b"foreign driver must survive"
        );
        assert!(base.is_dir());
        let cleaned = failure
            .finish_cleanup()
            .ok()
            .expect("actual handles consumed after cleanup");
        assert!(matches!(
            cleaned.release(),
            SourceFileRelease::HandlesReleasedUnverified { .. }
        ));
    });
}

#[test]
#[ignore = "requires exact selected archive; actual original-end partial filesystem control, no processes"]
fn selected_runtime_materialization_02_partial_actual_output_cleans_after_original_end() {
    let raw = fs::read(
        std::env::var_os("MORPHIR_MCK_BROWSER_PLAYWRIGHT_ARCHIVE").expect("explicit archive"),
    )
    .unwrap();
    let root = tempfile::tempdir().unwrap();
    let base = root.path().canonicalize().unwrap();
    let executable = base.join("literal-executable");
    fs::write(&executable, b"never executed").unwrap();
    fs::set_permissions(&executable, fs::Permissions::from_mode(0o700)).unwrap();
    with_source_controller_artifact_control(|lifetime, loans| {
        let package = SelectedRuntimePackage::prepare(&raw, &lifetime, loans).unwrap();
        let input = SelectedControllerTargetInput {
            chromium: ControllerFileInput {
                path: &executable,
                byte_length: 14,
            },
            node: ControllerFileInput {
                path: &executable,
                byte_length: 14,
            },
            root: &base,
        };
        let mut prepared = FundedControllerAcquisition::prepare_selected(
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
        .unwrap_or_else(|_| panic!("prepaid partial filesystem control"));
        // Exercise the production output owner at its actual handoff. This
        // does not acquire a selected Node/Chromium or construct a target.
        prepared.walk(4).unwrap();
        prepared.create(0).unwrap();
        prepared.create(1).unwrap();
        prepared
            .runtime
            .sink
            .start(
                prepared.partial.created_files[1].as_ref().unwrap(),
                &prepared.lifetime,
            )
            .unwrap();
        let RuntimeReaderState::Prepared(reader) =
            std::mem::replace(&mut prepared.runtime.reader, RuntimeReaderState::Moving)
        else {
            panic!("prepared reader")
        };
        let mut first = true;
        let result = reader.materialize(loans, |descriptor, source| {
            prepared
                .runtime
                .sink
                .write_entry(descriptor, source, &prepared.lifetime)?;
            if first {
                first = false;
                std::thread::sleep(
                    prepared
                        .lifetime
                        .end()
                        .saturating_duration_since(Instant::now()),
                );
            }
            Ok(())
        });
        let (package, read, sink) = result.into_parts();
        assert!(matches!(read,RuntimeArchiveReadTerminal::Incomplete{files:1,first:Some(super::super::source_inputs::RuntimeArchiveReadFault::Activity(super::super::super::adapter::execution_loans::BrowserActivityFault::OriginalEnd)),..}));
        prepared.runtime.reader = RuntimeReaderState::Observed {
            package,
            read,
            sink,
        };
        assert_eq!(prepared.runtime.sink.completed_files(), 1);
        assert_eq!(prepared.runtime.sink.observed_eofs(), 1);
        let mut failure = ControllerAcquisitionFailure {
            first: ControllerAcquisitionFault::Runtime,
            retained: prepared,
        };
        assert!(
            failure.cleanup_owned_entries().is_complete(),
            "cleanup is available after the original business end"
        );
        assert!(!base.join("profile").exists());
        assert!(!base.join("artifacts").exists());
        let cleaned = failure
            .finish_cleanup()
            .ok()
            .expect("actual partial handles released after entries retire");
        assert!(matches!(
            cleaned.fault(),
            ControllerAcquisitionFault::Runtime
        ));
        assert!(base.is_dir());
    });
}

#[test]
#[ignore = "requires exact selected archive; explicit low residual cleanup input, no filesystem acquisition"]
fn selected_runtime_materialization_03_known_cleanup_capacity_refuses_before_filesystem() {
    let raw = fs::read(
        std::env::var_os("MORPHIR_MCK_BROWSER_PLAYWRIGHT_ARCHIVE").expect("explicit archive"),
    )
    .unwrap();
    let root = tempfile::tempdir().unwrap();
    let base = root.path().canonicalize().unwrap();
    let literal = base.join("literal-never-opened");
    with_source_controller_cleanup_control(|lifetime, loans| {
        let package = SelectedRuntimePackage::prepare(&raw, &lifetime, loans).unwrap();
        let preparation = FundedControllerAcquisition::prepare_selected(
            SelectedControllerTargetInput {
                chromium: ControllerFileInput {
                    path: &literal,
                    byte_length: 1,
                },
                node: ControllerFileInput {
                    path: &literal,
                    byte_length: 1,
                },
                root: &base,
            },
            Limits {
                max_frame: 128,
                stderr_capture: 64,
                ..Limits::DEFAULT
            },
            lifetime,
            package,
            loans,
        );
        let failure = match preparation {
            Err(failure) => failure,
            Ok(prepared) => panic!(
                "known runtime entries require 533 cleanup slots; preparation admitted {}",
                prepared.descendants.as_ref().unwrap().capacity()
            ),
        };
        assert!(
            matches!(
                failure.fault(),
                ControllerAcquisitionFault::Cleanup(CleanupFault::Capacity)
            ),
            "{:#?}",
            failure.fault()
        );
        assert_eq!(failure.held_files(), 0);
        assert_eq!(failure.read_bytes(), 0);
        assert!(!base.join("profile").exists());
        assert!(!base.join("artifacts").exists());
        assert!(!base.join("driver.mjs").exists());
    });
}
