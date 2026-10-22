//! Actual native/physical ownership on a real pre-child spawn refusal.
//! No Page, listener start, source0 settlement or qualification is produced.
use super::*;
use crate::commands::ui::server::controlled_originals::{
    ControlledHostFinish, ControlledHostJoined, HostState, ListenerOwner,
};
use morphir_mck::transport::Limits;
use morphir_mck::workbench::{
    BrowserActionCursorTerminal, BrowserAdapterCompletion, BrowserControllerFile,
    BrowserControllerFiles, BrowserControllerLaunchStage, BrowserControllerRetirement,
    BrowserDocumentBounds, RunConfiguration, load, with_executed_browser_originals,
};
use std::{path::Path, time::Duration};

struct NativeCleanupFacts {
    same_host: bool,
    same_image: bool,
    was_bound: bool,
    joined: ControlledHostFinish,
}

fn finish_native(
    native: SelectedSourcePrepared<'_>,
    runtime: &tokio::runtime::Runtime,
    original_host: *const HostState,
    application: &RunObservedApplication,
) -> NativeCleanupFacts {
    let SelectedSourcePrepared {
        launch,
        runtime: retained_runtime,
    } = native;
    let same_host = Arc::as_ptr(&launch.owner.host.state) == original_host;
    let same_image = Arc::ptr_eq(&launch.owner.application.image, &application.image);
    let was_bound = matches!(launch.owner.host.listener, ListenerOwner::Bound(_));
    drop(launch.opening);
    let joined = runtime.block_on(launch.owner.host.finish_joined());
    drop(launch.owner.application);
    // This actual retained Handle remains owned through the native join.
    drop(retained_runtime);
    NativeCleanupFacts {
        same_host,
        same_image,
        was_bound,
        joined,
    }
}

fn assert_native_cleanup(facts: NativeCleanupFacts) {
    assert!(facts.same_host);
    assert!(facts.same_image);
    assert!(
        facts.was_bound,
        "spawn refusal must leave the listener unserved"
    );
    assert!(matches!(
        facts.joined,
        ControlledHostFinish::Joined(ControlledHostJoined::Clean)
    ));
}

#[test]
#[ignore = "requires selected77 image/archive/Node; actual missing-cwd refusal, no Chrome"]
fn native_selected_controller_composition_09_spawn_refusal_retains_all_actual_owners() {
    use crate::commands::ui::server::controlled_originals_tests::runtime;
    const CONTROL_ONLY: &str = "native composition refusal only; source0 was not executed";
    let input = std::path::PathBuf::from(
        std::env::var_os("MORPHIR_MCK_SELECTED_UI_IMAGE").expect("explicit selected77 image"),
    );
    let table = std::fs::read_to_string(input.join("assets.tsv")).unwrap();
    let files: Vec<_> = table
        .lines()
        .map(|line| {
            let mut fields = line.split('\t');
            let path = fields.next().unwrap();
            let bytes = fields.next().unwrap().parse().unwrap();
            let hash = fields.next().unwrap();
            assert!(fields.next().is_none());
            let sha256 =
                std::array::from_fn(|i| u8::from_str_radix(&hash[i * 2..i * 2 + 2], 16).unwrap());
            ApplicationFile {
                path,
                bytes,
                sha256,
            }
        })
        .collect();
    let held =
        cap_std::fs::Dir::open_ambient_dir(input.join("files"), cap_std::ambient_authority())
            .unwrap();
    let acquired = AcquiredObservedWorkbench {
        root: &held,
        manifest: ApplicationManifest {
            source: ApplicationSource {
                commit: std::str::from_utf8(SELECTED_COMMIT).unwrap(),
                tree: std::str::from_utf8(SELECTED_TREE).unwrap(),
                build_manifest_sha256: SELECTED_TABLE,
            },
            files: &files,
        },
    };
    let archive = std::fs::read(
        std::env::var_os("MORPHIR_MCK_BROWSER_PLAYWRIGHT_ARCHIVE").expect("explicit archive"),
    )
    .unwrap();
    let node = std::path::PathBuf::from(
        std::env::var_os("MORPHIR_MCK_BROWSER_NODE").expect("explicit selected Node"),
    );
    let node_bytes = std::fs::metadata(&node).unwrap().len();
    let chromium_bytes = std::fs::metadata("/bin/sleep").unwrap().len();
    let directory = tempfile::tempdir().unwrap();
    let base = directory.path().canonicalize().unwrap();
    let cwd = base.join("owned-cwd");
    let moved = base.join("moved-owned-cwd");
    std::fs::create_dir(&cwd).unwrap();
    std::fs::write(
        base.join("cases.json"),
        include_bytes!(concat!(
            env!("CARGO_MANIFEST_DIR"),
            "/../morphir-mck/src/workbench/model_originals/workflow/pipeline_controls/cases.json"
        )),
    )
    .unwrap();
    let mut checker: serde_json::Value = serde_json::from_slice(include_bytes!(concat!(
        env!("CARGO_MANIFEST_DIR"),
        "/../morphir-mck/src/workbench/model_originals/workflow/pipeline_controls/explicit-test-policy.json"
    )))
    .unwrap();
    // Existing explicit artifact-control INPUT only. The ordinary native8
    // fixture/defaults stay unchanged; actual full115 costs exceed one GiB.
    checker["decode"]["byteVisits"] = serde_json::json!(34_359_738_368u64);
    let configuration = RunConfiguration::from_json(
        &serde_json::json!({
            "kind":"model-originals-browser","browser":"chromium","checker":checker,
            "receiving":{
                "retainedBytes":67_108_864u64,"stdoutPrefixBytes":4096,"stderrPrefixBytes":4096,
                "snapshotReadBytes":33_554_432u64,"byteVisits":34_359_738_368u64,"records":1024
            }
        })
        .to_string(),
    )
    .unwrap();
    let corpus = load(&base).unwrap();
    let runtime = runtime();
    let mut callbacks = 0;
    with_executed_browser_originals(
        &corpus,
        &configuration,
        BrowserDocumentBounds::new(2, 4096, 1024).unwrap(),
        |run, loans, producer| {
            callbacks += 1;
            let action = run.next_action(loans).unwrap().unwrap();
            let opening = run.openings(loans).unwrap().next().unwrap();
            let endpoint = producer.issue(run, &opening, loans).unwrap();
            let stimulus = run.prepare_controlled_host(&opening, loans).unwrap();
            let application_end = Instant::now() + Duration::from_secs(30);
            let application =
                RunObservedApplication::prepare(&acquired, loans, application_end).unwrap();
            let original_end = (Instant::now() + Duration::from_secs(30)).min(application.end);
            let selected = SelectedSourceApplication::prepare(
                &application,
                &acquired.manifest,
                loans,
                original_end,
            )
            .unwrap();
            let host = runtime
                .block_on(BoundControlledUiHost::bind_with_engine_observed_document(
                    stimulus,
                    &application,
                    loans,
                    ingress::DocumentIngressLimits {
                        observation_owners: 4,
                        observation_events: 8,
                        records: 2,
                        journal_bytes: 4096,
                        frame_bytes: 1024,
                        socket_tasks: 6,
                        request_tickets: 16,
                        request_header_fields: 32,
                        request_header_bytes: 1024,
                    },
                    endpoint,
                    original_end,
                ))
                .unwrap();
            let original_host = Arc::as_ptr(&host.state);
            let (owned, preparation) = action
                .prepare_connected_controller(
                    host.document_producer.as_ref().unwrap(),
                    host.state.transcript.as_ref().unwrap(),
                    &host.state.source,
                    loans,
                )
                .unwrap_or_else(|_| panic!("genuine source0 owned preparation"));
            let sdk = owned
                .connected_opening(
                    host.document_producer.as_ref().unwrap(),
                    host.state.transcript.as_ref().unwrap(),
                    &host.state.source,
                    loans,
                )
                .unwrap();
            let launch = selected
                .into_launch(host, &application, sdk, loans)
                .unwrap_or_else(|_| panic!("SAME selected image/source/host/end"));
            // Retain the actual runtime and native wrapper costs BEFORE the
            // physical preparation chooses residual cleanup capacity.
            let prepared = runtime
                .block_on(async { launch.prepare_native_runtime(loans) })
                .unwrap_or_else(|_| panic!("actual pre-acquisition native runtime retention"));
            let materialized = match preparation.prepare_runtime(
                &archive,
                BrowserControllerFiles {
                    chromium: BrowserControllerFile {
                        path: Path::new("/bin/sleep"),
                        byte_length: chromium_bytes,
                    },
                    node: BrowserControllerFile {
                        path: &node,
                        byte_length: node_bytes,
                    },
                    root: &cwd,
                },
                Limits {
                    max_frame: 128,
                    stderr_capture: 64,
                    ..Limits::DEFAULT
                },
                loans,
            ) {
                Ok(materialized) => materialized,
                Err(failure) => {
                    let detail = format!("{failure:?}");
                    let cleanup = failure.finish_cleanup();
                    let native = finish_native(prepared, &runtime, original_host, &application);
                    assert_native_cleanup(native);
                    assert!(
                        cleanup.is_ok(),
                        "actual preparation refusal cleanup incomplete"
                    );
                    panic!("actual full115 setup refused under unchanged64MiB input: {detail}");
                }
            };
            let staged = match prepared.prepare_controller_launch(materialized, loans) {
                Ok(staged) => staged,
                Err(SelectedSourceControllerPreparationFailure {
                    native,
                    materialized,
                    cause,
                }) => {
                    let cleanup = materialized.finish_cleanup();
                    let native = finish_native(native, &runtime, original_host, &application);
                    assert_native_cleanup(native);
                    assert!(cleanup.is_ok(), "actual staging refusal cleanup incomplete");
                    panic!("actual listener-credit staging refused: {cause:?}");
                }
            };
            let runtime_was_present = cwd.join("artifacts/runtime/index.mjs").is_file();
            // The genuine current-directory path disappears while the SAME
            // owned directory FD/files survive. No replacement executable or
            // wrapper is invoked, and no process can start from this cwd.
            std::fs::rename(&cwd, &moved).unwrap();
            match staged.launch_controller(loans) {
                Err(SelectedSourceControllerLaunchFailure::Physical {
                    native,
                    listener_credit,
                    mut controller,
                }) => {
                    let stage = controller.stage();
                    let spawn = controller.spawn_error().map(std::io::Error::kind);
                    let retained_runtime_file = moved.join("artifacts/runtime/index.mjs").is_file();
                    controller.request_shutdown();
                    while !controller.poll_cleanup() && Instant::now() < original_end {
                        std::thread::sleep(Duration::from_millis(1));
                    }
                    let physical = controller.finish_cleanup();
                    let native = finish_native(native, &runtime, original_host, &application);
                    let renamed_back = std::fs::rename(&moved, &cwd);
                    // Keep the actual moved credit through both teardowns.
                    drop(listener_credit);
                    assert!(physical.is_ok(), "actual physical cleanup incomplete");
                    assert_native_cleanup(native);
                    assert!(renamed_back.is_ok());
                    assert_eq!(stage, BrowserControllerLaunchStage::PreChildSpawn);
                    assert_eq!(spawn, Some(std::io::ErrorKind::NotFound));
                    assert!(runtime_was_present && retained_runtime_file);
                    assert!(!cwd.join("artifacts").exists());
                    assert!(!cwd.join("profile").exists());
                    assert!(!cwd.join("driver.mjs").exists());
                    assert!(cwd.is_dir());
                    assert!(matches!(
                        physical.unwrap().retirement(),
                        BrowserControllerRetirement::Returned
                    ));
                }
                Err(SelectedSourceControllerLaunchFailure::BeforeSpawn { staged, cause }) => {
                    let SelectedSourceControllerPrepared {
                        native,
                        materialized,
                        listener_credit,
                    } = staged;
                    let cleanup = materialized.finish_cleanup();
                    let native = finish_native(native, &runtime, original_host, &application);
                    let renamed_back = std::fs::rename(&moved, &cwd);
                    drop(listener_credit);
                    assert!(
                        cleanup.is_ok(),
                        "actual pre-spawn refusal cleanup incomplete"
                    );
                    assert_native_cleanup(native);
                    assert!(renamed_back.is_ok());
                    panic!("target physical spawn refusal was not reached: {cause:?}");
                }
                Ok(SelectedSourceControllerLaunched {
                    native,
                    listener_credit,
                    mut controller,
                }) => {
                    controller.request_shutdown();
                    while !controller.poll_cleanup() && Instant::now() < original_end {
                        std::thread::sleep(Duration::from_millis(1));
                    }
                    let physical = controller.finish();
                    let native = finish_native(native, &runtime, original_host, &application);
                    let renamed_back = std::fs::rename(&moved, &cwd);
                    drop(listener_credit);
                    assert!(
                        physical.is_ok(),
                        "unexpected actual controller teardown incomplete"
                    );
                    assert_native_cleanup(native);
                    assert!(renamed_back.is_ok());
                    panic!("genuinely missing cwd must never create a controller");
                }
            }
            assert!(matches!(
                run.actions_terminal(),
                BrowserActionCursorTerminal::Incomplete {
                    consumed: 0,
                    pending: Some(0),
                    ..
                }
            ));
            Err::<(), _>(CONTROL_ONLY)
        },
        |inventory| {
            assert_eq!(inventory.rows().len(), 23);
            assert_eq!(inventory.first_failed_row(), Some(0));
            assert!(matches!(
                inventory.rows()[0].attempt().unwrap().callback(),
                BrowserAdapterCompletion::Returned(Err(CONTROL_ONLY))
            ));
            assert!(!inventory.rows()[0].attempt().unwrap().collection_complete());
        },
    )
    .unwrap();
    assert_eq!(callbacks, 1);
}
