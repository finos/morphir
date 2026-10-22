//! Decoder permission relationship controls only. No compiled execution,
//! physical browser, product fact, report or profile qualification is claimed.
use super::super::execution_loans::ExecutionChild;
use super::*;
use crate::workbench::{
    configuration::InstalledObservationLimits,
    model_originals::workflow::pipeline::{
        installed::observation::InstalledObservationOwner,
        policy::{Owners, Policy},
    },
};

const PAYLOAD: &[u8] =
    br#"{"sequence":1,"kind":"model-closed","actual":{"workspace":"w","opening":0}}"#;
// This permission test needs only its exact fixed header and literal payload.
// Do not enlarge receiving policy to accommodate unrelated spare frame room.
const FRAME_BYTES: usize = 16 + PAYLOAD.len();
fn owners() -> (Owners, InstalledObservationOwner) {
    let policy = include_str!(concat!(
        env!("CARGO_MANIFEST_DIR"),
        "/src/workbench/model_originals/workflow/pipeline_controls/explicit-test-policy.json"
    ));
    let owners =
        Policy::from_document(&Document::parse_unsigned_counts(policy.as_bytes()).unwrap())
            .unwrap()
            .owners();
    let receiving = InstalledObservationOwner::new(
        &InstalledObservationLimits::from_document(
            &Document::parse_unsigned_counts(br#"{"rpcFrames":"checker-capture","retainedBytes":1048576,"stdoutPrefixBytes":0,"stderrPrefixBytes":0,"snapshotReadBytes":0,"byteVisits":1048576,"records":0}"#).unwrap(),
        ).unwrap(),
    );
    (owners, receiving)
}
fn assert_refused_without_consuming(
    loans: &mut BrowserLoans<'_, '_>,
    source: &BrowserApplicationSource,
    decoder: &mut BrowserDocumentDecoder,
) {
    let before = {
        let (decode, receiving, _) = loans.inner.physical_owners().unwrap();
        (decoder.remaining, decode.usage(), receiving.usage())
    };
    let error = loans
        .decode_document_frame_data(
            source,
            decoder,
            1,
            1,
            PAYLOAD,
            Instant::now() + std::time::Duration::from_secs(1),
        )
        .unwrap_err();
    assert_eq!(error.kind(), BrowserDocumentErrorKind::Source);
    assert_eq!(decoder.remaining, before.0);
    assert_eq!(loans.inner.physical_owners().unwrap().0.usage(), before.1);
    assert_eq!(loans.inner.physical_owners().unwrap().1.usage(), before.2);
}

#[test]
fn browser_document_relation_01_live_foreign_child_refuses_before_parser_or_record_consumption() {
    let (mut owners, mut receiving) = owners();
    let mut raw = inputs::BrowserOwnerLoans::new(&mut owners, &mut receiving);
    let global = BrowserSourceScope::prepare(&mut raw).unwrap();
    let source = BrowserLoans::application(&mut raw, &global)
        .unwrap()
        .prepare_application_source()
        .unwrap();
    let first = ExecutionChild::prepare(&global, &mut raw).unwrap();
    let second = ExecutionChild::prepare(&global, &mut raw).unwrap();
    let mut decoder = BrowserLoans::execution(&mut raw, &global, &first)
        .unwrap()
        .prepare_document_decoder(&source, 2, FRAME_BYTES)
        .unwrap();
    assert_refused_without_consuming(
        &mut BrowserLoans::execution(&mut raw, &global, &second).unwrap(),
        &source,
        &mut decoder,
    );
    assert!(
        BrowserLoans::execution(&mut raw, &global, &first)
            .unwrap()
            .decode_document_frame_data(
                &source,
                &mut decoder,
                1,
                1,
                PAYLOAD,
                Instant::now() + std::time::Duration::from_secs(1)
            )
            .is_ok()
    );
    assert_eq!(decoder.remaining, 1);
}

#[test]
fn browser_document_relation_02_application_and_execution_permissions_cannot_promote_or_downgrade()
{
    let (mut owners, mut receiving) = owners();
    let mut raw = inputs::BrowserOwnerLoans::new(&mut owners, &mut receiving);
    let global = BrowserSourceScope::prepare(&mut raw).unwrap();
    let source = BrowserLoans::application(&mut raw, &global)
        .unwrap()
        .prepare_application_source()
        .unwrap();
    let child = ExecutionChild::prepare(&global, &mut raw).unwrap();
    let mut application = BrowserLoans::application(&mut raw, &global)
        .unwrap()
        .prepare_document_decoder(&source, 2, FRAME_BYTES)
        .unwrap();
    let mut execution = BrowserLoans::execution(&mut raw, &global, &child)
        .unwrap()
        .prepare_document_decoder(&source, 2, FRAME_BYTES)
        .unwrap();
    assert_refused_without_consuming(
        &mut BrowserLoans::execution(&mut raw, &global, &child).unwrap(),
        &source,
        &mut application,
    );
    assert_refused_without_consuming(
        &mut BrowserLoans::application(&mut raw, &global).unwrap(),
        &source,
        &mut execution,
    );
}

#[test]
fn browser_document_relation_03_revoked_child_permission_stays_dead_while_global_image_stays_live()
{
    let (mut owners, mut receiving) = owners();
    let mut raw = inputs::BrowserOwnerLoans::new(&mut owners, &mut receiving);
    let global = BrowserSourceScope::prepare(&mut raw).unwrap();
    let source = BrowserLoans::application(&mut raw, &global)
        .unwrap()
        .prepare_application_source()
        .unwrap();
    let mut first = ExecutionChild::prepare(&global, &mut raw).unwrap();
    let mut decoder = BrowserLoans::execution(&mut raw, &global, &first)
        .unwrap()
        .prepare_document_decoder(&source, 2, FRAME_BYTES)
        .unwrap();
    first.revoke();
    assert_eq!(source.while_source_active(|| 42), Ok(42));
    let next = ExecutionChild::prepare(&global, &mut raw).unwrap();
    assert_refused_without_consuming(
        &mut BrowserLoans::execution(&mut raw, &global, &next).unwrap(),
        &source,
        &mut decoder,
    );
    assert!(BrowserLoans::execution(&mut raw, &global, &first).is_err());
}

#[test]
fn browser_document_relation_04_prior_owner_fault_dominates_foreign_child_without_consuming_record()
{
    use crate::workbench::model_originals::workflow::pipeline::installed::observation::InstalledObservationFault;
    let (mut owners, mut receiving) = owners();
    let mut raw = inputs::BrowserOwnerLoans::new(&mut owners, &mut receiving);
    let global = BrowserSourceScope::prepare(&mut raw).unwrap();
    let source = BrowserLoans::application(&mut raw, &global)
        .unwrap()
        .prepare_application_source()
        .unwrap();
    let first = ExecutionChild::prepare(&global, &mut raw).unwrap();
    let second = ExecutionChild::prepare(&global, &mut raw).unwrap();
    let mut decoder = BrowserLoans::execution(&mut raw, &global, &first)
        .unwrap()
        .prepare_document_decoder(&source, 2, FRAME_BYTES)
        .unwrap();
    let mut other = BrowserLoans::execution(&mut raw, &global, &second).unwrap();
    other
        .inner
        .physical_owners()
        .unwrap()
        .1
        .fail(InstalledObservationFault::PriorFault);
    let before = decoder.remaining;
    let error = other
        .decode_document_frame_data(
            &source,
            &mut decoder,
            1,
            1,
            PAYLOAD,
            Instant::now() + std::time::Duration::from_secs(1),
        )
        .unwrap_err();
    assert_eq!(error.kind(), BrowserDocumentErrorKind::Funding);
    assert_eq!(decoder.remaining, before);
}
