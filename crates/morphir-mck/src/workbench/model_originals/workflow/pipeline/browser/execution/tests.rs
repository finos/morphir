//! Genuine reviewed compiler rows and cumulative owners. No physical browser
//! execution, product provenance, checker verdict or profile qualification.
use super::super::{adapter::execution_loans::*, collection::*, *};
use super::*;
use crate::{
    json::strict::Document,
    workbench::{
        configuration::InstalledObservationLimits,
        corpus::CorpusSource,
        model_originals::workflow::pipeline::{Source, policy::Policy},
    },
};

fn fixture() -> (
    tempfile::TempDir,
    Source,
    Policy,
    InstalledObservationLimits,
) {
    let root = tempfile::tempdir().unwrap();
    std::fs::write(
        root.path().join("cases.json"),
        include_bytes!(concat!(
            env!("CARGO_MANIFEST_DIR"),
            "/src/workbench/model_originals/workflow/pipeline_controls/cases.json"
        )),
    )
    .unwrap();
    let source = Source::new(CorpusSource::load(root.path()).unwrap()).unwrap();
    let policy = Policy::from_document(
        &Document::parse_unsigned_counts(include_bytes!(concat!(
            env!("CARGO_MANIFEST_DIR"),
            "/src/workbench/model_originals/workflow/pipeline_controls/explicit-test-policy.json"
        )))
        .unwrap(),
    )
    .unwrap();
    let receiving = InstalledObservationLimits::from_document(&Document::parse_unsigned_counts(
        br#"{"rpcFrames":"checker-capture","retainedBytes":16777216,"stdoutPrefixBytes":0,"stderrPrefixBytes":0,"snapshotReadBytes":0,"byteVisits":16777216,"records":1024}"#).unwrap()).unwrap();
    (root, source, policy, receiving)
}
#[test]
fn browser_execution_engine_01_full_inventory_callback_error_and_actual_debt_are_retained() {
    let (_root, source, policy, receiving) = fixture();
    let mut callbacks = 0;
    let held = std::cell::RefCell::new(None);
    with_prepared_browser_execution(
        &source,
        &policy,
        &receiving,
        BrowserDocumentBounds::new(2, 4096, 1024).unwrap(),
        |run, loans, _producer| {
            callbacks += 1;
            let opening = run.openings(loans).unwrap().next().unwrap();
            held.replace(Some(run.prepare_controlled_host(&opening, loans).unwrap()));
            Err("actual adapter refusal")
        },
        |inventory, _loans| {
            assert_eq!(inventory.rows().len(), 23);
            assert_eq!(inventory.first_failed_row(), Some(0));
            let first = &inventory.rows()[0];
            assert_eq!(first.case_id(), "connected-inventory-single-file-json-v3");
            assert_eq!(first.run_index(), 0);
            assert_eq!(first.context().unwrap().case().id(), first.case_id());
            let attempted = first.attempt().unwrap();
            assert!(matches!(
                attempted.callback(),
                BrowserAdapterCompletion::Returned(Err("actual adapter refusal"))
            ));
            assert_eq!(
                attempted.child_terminal(),
                BrowserSourceTerminal::Unfinished { bindings: 1 }
            );
            for row in &inventory.rows()[1..] {
                assert_eq!(row.not_attempted_after(), Some(0));
            }
            assert_eq!(
                held.borrow().as_ref().unwrap().admit(),
                Err(BrowserSourceFault::Revoked)
            );
        },
    )
    .unwrap();
    assert_eq!(callbacks, 1);
    // No physical host was created: the held binding remains debt, not a join.
}

#[test]
fn browser_execution_engine_02_successful_callback_cannot_substitute_for_missing_collection() {
    let (_root, source, policy, receiving) = fixture();
    let mut callbacks = 0;
    with_prepared_browser_execution(
        &source,
        &policy,
        &receiving,
        BrowserDocumentBounds::new(2, 4096, 1024).unwrap(),
        |_run, _loans, _producer| {
            callbacks += 1;
            Ok::<_, ()>(())
        },
        |inventory, _loans| {
            assert_eq!(inventory.rows().len(), 23);
            assert_eq!(inventory.first_failed_row(), Some(0));
            let attempted = inventory.rows()[0].attempt().unwrap();
            assert!(matches!(
                attempted.callback(),
                BrowserAdapterCompletion::Returned(Ok(()))
            ));
            assert_eq!(attempted.child_terminal(), BrowserSourceTerminal::Quiescent);
            assert!(!attempted.collection_complete());
            for row in &inventory.rows()[1..] {
                assert_eq!(row.not_attempted_after(), Some(0));
            }
        },
    )
    .unwrap();
    assert_eq!(callbacks, 1);
}

fn frame(kind: u8, sequence: u64, payload: &[u8]) -> Vec<u8> {
    let mut frame = vec![0; 16];
    frame[0] = 1;
    frame[1] = kind;
    frame[4..12].copy_from_slice(&sequence.to_be_bytes());
    frame[12..16].copy_from_slice(&u32::try_from(payload.len()).unwrap().to_be_bytes());
    frame.extend_from_slice(payload);
    frame
}
#[test]
fn browser_execution_engine_03_actual_raw_and_typed_data_survive_callback_error_with_source_context()
 {
    let (_root, source, policy, receiving) = fixture();
    let payload = br#"{"sequence":1,"kind":"model-closed","actual":{"workspace":"literal-\ud800","opening":0}}"#;
    let actual_frame = frame(1, 1, payload);
    with_prepared_browser_execution(
        &source,
        &policy,
        &receiving,
        BrowserDocumentBounds::new(2, 4096, 1024).unwrap(),
        |run, loans, row| {
            let opening = run.openings(loans).unwrap().next().unwrap();
            let mut endpoint = row.issue(run, &opening, loans).unwrap();
            endpoint
                .record_frame(
                    loans,
                    &actual_frame,
                    std::time::Instant::now() + std::time::Duration::from_secs(2),
                )
                .unwrap();
            Err("after retained DATA, before any physical ACK")
        },
        |inventory, _loans| {
            assert_eq!(inventory.rows().len(), 23);
            let first = &inventory.rows()[0];
            assert_eq!(
                first.context().unwrap().case().id(),
                "connected-inventory-single-file-json-v3"
            );
            let attempt = first.attempt().unwrap();
            let document = attempt.collection().document(0).unwrap();
            assert_eq!(document.record_count(), 1);
            let record = document.record(0).unwrap();
            assert_eq!(record.frame(), actual_frame);
            assert_eq!(record.data().sequence().0, 1);
            assert!(matches!(
                record.data().content(),
                BrowserDocumentContent::Fact(BrowserDocumentFactData::ModelClosed(_))
            ));
            drop(record);
            drop(document);
            assert!(!attempt.collection_complete());
            assert_eq!(inventory.first_failed_row(), Some(0));
        },
    )
    .unwrap();
}

#[test]
fn browser_execution_engine_04_unwind_retains_original_payload_and_revokes_actual_child() {
    let (_root, source, policy, receiving) = fixture();
    let held = std::cell::RefCell::new(None);
    with_prepared_browser_execution(
        &source,
        &policy,
        &receiving,
        BrowserDocumentBounds::new(2, 4096, 1024).unwrap(),
        |run, loans, _row| -> Result<(), ()> {
            let opening = run.openings(loans).unwrap().next().unwrap();
            held.replace(Some(run.prepare_controlled_host(&opening, loans).unwrap()));
            std::panic::panic_any(431_u32);
        },
        |inventory, _loans| {
            let attempt = inventory.rows()[0].attempt().unwrap();
            match attempt.callback() {
                BrowserAdapterCompletion::Panicked(actual) => {
                    assert_eq!(actual.downcast_ref::<u32>(), Some(&431))
                }
                _ => panic!("the original panic payload must remain a distinct outcome"),
            }
            assert_eq!(
                held.borrow().as_ref().unwrap().admit(),
                Err(BrowserSourceFault::Revoked)
            );
            assert_eq!(
                attempt.child_terminal(),
                BrowserSourceTerminal::Unfinished { bindings: 1 }
            );
            assert_eq!(inventory.first_failed_row(), Some(0));
            for row in &inventory.rows()[1..] {
                assert_eq!(row.not_attempted_after(), Some(0));
            }
        },
    )
    .unwrap();
}

#[test]
fn browser_execution_engine_05_public_component_wrapper_uses_same_actual_inventory() {
    let (root, _source, _policy, _receiving) = fixture();
    let corpus = crate::workbench::corpus::load(root.path()).unwrap();
    let checker: serde_json::Value = serde_json::from_slice(include_bytes!(concat!(
        env!("CARGO_MANIFEST_DIR"),
        "/src/workbench/model_originals/workflow/pipeline_controls/explicit-test-policy.json"
    )))
    .unwrap();
    let configuration = crate::workbench::RunConfiguration::from_json(
        &serde_json::json!({
            "kind":"model-originals-browser", "browser":"chromium", "checker":checker,
            "receiving":{"retainedBytes":16777216,"stdoutPrefixBytes":0,"stderrPrefixBytes":0,
            "snapshotReadBytes":0,"byteVisits":16777216,"records":1024}
        })
        .to_string(),
    )
    .unwrap();
    let count = with_executed_browser_originals(
        &corpus,
        &configuration,
        BrowserDocumentBounds::new(2, 4096, 1024).unwrap(),
        |_run, _loans, _producer| Err::<(), _>("actual component refusal"),
        |inventory| {
            assert_eq!(inventory.first_failed_row(), Some(0));
            inventory.rows().len()
        },
    )
    .unwrap();
    assert_eq!(count, 23);
}

#[test]
fn browser_execution_engine_06_ignored_owner_refusal_belongs_to_same_attempt() {
    let (_root, source, policy, receiving) = fixture();
    let fact = frame(
        1,
        1,
        br#"{"sequence":1,"kind":"model-closed","actual":{"workspace":"literal","opening":0}}"#,
    );
    let end = frame(2, 2, br#"{"lastSequence":1,"observer":{"kind":"closed"}}"#);
    let mut callbacks = 0;
    with_prepared_browser_execution(
        &source,
        &policy,
        &receiving,
        BrowserDocumentBounds::new(2, 4096, 1024).unwrap(),
        |run, loans, row| {
            callbacks += 1;
            let opening = run.openings(loans).unwrap().next().unwrap();
            let mut endpoint = row.issue(run, &opening, loans).unwrap();
            let actual_end = std::time::Instant::now() + std::time::Duration::from_secs(2);
            endpoint.record_frame(loans, &fact, actual_end).unwrap();
            endpoint.record_frame(loans, &end, actual_end).unwrap();
            assert!(
                loans
                    .reserve_controlled_host_storage(usize::MAX, 0, 0)
                    .is_err()
            );
            Ok::<_, ()>(())
        },
        |inventory, _loans| {
            assert_eq!(
                inventory.first_failed_row(),
                Some(0),
                "the owner fault belongs to the actual completed callback, not next-row setup"
            );
            assert_eq!(inventory.rows().len(), 23);
            let attempt = inventory.rows()[0].attempt().unwrap();
            assert!(matches!(
                attempt.callback(),
                BrowserAdapterCompletion::Returned(Ok(()))
            ));
            assert_eq!(attempt.child_terminal(), BrowserSourceTerminal::Quiescent);
            assert!(attempt.collection_complete());
            assert!(attempt.owner_failure().is_some());
            let snapshot = attempt.collection().document(0).unwrap();
            assert_eq!(snapshot.record_count(), 2);
            assert_eq!(snapshot.record(0).unwrap().frame(), fact);
            assert_eq!(snapshot.record(1).unwrap().frame(), end);
            for row in &inventory.rows()[1..] {
                assert_eq!(row.not_attempted_after(), Some(0));
            }
        },
    )
    .unwrap();
    assert_eq!(callbacks, 1);
}
