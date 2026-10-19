//! Existing workflow child; actual Report-owned record and genuine Session.
//! Missing APIs are intentional prospective RED, not a separate test checker.
use super::expansion::{ExpansionLimits, ExpansionOwner, ReadExpansionLimits};
use super::ingress::BoundCorpus;
use super::observation_check::{CompareLimits, CompareOwner, ObservationError};
use super::reviewed_sources::ReviewedSources;
use super::source_compile::{CaseCompiler, WorkflowRecordError};
use super::source_proof::{LineageStatus, SourceVerifier};
use super::work::{ClosureLimits, ClosureOwner};
use super::*;
use crate::json::strict::{ReadWork, ReadWorkLimits};
use crate::transport::{Limits, Session};
use crate::workbench::report::WorkflowExchangeRecord;
use serde::Serialize;
use serde_json::value::RawValue;
use std::ffi::OsString;

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct PrivateProposedRequest<'a> {
    op: &'static str,
    suite: &'static str,
    contract_version: &'static str,
    format: &'static str,
    run_index: usize,
    input: &'a RawValue,
}

#[test]
fn report_owned_actual_exchange_roundtrip_uses_same_genuine_blocked_source_checker() {
    let sources = ReviewedSources::selected();
    let mut decode = Decoder::new(
        DecodeLimits::new(
            16_777_216,
            1_073_741_824,
            4_000_000,
            1_073_741_824,
            4_000_000,
        )
        .unwrap(),
    );
    let bound = BoundCorpus::decode(
        include_str!("source_compile/controls/bound-corpus.json"),
        &mut decode,
    )
    .unwrap();
    let verifier = SourceVerifier::new(&sources, &mut decode).unwrap();
    let mut closure = ClosureOwner::new(
        ClosureLimits::new(1_000_000, 1_000_000, 100_000_000, 100_000_000).unwrap(),
    );
    let mut expanded = ExpansionOwner::new(
        ExpansionLimits::new(
            1_073_741_824,
            1_073_741_824,
            1_073_741_824,
            1_000_000,
            10_000_000,
        )
        .with_reads(ReadExpansionLimits::new(
            1_000_000,
            4_294_967_296,
            8_589_934_592,
            8_589_934_592,
        )),
    );
    let mut compiler = CaseCompiler::new(verifier, &mut closure, &mut expanded);
    let compiled = compiler.compile(&bound.cases()[0]).unwrap();
    let context = compiled.report_context();
    assert_eq!(
        context.case().id(),
        "connected-inventory-single-file-json-v3"
    );
    assert_eq!(context.lineage(), LineageStatus::Unproven);

    // Private candidate envelope only: draft30 is not registered or advertised
    // by this control. Producer input is actual source bytes, not expected data.
    let op = match context.paired().run() {
        super::pairing::PairedRun::Client { .. } => "model-originals-client",
        _ => panic!("fixed reviewed v3 is a genuine client run"),
    };
    let request = PrivateProposedRequest {
        op,
        suite: "workbench",
        contract_version: "0.1.0-draft.30",
        format: "json",
        run_index: context.paired().run_index(),
        input: context.input_raw(),
    };
    let peer = std::env::var_os("MORPHIR_MCK_REPORT_PEER_BIN")
        .expect("root gate supplies actual compiled existing MEP test harness");
    let mut session = Session::spawn_mep(
        &peer,
        &[
            OsString::from("--adapter"),
            OsString::from("workflow-report-v3"),
        ],
        Limits::DEFAULT,
    )
    .unwrap();
    let exchange = session.exchange_recorded_literal(&request).unwrap();
    let record = WorkflowExchangeRecord::capture(exchange);
    session.close().unwrap();
    assert_eq!(
        record.sent_payload().as_bytes(),
        include_bytes!("report_controls/sent-request.payload.json")
    );
    assert_eq!(
        record.received_payload().as_bytes(),
        include_bytes!("report_controls/received-reply.payload.json")
    );
    assert_eq!(
        context.input_raw().get().as_bytes(),
        include_bytes!("report_controls/source-input.token.json")
    );

    // This is the existing Report module's private evidence record body,
    // never a second top-level report contract or a qualification issuer.
    let saved = record.to_json().unwrap();
    let mut saved_work = ReadWork::new(ReadWorkLimits::new(16_777_216, 4_000_000).unwrap());
    let restored = WorkflowExchangeRecord::from_json(&saved, &mut saved_work).unwrap();
    assert_eq!(restored.sent_payload(), record.sent_payload());
    assert_eq!(restored.received_payload(), record.received_payload());

    let mut live_owner =
        CompareOwner::new(CompareLimits::new(100_000, 1_000_000, 100_000).unwrap());
    assert!(matches!(
        context.check_record(&record, &mut decode, &mut live_owner),
        Err(WorkflowRecordError::Observation(
            ObservationError::ExpectedBlocked
        ))
    ));
    let decode_at_fault = decode.usage();
    let comparison_at_fault = live_owner.usage();
    assert!(matches!(
        context.check_record(&restored, &mut decode, &mut live_owner),
        Err(WorkflowRecordError::Observation(
            ObservationError::ExpectedBlocked
        ))
    ));
    assert_eq!(decode.usage(), decode_at_fault);
    assert_eq!(live_owner.usage(), comparison_at_fault);

    // Replay is a separate caller-owned check attempt under explicit policy,
    // not a reset of the failed live owner or limits obtained from saved data.
    let mut replay_owner =
        CompareOwner::new(CompareLimits::new(100_000, 1_000_000, 100_000).unwrap());
    assert!(matches!(
        context.check_record(&restored, &mut decode, &mut replay_owner),
        Err(WorkflowRecordError::Observation(
            ObservationError::ExpectedBlocked
        ))
    ));
    assert_eq!(context.lineage(), LineageStatus::Unproven);
}
