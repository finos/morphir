//! Genuine first compiler row/owners; these finite port controls create no host,
//! browser or network effect and claim no product/physical qualification.
use super::super::super::{
    adapter::execution_loans::PreparedBrowserClientRun, execution::with_prepared_browser_execution,
};
use super::*;
use crate::{
    json::strict::Document,
    workbench::{
        configuration::InstalledObservationLimits,
        corpus::CorpusSource,
        model_originals::workflow::pipeline::{Source, policy::Policy},
    },
};
fn first<R>(
    action: impl FnOnce(
        &PreparedBrowserClientRun<'_, '_, '_, '_, '_, '_>,
        &mut BrowserLoans<'_, '_>,
        &mut BrowserRowProducer<'_>,
    ) -> R,
    inspect: impl FnOnce(&BrowserRowCollection),
) -> R {
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
    let receiving=InstalledObservationLimits::from_document(&Document::parse_unsigned_counts(br#"{"rpcFrames":"checker-capture","retainedBytes":16777216,"stdoutPrefixBytes":0,"stderrPrefixBytes":0,"snapshotReadBytes":0,"byteVisits":16777216,"records":1024}"#).unwrap()).unwrap();
    let mut action = Some(action);
    let result = std::cell::RefCell::new(None);
    with_prepared_browser_execution(
        &source,
        &policy,
        &receiving,
        BrowserDocumentBounds::new(2, 4096, 1024).unwrap(),
        |run, loans, row| {
            result.replace(Some(action.take().unwrap()(run, loans, row)));
            Err::<(), ()>(())
        },
        |inventory, _| {
            assert_eq!(inventory.rows().len(), 23);
            inspect(inventory.rows()[0].attempt().unwrap().collection())
        },
    )
    .unwrap();
    result.into_inner().unwrap()
}
#[test]
fn browser_host_transcript_01_exact_source_journey_is_retained_outside_callback() {
    first(
        |run, loans, row| {
            let opening = run.openings(loans).unwrap().next().unwrap();
            let stimulus = run.prepare_controlled_host(&opening, loans).unwrap();
            let mut producer = row.issue(run, &opening, loans).unwrap();
            let port = producer
                .prepare_host_transcript(
                    loans,
                    &stimulus,
                    Instant::now() + std::time::Duration::from_secs(3),
                )
                .unwrap();
            assert!(
                producer
                    .prepare_host_transcript(
                        loans,
                        &stimulus,
                        Instant::now() + std::time::Duration::from_secs(3)
                    )
                    .is_err()
            );
            port.begin_manifest()
                .unwrap()
                .prepared(200, stimulus.manifest_body().as_bytes())
                .unwrap();
            port.peer_opened().unwrap();
            let requests = stimulus.requests().unwrap();
            for (request, reply) in requests.iter().zip(stimulus.frames()) {
                port.begin_read()
                    .unwrap()
                    .finish(BrowserHostReadOutcome::Text(request.as_bytes()))
                    .unwrap();
                port.begin_reply(reply.as_bytes())
                    .unwrap()
                    .finish(BrowserHostSendOutcome::Returned)
                    .unwrap();
            }
            port.peer_finished(BrowserHostPeerFinish::ScriptFinished)
                .unwrap();
            (stimulus.manifest_body().as_bytes().to_vec(), requests.len())
        },
        |collection| {
            let document = collection.document(0).unwrap();
            let host = document.host_transcript().unwrap();
            assert_eq!(host.event_count(), 28);
            assert_eq!(host.pending(), 0);
            assert_eq!(host.first(), None);
            assert!(matches!(
                host.event(0).unwrap().fact(),
                BrowserHostFact::ManifestRequestReceived
            ));
            assert!(matches!(
                host.event(1).unwrap().fact(),
                BrowserHostFact::ManifestResponsePrepared { status: 200 }
            ));
            assert!(
                host.event(1)
                    .unwrap()
                    .bytes()
                    .unwrap()
                    .starts_with(b"{\"protocolVersion\"")
            );
            assert!(matches!(
                host.event(27).unwrap().fact(),
                BrowserHostFact::PeerFinished {
                    outcome: BrowserHostPeerFinish::ScriptFinished
                }
            ));
        },
    );
}
#[test]
fn browser_host_transcript_02_mismatched_text_is_retained_before_peer_failure() {
    first(
        |run, loans, row| {
            let opening = run.openings(loans).unwrap().next().unwrap();
            let stimulus = run.prepare_controlled_host(&opening, loans).unwrap();
            let mut producer = row.issue(run, &opening, loans).unwrap();
            let port = producer
                .prepare_host_transcript(
                    loans,
                    &stimulus,
                    Instant::now() + std::time::Duration::from_secs(3),
                )
                .unwrap();
            port.peer_opened().unwrap();
            let mut actual = stimulus.requests().unwrap()[0].as_bytes().to_vec();
            actual[0] = b'[';
            port.begin_read()
                .unwrap()
                .finish(BrowserHostReadOutcome::Text(&actual))
                .unwrap();
            port.peer_finished(BrowserHostPeerFinish::Failed).unwrap();
        },
        |collection| {
            let document = collection.document(0).unwrap();
            let host = document.host_transcript().unwrap();
            assert!(matches!(
                host.event(1).unwrap().fact(),
                BrowserHostFact::TextRequestReceived
            ));
            assert_eq!(host.event(1).unwrap().bytes().unwrap()[0], b'[');
            assert!(host.first().is_some());
        },
    );
}
#[test]
fn browser_host_transcript_03_overbound_text_refuses_without_claiming_truncated_bytes() {
    first(
        |run, loans, row| {
            let opening = run.openings(loans).unwrap().next().unwrap();
            let stimulus = run.prepare_controlled_host(&opening, loans).unwrap();
            let mut producer = row.issue(run, &opening, loans).unwrap();
            let port = producer
                .prepare_host_transcript(
                    loans,
                    &stimulus,
                    Instant::now() + std::time::Duration::from_secs(3),
                )
                .unwrap();
            port.peer_opened().unwrap();
            let actual = vec![b'x'; stimulus.requests().unwrap()[0].len() + 1];
            assert!(
                port.begin_read()
                    .unwrap()
                    .finish(BrowserHostReadOutcome::Text(&actual))
                    .is_err()
            );
            assert!(port.begin_reply(stimulus.frames()[0].as_bytes()).is_err());
            port.peer_finished(BrowserHostPeerFinish::Failed).unwrap();
        },
        |collection| {
            let document = collection.document(0).unwrap();
            let host = document.host_transcript().unwrap();
            let record = host.event(1).unwrap();
            assert!(
                matches!(record.fact(),BrowserHostFact::TextRequestOverBound{actual_bytes,admitted_bytes} if *actual_bytes==*admitted_bytes+1)
            );
            assert_eq!(record.bytes(), None);
            assert_eq!(host.first(), Some(BrowserHostTranscriptFault::Capacity));
        },
    );
}
#[test]
fn browser_host_transcript_04_pending_return_survives_source_revoke_but_new_effect_refuses() {
    let (port, pending) = first(
        |run, loans, row| {
            let opening = run.openings(loans).unwrap().next().unwrap();
            let stimulus = run.prepare_controlled_host(&opening, loans).unwrap();
            let mut producer = row.issue(run, &opening, loans).unwrap();
            let port = producer
                .prepare_host_transcript(
                    loans,
                    &stimulus,
                    Instant::now() + std::time::Duration::from_secs(3),
                )
                .unwrap();
            port.peer_opened().unwrap();
            port.begin_read()
                .unwrap()
                .finish(BrowserHostReadOutcome::Text(
                    stimulus.requests().unwrap()[0].as_bytes(),
                ))
                .unwrap();
            let pending = port.begin_reply(stimulus.frames()[0].as_bytes()).unwrap();
            (port, pending)
        },
        |collection| {
            let document = collection.document(0).unwrap();
            let host = document.host_transcript().unwrap();
            assert_eq!(host.pending(), 1);
        },
    );
    assert!(matches!(
        port.begin_read(),
        Err(BrowserHostTranscriptFault::Source)
    ));
    pending.finish(BrowserHostSendOutcome::Returned).unwrap();
}
