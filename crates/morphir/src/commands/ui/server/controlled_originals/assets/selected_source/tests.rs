//! Native retained-image controls; no Page, browser launch, or qualification.
use super::super::*;
use super::*;
use morphir_mck::workbench::{RunConfiguration, load, with_prepared_browser_clients};
use std::time::{Duration, Instant};

const SELECTED_COMMIT: &str = "a42427debd0f5b3d484446e22670d2527469a538";
const SELECTED_TREE: &str = "bd397354331a208523805f0a02a955e2594891c7";
fn table_digest() -> [u8; 32] {
    let text = "a2b2441928a3b61c85ec60033931feb9ad6ccb2bfacd90e670b428d0af557b24";
    std::array::from_fn(|index| u8::from_str_radix(&text[index * 2..index * 2 + 2], 16).unwrap())
}
fn with_image_loans(snapshot_read_bytes: u64, action: impl FnOnce(&mut BrowserLoans<'_, '_>)) {
    let root = tempfile::tempdir().unwrap();
    std::fs::write(
        root.path().join("cases.json"),
        include_str!(concat!(
            env!("CARGO_MANIFEST_DIR"),
            "/../morphir-mck/src/workbench/model_originals/workflow/pipeline_controls/cases.json"
        )),
    )
    .unwrap();
    let checker: serde_json::Value = serde_json::from_str(include_str!(concat!(env!("CARGO_MANIFEST_DIR"), "/../morphir-mck/src/workbench/model_originals/workflow/pipeline_controls/explicit-test-policy.json"))).unwrap();
    let configuration = RunConfiguration::from_json(&serde_json::json!({
        "kind":"model-originals-browser","browser":"chromium","checker":checker,
        "receiving":{"retainedBytes":67108864,"stdoutPrefixBytes":0,"stderrPrefixBytes":0,"snapshotReadBytes":snapshot_read_bytes,"byteVisits":268435456,"records":0}
    }).to_string()).unwrap();
    let corpus = load(root.path()).unwrap();
    let outcome = with_prepared_browser_clients(&corpus, &configuration, |_, loans| {
        action(loans);
        Ok::<_, BrowserInputError>(())
    })
    .unwrap();
    outcome.into_parts().0.unwrap();
}
#[test]
fn browser_selected_source_01_selected_labels_do_not_authenticate_a_different_image() {
    let root = tempfile::tempdir().unwrap();
    let bodies: [(&str, &[u8]); 3] = [
        ("index.html", b"<!doctype html><div id=\"app\"></div>"),
        (
            "observed-bootstrap.js",
            b"import './product-observer.js';\n",
        ),
        ("product-observer.js", b"export const unrelated = true;\n"),
    ];
    for (path, body) in bodies {
        std::fs::write(root.path().join(path), body).unwrap();
    }
    let files: Vec<_> = bodies
        .iter()
        .map(|(path, body)| ApplicationFile {
            path,
            bytes: body.len(),
            sha256: Sha256::digest(body).into(),
        })
        .collect();
    let held =
        cap_std::fs::Dir::open_ambient_dir(root.path(), cap_std::ambient_authority()).unwrap();
    let acquired = AcquiredObservedWorkbench {
        root: &held,
        manifest: ApplicationManifest {
            source: ApplicationSource {
                commit: SELECTED_COMMIT,
                tree: SELECTED_TREE,
                build_manifest_sha256: table_digest(),
            },
            files: &files,
        },
    };
    with_image_loans(1048576, |loans| {
        let end = Instant::now() + Duration::from_secs(30);
        let application = RunObservedApplication::prepare(&acquired, loans, end).unwrap();
        let failure =
            SelectedSourceApplication::prepare(&application, &acquired.manifest, loans, end)
                .err()
                .expect("labels cannot select unrelated bytes");
        assert!(matches!(failure, SelectedSourceFault::SelectedManifest));
    });
}

#[test]
#[ignore = "requires exact explicit a424 complete77 input image; no browser/source0 qualification"]
fn browser_selected_source_02_actual_selected77_complete_image_and_forged_table_refusal() {
    let root = std::path::PathBuf::from(
        std::env::var_os("MORPHIR_MCK_SELECTED_UI_IMAGE")
            .expect("explicit exact a424 selected image required"),
    );
    let receipt = std::fs::read(root.join("receipt.json")).unwrap();
    let receipt_hash = Sha256::digest(&receipt)
        .iter()
        .map(|byte| format!("{byte:02x}"))
        .collect::<String>();
    assert_eq!(
        receipt_hash,
        "8b746507f3a58c9902a3e2f8c4f521f224693c088a6255f14e427d51784e2c7e"
    );
    let table = std::fs::read_to_string(root.join("assets.tsv")).unwrap();
    assert_eq!(
        <[u8; 32]>::from(Sha256::digest(table.as_bytes())),
        table_digest()
    );
    let files: Vec<_> = table
        .lines()
        .map(|line| {
            let mut fields = line.split('\t');
            let path = fields.next().unwrap();
            let bytes = fields.next().unwrap().parse().unwrap();
            let sha = fields.next().unwrap();
            assert!(fields.next().is_none());
            assert_eq!(sha.len(), 64);
            let sha256 = std::array::from_fn(|index| {
                u8::from_str_radix(&sha[index * 2..index * 2 + 2], 16).unwrap()
            });
            ApplicationFile {
                path,
                bytes,
                sha256,
            }
        })
        .collect();
    assert_eq!(files.len(), 77);
    assert_eq!(
        files.iter().map(|file| file.bytes).sum::<usize>(),
        15_392_100
    );
    let held = cap_std::fs::Dir::open_ambient_dir(root.join("files"), cap_std::ambient_authority())
        .unwrap();
    let acquired = AcquiredObservedWorkbench {
        root: &held,
        manifest: ApplicationManifest {
            source: ApplicationSource {
                commit: SELECTED_COMMIT,
                tree: SELECTED_TREE,
                build_manifest_sha256: table_digest(),
            },
            files: &files,
        },
    };
    // This explicit actual-image INPUT pays its complete 15.39MiB acquisition
    // and EOF probes. The ordinary tiny fixture retains its 1MiB read limit;
    // production defaults and source/case grants are unchanged.
    with_image_loans(32 * 1024 * 1024, |loans| {
        let original_end = Instant::now() + Duration::from_secs(30);
        let application = RunObservedApplication::prepare(&acquired, loans, original_end).unwrap();
        let selected = SelectedSourceApplication::prepare(
            &application,
            &acquired.manifest,
            loans,
            original_end,
        )
        .unwrap();
        assert!(Arc::ptr_eq(&selected.image, &application.image));
        assert_eq!(selected.end, original_end);
        assert_eq!(selected.image.raw.len(), 15_392_100);
        let mut wrong_files: Vec<_> = files
            .iter()
            .map(|file| ApplicationFile {
                path: file.path,
                bytes: file.bytes,
                sha256: file.sha256,
            })
            .collect();
        wrong_files[0].sha256[0] ^= 1;
        let wrong = ApplicationManifest {
            source: ApplicationSource {
                commit: SELECTED_COMMIT,
                tree: SELECTED_TREE,
                build_manifest_sha256: table_digest(),
            },
            files: &wrong_files,
        };
        assert!(matches!(
            SelectedSourceApplication::prepare(&application, &wrong, loans, original_end),
            Err(SelectedSourceFault::SelectedManifest)
        ));
        assert!(
            loans
                .reserve_controlled_host_storage(usize::MAX, 0, 0)
                .is_err()
        );
        assert!(matches!(
            SelectedSourceApplication::prepare(
                &application,
                &acquired.manifest,
                loans,
                original_end
            ),
            Err(SelectedSourceFault::Assets(ObservedAssetsFault::Funding(_)))
        ));
    });
}

#[test]
#[ignore = "requires exact explicit selected77 image; native source association only, no Page"]
fn browser_selected_source_03_genuine_row_same_host_original_end_and_recoverable_refusal() {
    use super::super::super::{ControlledHostFinish, ControlledHostJoined};
    use crate::commands::ui::server::controlled_originals_tests::runtime;
    use morphir_mck::workbench::{
        BrowserAdapterCompletion, BrowserDocumentBounds, with_executed_browser_originals,
    };
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
                commit: SELECTED_COMMIT,
                tree: SELECTED_TREE,
                build_manifest_sha256: table_digest(),
            },
            files: &files,
        },
    };
    let directory = tempfile::tempdir().unwrap();
    std::fs::write(
        directory.path().join("cases.json"),
        include_bytes!(concat!(
            env!("CARGO_MANIFEST_DIR"),
            "/../morphir-mck/src/workbench/model_originals/workflow/pipeline_controls/cases.json"
        )),
    )
    .unwrap();
    let checker:serde_json::Value = serde_json::from_slice(include_bytes!(concat!(env!("CARGO_MANIFEST_DIR"),"/../morphir-mck/src/workbench/model_originals/workflow/pipeline_controls/explicit-test-policy.json"))).unwrap();
    let configuration = RunConfiguration::from_json(&serde_json::json!({
        "kind":"model-originals-browser","browser":"chromium","checker":checker,
        "receiving":{"retainedBytes":67108864,"stdoutPrefixBytes":0,"stderrPrefixBytes":0,"snapshotReadBytes":33554432,"byteVisits":536870912,"records":1024}
    }).to_string()).unwrap();
    let corpus = load(directory.path()).unwrap();
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
            let original_end = Instant::now() + Duration::from_secs(30);
            let application =
                RunObservedApplication::prepare(&acquired, loans, original_end).unwrap();
            let selected_short = SelectedSourceApplication::prepare(
                &application,
                &acquired.manifest,
                loans,
                original_end - Duration::from_secs(1),
            )
            .unwrap();
            let limits = ingress::DocumentIngressLimits {
                observation_owners: 4,
                observation_events: 8,
                records: 2,
                journal_bytes: 4096,
                frame_bytes: 1024,
                socket_tasks: 6,
                request_tickets: 16,
                request_header_fields: 32,
                request_header_bytes: 1024,
            };
            let host = runtime
                .block_on(BoundControlledUiHost::bind_with_engine_observed_document(
                    stimulus,
                    &application,
                    loans,
                    limits,
                    endpoint,
                    original_end,
                ))
                .unwrap();
            let original_host = Arc::as_ptr(&host.state);
            let sdk = action
                .connected_opening(
                    host.document_producer.as_ref().unwrap(),
                    host.state.transcript.as_ref().unwrap(),
                    &host.state.source,
                    loans,
                )
                .unwrap();
            let refused = selected_short
                .into_launch(host, &application, sdk, loans)
                .err()
                .expect("short component end is not SAME host end");
            let (fault, selected_short, host, sdk) = refused.into_parts();
            assert!(matches!(fault, SelectedSourceFault::OriginalEnd));
            assert_eq!(
                Arc::as_ptr(&host.state),
                original_host,
                "actual host returned, no cloned surrogate"
            );
            assert!(Arc::ptr_eq(&selected_short.image, &application.image));
            drop(selected_short);
            let selected = SelectedSourceApplication::prepare(
                &application,
                &acquired.manifest,
                loans,
                original_end,
            )
            .unwrap();
            let launch = selected
                .into_launch(host, &application, sdk, loans)
                .unwrap_or_else(|_| panic!("actual SAME image/entry/child/journal/end"));
            assert_eq!(Arc::as_ptr(&launch.owner.host.state), original_host);
            assert!(Arc::ptr_eq(
                &launch.owner.application.image,
                &application.image
            ));
            assert_eq!(launch.owner.host.state.end, original_end);
            assert_eq!(launch.owner.application.end, original_end);
            assert!(matches!(
                launch.owner.host.state.assets.as_ref().unwrap().entry,
                EntryPreparation::Prepared
            ));
            // Prepared entry bytes do not prove an unused listener. Start the
            // SAME actual listener, then require a recoverable refusal rather
            // than granting source0 a host that could already have served it.
            let SelectedSourceLaunch { owner, opening } = launch;
            let SelectedSourceHost {
                mut host,
                application: selected,
            } = owner;
            runtime.block_on(async { host.start() }).unwrap();
            let was_running = matches!(
                host.listener,
                super::super::super::ListenerOwner::Running { .. }
            );
            let (refusal, host, selected, opening) =
                match selected.into_launch(host, &application, opening, loans) {
                    Ok(launch) => (
                        None,
                        launch.owner.host,
                        launch.owner.application,
                        launch.opening,
                    ),
                    Err(failure) => {
                        let (fault, selected, host, opening) = failure.into_parts();
                        (Some(fault), host, selected, opening)
                    }
                };
            let returned_host = Arc::as_ptr(&host.state);
            let returned_image = Arc::ptr_eq(&selected.image, &application.image);
            // Always join the real running listener before assertions, even
            // when the regression is RED and association wrongly succeeded.
            drop(opening);
            drop(selected);
            let joined = runtime.block_on(host.finish_joined());
            assert!(was_running);
            assert_eq!(returned_host, original_host);
            assert!(returned_image);
            assert!(matches!(
                joined,
                ControlledHostFinish::Joined(ControlledHostJoined::Clean)
            ));
            assert!(matches!(refusal, Some(SelectedSourceFault::HostEntry)));
            Err::<(), _>("native association only; source0 was not executed")
        },
        |inventory| {
            assert_eq!(inventory.rows().len(), 23);
            assert_eq!(inventory.first_failed_row(), Some(0));
            assert!(matches!(
                inventory.rows()[0].attempt().unwrap().callback(),
                BrowserAdapterCompletion::Returned(Err(
                    "native association only; source0 was not executed"
                ))
            ));
            assert!(!inventory.rows()[0].attempt().unwrap().collection_complete());
        },
    )
    .unwrap();
    assert_eq!(callbacks, 1);
}
