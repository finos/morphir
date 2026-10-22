//! Existing actual registry owner, with explicitly funded fixed table backing.
//! No browser or host-source qualification is established by these controls.
use super::*;
use morphir_mck::workbench::{BrowserLoans, RunConfiguration, load, with_prepared_browser_clients};

fn with_loans<R>(run: impl FnOnce(&mut BrowserLoans<'_, '_>) -> R) -> R {
    let root = tempfile::tempdir().unwrap();
    std::fs::write(
        root.path().join("cases.json"),
        include_str!(concat!(
            env!("CARGO_MANIFEST_DIR"),
            "/../morphir-mck/src/workbench/model_originals/workflow/pipeline_controls/cases.json"
        )),
    )
    .unwrap();
    let checker: serde_json::Value = serde_json::from_str(include_str!(concat!(env!("CARGO_MANIFEST_DIR"),"/../morphir-mck/src/workbench/model_originals/workflow/pipeline_controls/explicit-test-policy.json"))).unwrap();
    let configuration = RunConfiguration::from_json(&serde_json::json!({
        "kind":"model-originals-browser","browser":"chromium","checker":checker,
        "receiving":{"retainedBytes":8388608,"stdoutPrefixBytes":0,"stderrPrefixBytes":0,"snapshotReadBytes":0,"byteVisits":8388608,"records":0}
    }).to_string()).unwrap();
    let source = load(root.path()).unwrap();
    with_prepared_browser_clients(&source, &configuration, |_, loans| Ok::<_, ()>(run(loans)))
        .unwrap()
        .into_parts()
        .0
        .unwrap()
}

#[test]
fn browser_fixed_socket_01_zero_and_overflow_refuse_before_task_admission() {
    with_loans(|loans| {
        assert_eq!(
            SocketTaskRegistry::fixed_requested_bytes(0),
            Err(SocketCleanupError::Capacity)
        );
        assert_eq!(
            SocketTaskRegistry::fixed_requested_bytes(usize::MAX),
            Err(SocketCleanupError::SizeOverflow)
        );
        let capacity = HostModelCaptureCapacity::metadata_only(loans, 0).unwrap();
        let result = SocketTaskRegistry::new_fixed(&capacity, 1, loans);
        assert!(matches!(
            result,
            Err(FixedSocketSetupFault::Registry(
                SocketCleanupError::Capacity
            ))
        ));
        assert_eq!(capacity.usage().metadata_bytes(), 0);
    });
}

#[test]
fn browser_fixed_socket_02_full_refuses_before_spawn_with_same_actual_handle() {
    let runtime = tokio::runtime::Builder::new_multi_thread()
        .worker_threads(2)
        .enable_all()
        .build()
        .unwrap();
    with_loans(|loans| {
        runtime.block_on(async {
            let bytes = SocketTaskRegistry::fixed_requested_bytes(1).unwrap();
            let capacity = HostModelCaptureCapacity::metadata_only(loans, bytes).unwrap();
            let (registry, mut owner) = SocketTaskRegistry::new_fixed(&capacity, 1, loans).unwrap();
            registry.spawn_upgrade(std::future::pending()).unwrap();
            let first = first_id(&registry);
            let entered = Arc::new(std::sync::atomic::AtomicBool::new(false));
            let actual_entered = entered.clone();
            let refused = registry.spawn_upgrade(async move {
                actual_entered.store(true, std::sync::atomic::Ordering::SeqCst);
                std::future::pending::<()>().await;
            });
            let after = first_id(&registry);
            let retained = owner.retained_tasks();
            let joined = owner.join().await;
            drop(owner);
            drop(registry);
            let usage = capacity.usage();
            assert_eq!(refused, Err(SocketCleanupError::Capacity));
            assert_eq!(first, after);
            assert_eq!(retained, 1);
            assert!(!entered.load(std::sync::atomic::Ordering::SeqCst));
            assert_eq!(joined, SocketDrainOutcome::Joined);
            assert_eq!(
                usage,
                super::super::super::model_originals::ModelCaptureUsage::default()
            );
        })
    });
}

#[test]
fn browser_fixed_socket_03_cancelled_borrow_retains_actual_handle_through_destructor_join() {
    let runtime = tokio::runtime::Builder::new_multi_thread()
        .worker_threads(2)
        .enable_all()
        .build()
        .unwrap();
    with_loans(|loans| {
        runtime.block_on(async {
            let bytes = SocketTaskRegistry::fixed_requested_bytes(1).unwrap();
            let capacity = HostModelCaptureCapacity::metadata_only(loans, bytes).unwrap();
            let (registry, mut owner) = SocketTaskRegistry::new_fixed(&capacity, 1, loans).unwrap();
            let release = Release::new();
            let entered = Arc::new(Notify::new());
            held_task(&registry, &release, entered.clone());
            let entered_result =
                tokio::time::timeout(Duration::from_secs(3), entered.notified()).await;
            let first = first_id(&registry);
            let pending = if entered_result.is_ok() {
                let mut drain =
                    std::pin::pin!(owner.drain(Instant::now() + Duration::from_secs(3)));
                futures_util::poll!(drain.as_mut()).is_pending()
            } else {
                false
            };
            let after = first_id(&registry);
            let retained = owner.retained_tasks();
            release.release();
            let joined = owner.join().await;
            drop(owner);
            drop(registry);
            let usage = capacity.usage();
            assert!(entered_result.is_ok());
            assert!(pending);
            assert_eq!(first, after);
            assert_eq!(retained, 1);
            assert_eq!(joined, SocketDrainOutcome::Joined);
            assert_eq!(
                usage,
                super::super::super::model_originals::ModelCaptureUsage::default()
            );
        })
    });
}
