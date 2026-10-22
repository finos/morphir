//! Actual source-issued preparation and retained ownership, not a browser run.
use super::super::super::adapter::execution_loans::{
    with_foreign_source_controller_lifetime, with_source_controller_artifact_control,
    with_source_controller_end, with_source_controller_lifetime,
};
use super::*;
use std::time::{Duration, Instant};

fn nonexistent_files(root: &Path) -> BrowserControllerFiles<'_> {
    BrowserControllerFiles {
        chromium: BrowserControllerFile {
            path: root,
            byte_length: u64::MAX,
        },
        node: BrowserControllerFile {
            path: root,
            byte_length: u64::MAX,
        },
        root,
    }
}

#[test]
fn browser_source_facade_01_archive_refusal_preserves_unlaunched_owner() {
    let directory = tempfile::tempdir().unwrap();
    with_source_controller_lifetime(|preparation, loans| {
        let failure = match preparation.prepare_runtime(
            b"not the authenticated package",
            nonexistent_files(directory.path()),
            Limits::DEFAULT,
            loans,
        ) {
            Err(failure) => failure,
            Ok(_) => panic!("unselected archive cannot produce a materialized owner"),
        };
        assert_eq!(
            failure.stage(),
            BrowserControllerPreparationStage::RuntimeSelection
        );
        assert!(directory.path().read_dir().unwrap().next().is_none());
        let finished = failure
            .finish_cleanup()
            .ok()
            .expect("no physical owners were acquired");
        assert_eq!(
            finished.stage(),
            BrowserControllerPreparationStage::RuntimeSelection
        );
    });
}

#[test]
fn browser_source_facade_02_foreign_child_refuses_before_archive_or_path_effects() {
    let directory = tempfile::tempdir().unwrap();
    with_foreign_source_controller_lifetime(|preparation, loans| {
        let failure = match preparation.prepare_runtime(
            b"wrong length",
            nonexistent_files(directory.path()),
            Limits::DEFAULT,
            loans,
        ) {
            Err(failure) => failure,
            Ok(_) => panic!("foreign child cannot acquire a source runtime"),
        };
        assert_eq!(
            failure.input_error().unwrap().source_cause(),
            Some(super::super::super::adapter::BrowserSourceFault::ForeignSource)
        );
        assert!(directory.path().read_dir().unwrap().next().is_none());
        failure
            .finish_cleanup()
            .ok()
            .expect("owned retirement requires no foreign business grant");
    });
}

#[test]
fn browser_source_facade_03_original_end_refusal_keeps_cleanup_available() {
    let directory = tempfile::tempdir().unwrap();
    with_source_controller_end(Duration::from_millis(100), |preparation, loans| {
        std::thread::sleep(
            preparation.end().saturating_duration_since(Instant::now()) + Duration::from_millis(1),
        );
        let failure = match preparation.prepare_runtime(
            b"wrong length",
            nonexistent_files(directory.path()),
            Limits::DEFAULT,
            loans,
        ) {
            Err(failure) => failure,
            Ok(_) => panic!("the original end cannot be renewed by preparation"),
        };
        assert_eq!(
            failure.input_error().unwrap().activity_cause(),
            Some(super::super::super::adapter::execution_loans::BrowserActivityFault::OriginalEnd)
        );
        assert!(directory.path().read_dir().unwrap().next().is_none());
        failure
            .finish_cleanup()
            .ok()
            .expect("retirement after actual original end");
    });
}

#[test]
#[ignore = "requires exact selected archive/Node; actual materialization and revoked cleanup, no Chrome"]
fn browser_source_facade_04_actual_partial_files_cleanup_after_source_revocation() {
    let archive = fs::read(
        std::env::var_os("MORPHIR_MCK_BROWSER_PLAYWRIGHT_ARCHIVE")
            .expect("explicit selected archive"),
    )
    .unwrap();
    let node = PathBuf::from(
        std::env::var_os("MORPHIR_MCK_BROWSER_NODE").expect("explicit selected Node"),
    );
    let directory = tempfile::tempdir().unwrap();
    let root = directory.path().canonicalize().unwrap();
    let executable = root.join("literal-executable-never-launched");
    fs::write(&executable, b"literal fixture, not Chromium").unwrap();
    fs::set_permissions(&executable, fs::Permissions::from_mode(0o700)).unwrap();
    fs::write(root.join("driver.mjs"), b"foreign driver must survive").unwrap();
    let mut retained = None;
    with_source_controller_artifact_control(|preparation, loans| {
        let files = BrowserControllerFiles {
            chromium: BrowserControllerFile {
                path: &executable,
                byte_length: fs::metadata(&executable).unwrap().len(),
            },
            node: BrowserControllerFile {
                path: &node,
                byte_length: fs::metadata(&node).unwrap().len(),
            },
            root: &root,
        };
        let failure = match preparation.prepare_runtime(
            &archive,
            files,
            Limits {
                max_frame: 128,
                stderr_capture: 64,
                ..Limits::DEFAULT
            },
            loans,
        ) {
            Err(failure) => failure,
            Ok(_) => panic!("create-only foreign driver must refuse after actual runtime writes"),
        };
        assert_eq!(
            failure.stage(),
            BrowserControllerPreparationStage::Acquisition
        );
        assert!(root.join("artifacts/runtime/index.mjs").is_file());
        retained = Some(failure);
    }); // The genuine issuing child is revoked by this existing fixture.
    let finished = retained
        .unwrap()
        .finish_cleanup()
        .ok()
        .expect("actual owned cleanup is independent of fresh source business permission");
    assert_eq!(
        finished.stage(),
        BrowserControllerPreparationStage::Acquisition
    );
    assert!(!root.join("artifacts").exists());
    assert!(!root.join("profile").exists());
    assert_eq!(
        fs::read(root.join("driver.mjs")).unwrap(),
        b"foreign driver must survive"
    );
    assert!(root.is_dir());
}

#[test]
#[ignore = "requires selected archive/Node; real missing-cwd prechild refusal, no Chrome"]
fn browser_source_facade_05_materialized_spawn_refusal_preserves_actual_owned_tree() {
    use super::super::super::adapter::execution_loans::{
        ExecutionChild, controlled_clients, with_compiled_artifact_control,
    };
    use super::super::super::source_scope::BrowserSourceScope;
    use super::super::super::{
        BrowserDocumentBounds, BrowserRowCollection, PreparedBrowserClientRun,
    };
    let archive = fs::read(
        std::env::var_os("MORPHIR_MCK_BROWSER_PLAYWRIGHT_ARCHIVE").expect("explicit archive"),
    )
    .unwrap();
    let node = PathBuf::from(std::env::var_os("MORPHIR_MCK_BROWSER_NODE").expect("explicit Node"));
    let directory = tempfile::tempdir().unwrap();
    let base = directory.path().canonicalize().unwrap();
    let root = base.join("owned-cwd");
    let moved = base.join("moved-owned-cwd");
    fs::create_dir(&root).unwrap();
    with_compiled_artifact_control(|compiled, inner| {
        let core = controlled_clients(compiled)[0];
        let global = BrowserSourceScope::prepare(inner).unwrap();
        let child = ExecutionChild::prepare(&global, inner).unwrap();
        let run = PreparedBrowserClientRun::prepare(core, &global, &child, inner).unwrap();
        let mut loans = BrowserLoans::execution(inner, &global, &child).unwrap();
        let source = run.openings(&mut loans).unwrap().next().unwrap();
        let stimulus = run.prepare_controlled_host(&source, &mut loans).unwrap();
        let mut collection = BrowserRowCollection::prepare(
            &run,
            &mut loans,
            BrowserDocumentBounds::new(2, 1024, 512).unwrap(),
        )
        .unwrap();
        let mut producer = collection
            .producer()
            .issue(&run, &source, &mut loans)
            .unwrap();
        let transcript = producer
            .prepare_host_transcript(
                &mut loans,
                &stimulus,
                Instant::now() + Duration::from_secs(10),
            )
            .unwrap();
        let action = run.next_action(&mut loans).unwrap().unwrap();
        let (owned, preparation) = action
            .prepare_connected_controller(&producer, &transcript, &stimulus, &mut loans)
            .unwrap_or_else(|_| panic!("genuine source0 factory"));
        let sdk = owned
            .connected_opening(&producer, &transcript, &stimulus, &mut loans)
            .unwrap();
        let files = BrowserControllerFiles {
            chromium: BrowserControllerFile {
                path: Path::new("/bin/sleep"),
                byte_length: fs::metadata("/bin/sleep").unwrap().len(),
            },
            node: BrowserControllerFile {
                path: &node,
                byte_length: fs::metadata(&node).unwrap().len(),
            },
            root: &root,
        };
        let materialized = preparation
            .prepare_runtime(
                &archive,
                files,
                Limits {
                    max_frame: 128,
                    stderr_capture: 64,
                    ..Limits::DEFAULT
                },
                &mut loans,
            )
            .unwrap_or_else(|cause| panic!("actual materialized tree: {cause:?}"));
        fs::rename(&root, &moved).unwrap();
        let failure = match materialized.launch(
            "http://127.0.0.1:1/launch?token=AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
            &sdk,
            &mut loans,
        ) {
            Err(failure) => failure,
            Ok(_) => panic!("genuinely missing cwd cannot create a child"),
        };
        assert_eq!(failure.stage(), BrowserControllerLaunchStage::PreChildSpawn);
        assert_eq!(
            failure.spawn_error().unwrap().kind(),
            std::io::ErrorKind::NotFound
        );
        assert!(moved.join("artifacts/runtime/index.mjs").is_file());
        failure
            .finish_cleanup()
            .ok()
            .expect("actual unlaunched files can be consumed through retained parent FD");
        assert!(!moved.join("artifacts").exists());
        assert!(!moved.join("profile").exists());
        assert!(!moved.join("driver.mjs").exists());
        assert!(moved.is_dir());
        fs::rename(&moved, &root).unwrap();
    });
}

#[test]
#[ignore = "requires selected archive/Node; full115 and actual scoped gate, no Chrome"]
fn browser_source_facade_06_full_runtime_step_survives_unreserved_storage_exhaustion() {
    use super::super::super::adapter::execution_loans::{
        BrowserControllerDispatch, BrowserControllerStepDispatcher, BrowserPreparedControllerStep,
        ExecutionChild, controlled_clients, with_compiled_artifact_control,
    };
    use super::super::super::source_scope::BrowserSourceScope;
    use super::super::super::{
        BrowserDocumentBounds, BrowserRowCollection, PreparedBrowserClientRun,
    };
    let archive = fs::read(
        std::env::var_os("MORPHIR_MCK_BROWSER_PLAYWRIGHT_ARCHIVE").expect("explicit archive"),
    )
    .unwrap();
    let node = PathBuf::from(std::env::var_os("MORPHIR_MCK_BROWSER_NODE").expect("explicit Node"));
    let directory = tempfile::tempdir().unwrap();
    let root = directory.path().canonicalize().unwrap();
    with_compiled_artifact_control(|compiled, inner| {
        let core = controlled_clients(compiled)[0];
        let global = BrowserSourceScope::prepare(inner).unwrap();
        let child = ExecutionChild::prepare(&global, inner).unwrap();
        let run = PreparedBrowserClientRun::prepare(core, &global, &child, inner).unwrap();
        let mut loans = BrowserLoans::execution(inner, &global, &child).unwrap();
        let source = run.openings(&mut loans).unwrap().next().unwrap();
        let stimulus = run.prepare_controlled_host(&source, &mut loans).unwrap();
        let mut collection = BrowserRowCollection::prepare(
            &run,
            &mut loans,
            BrowserDocumentBounds::new(2, 1024, 512).unwrap(),
        )
        .unwrap();
        let mut producer = collection
            .producer()
            .issue(&run, &source, &mut loans)
            .unwrap();
        let transcript = producer
            .prepare_host_transcript(
                &mut loans,
                &stimulus,
                Instant::now() + Duration::from_secs(10),
            )
            .unwrap();
        let action = run.next_action(&mut loans).unwrap().unwrap();
        let (owned, preparation) = action
            .prepare_connected_controller(&producer, &transcript, &stimulus, &mut loans)
            .unwrap_or_else(|_| panic!("genuine source0 factory"));
        let sdk = owned
            .connected_opening(&producer, &transcript, &stimulus, &mut loans)
            .unwrap();
        let mut materialized = preparation
            .prepare_runtime(
                &archive,
                BrowserControllerFiles {
                    chromium: BrowserControllerFile {
                        path: Path::new("/bin/sleep"),
                        byte_length: fs::metadata("/bin/sleep").unwrap().len(),
                    },
                    node: BrowserControllerFile {
                        path: &node,
                        byte_length: fs::metadata(&node).unwrap().len(),
                    },
                    root: &root,
                },
                Limits {
                    max_frame: 128,
                    stderr_capture: 64,
                    ..Limits::DEFAULT
                },
                &mut loans,
            )
            .unwrap_or_else(|cause| panic!("actual complete runtime preparation: {cause:?}"));
        assert!(root.join("artifacts/runtime/index.mjs").is_file());
        let (_, lifetime, _, _) = materialized.target.launch_parts();
        let available = loans.remaining_cleanup_resources(lifetime).unwrap();
        // Consume only the SAME owner's unreserved remainder after actual
        // preparation. No pool is enlarged or refilled and no cleanup capacity
        // is invented. Later work must use its earlier owned reservation.
        loans
            .reserve_controlled_host_storage(available.retained_bytes, 0, 0)
            .unwrap();
        struct MatchingOnly<'a> {
            lifetime: &'a BrowserControllerPreparation,
            matched: &'a mut bool,
        }
        impl BrowserControllerStepDispatcher for MatchingOnly<'_> {
            fn dispatch(
                &mut self,
                permit: BrowserPreparedControllerStep<'_>,
            ) -> BrowserControllerDispatch {
                *self.matched = permit.matches_lifetime(self.lifetime);
                // This exercises the actual scoped gate without performing a
                // browser effect or inventing a successful controller reply.
                BrowserControllerDispatch::NativeRefused
            }
        }
        let mut matched = false;
        let step = match materialized.take_dispatch_credit(&loans) {
            Err(cause) => Err(cause),
            Ok(credit) => {
                let (_, lifetime, _, _) = materialized.target.launch_parts();
                let mut dispatcher = MatchingOnly {
                    lifetime,
                    matched: &mut matched,
                };
                sdk.with_prepaid_controller_step(credit, &loans, &mut dispatcher)
            }
        };
        // Always finish the actual owned filesystem path before the assertion,
        // including the genuine old per-call funding refusal in the RED run.
        let finished = materialized
            .finish_cleanup()
            .ok()
            .expect("prepaid owned cleanup remains possible after business refusal");
        let retirement = finished.retirement();
        assert!(!root.join("profile").exists());
        assert!(!root.join("artifacts").exists());
        assert!(!root.join("driver.mjs").exists());
        assert!(root.is_dir());
        assert_eq!(retirement, BrowserControllerRetirement::Returned);
        assert!(
            step.is_ok(),
            "scoped step cannot ask for fresh storage: {step:?}"
        );
        assert!(
            matched,
            "scoped permit belongs to the actual materialized lifetime"
        );
    });
}
