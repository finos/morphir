use super::super::{adapter::execution_loans::*, inputs, source_scope::BrowserSourceScope};
use super::*;
use crate::{
    json::strict::Document,
    workbench::{
        configuration::InstalledObservationLimits,
        corpus::CorpusSource,
        model_originals::workflow::{
            pipeline::{Source, policy::Policy, prepared_typed},
            reviewed_sources::ReviewedSources,
            source_compile::CompiledExecution,
        },
    },
};

const FACT: &[u8] =
    br#"{"sequence":1,"kind":"model-closed","actual":{"workspace":"unit","opening":0}}"#;
const END: &[u8] = br#"{"lastSequence":1,"observer":{"kind":"closed"}}"#;
fn frame(kind: u8, sequence: u64, payload: &[u8]) -> Vec<u8> {
    let mut bytes = vec![0; 16];
    bytes[0] = 1;
    bytes[1] = kind;
    bytes[4..12].copy_from_slice(&sequence.to_be_bytes());
    bytes[12..16].copy_from_slice(&u32::try_from(payload.len()).unwrap().to_be_bytes());
    bytes.extend_from_slice(payload);
    bytes
}
fn compiled(
    action: impl FnOnce(&[CompiledExecution<'_, '_, '_, '_>], &mut inputs::BrowserOwnerLoans<'_>),
) {
    let root = tempfile::tempdir().unwrap();
    std::fs::write(
        root.path().join("cases.json"),
        include_str!("../../../pipeline_controls/cases.json"),
    )
    .unwrap();
    let source = Source::new(CorpusSource::load(root.path()).unwrap()).unwrap();
    let policy = Policy::from_document(
        &Document::parse_unsigned_counts(include_bytes!(
            "../../../pipeline_controls/explicit-test-policy.json"
        ))
        .unwrap(),
    )
    .unwrap();
    let limits=InstalledObservationLimits::from_document(&Document::parse_unsigned_counts(br#"{"rpcFrames":"checker-capture","retainedBytes":8388608,"stdoutPrefixBytes":0,"stderrPrefixBytes":0,"snapshotReadBytes":1048576,"byteVisits":8388608,"records":0}"#).unwrap()).unwrap();
    let mut receiving =
        super::super::super::installed::observation::InstalledObservationOwner::new(&limits);
    prepared_typed(
        &source,
        &policy,
        ReviewedSources::selected(),
        |rows, owners| {
            action(
                rows,
                &mut inputs::BrowserOwnerLoans::new(owners, &mut receiving),
            );
            Ok::<_, ()>(())
        },
    )
    .unwrap();
}
#[test]
fn browser_core_collection_01_exact_bytes_survive_endpoint_drop() {
    compiled(|rows, owners| {
        let CompiledExecution::Current(core) = &rows[0] else {
            panic!("current row")
        };
        let global = BrowserSourceScope::prepare(owners).unwrap();
        let child = ExecutionChild::prepare(&global, owners).unwrap();
        let run = PreparedBrowserClientRun::prepare(core, &global, &child, owners).unwrap();
        let mut loans = super::super::BrowserLoans::execution(owners, &global, &child).unwrap();
        let mut collection = BrowserRowCollection::prepare(
            &run,
            &mut loans,
            BrowserDocumentBounds::new(2, 1024, 16 + FACT.len()).unwrap(),
        )
        .unwrap();
        let opening = run.openings(&mut loans).unwrap().next().unwrap();
        let fact = frame(1, 1, FACT);
        let end = frame(2, 2, END);
        {
            let mut producer = collection
                .producer()
                .issue(&run, &opening, &mut loans)
                .unwrap();
            producer
                .record_frame(
                    &mut loans,
                    &fact,
                    std::time::Instant::now() + std::time::Duration::from_secs(5),
                )
                .unwrap();
            producer
                .record_frame(
                    &mut loans,
                    &end,
                    std::time::Instant::now() + std::time::Duration::from_secs(5),
                )
                .unwrap();
        }
        let snapshot = collection.document(0).unwrap();
        assert_eq!(snapshot.record_count(), 2);
        assert_eq!(snapshot.record(0).unwrap().frame(), fact);
        assert_eq!(snapshot.record(1).unwrap().frame(), end);
        drop(snapshot);
        assert!(matches!(
            collection.terminal(),
            BrowserCollectionTerminal::AllDocumentsEnded {
                documents: 1,
                records: 2
            }
        ));
        assert!(
            collection
                .producer()
                .issue(&run, &opening, &mut loans)
                .is_err(),
            "same source opening cannot acquire a second producer"
        );
    });
}
#[test]
fn browser_core_collection_02_partial_facts_survive_abandoned_writer() {
    compiled(|rows, owners| {
        let CompiledExecution::Current(core) = &rows[0] else {
            panic!("current row")
        };
        let global = BrowserSourceScope::prepare(owners).unwrap();
        let child = ExecutionChild::prepare(&global, owners).unwrap();
        let run = PreparedBrowserClientRun::prepare(core, &global, &child, owners).unwrap();
        let mut loans = super::super::BrowserLoans::execution(owners, &global, &child).unwrap();
        let mut collection = BrowserRowCollection::prepare(
            &run,
            &mut loans,
            BrowserDocumentBounds::new(2, 1024, 16 + FACT.len()).unwrap(),
        )
        .unwrap();
        let opening = run.openings(&mut loans).unwrap().next().unwrap();
        let fact = frame(1, 1, FACT);
        {
            let mut producer = collection
                .producer()
                .issue(&run, &opening, &mut loans)
                .unwrap();
            producer
                .record_frame(
                    &mut loans,
                    &fact,
                    std::time::Instant::now() + std::time::Duration::from_secs(5),
                )
                .unwrap();
        }
        assert_eq!(
            collection.document(0).unwrap().record(0).unwrap().frame(),
            fact
        );
        assert!(matches!(
            collection.terminal(),
            BrowserCollectionTerminal::Incomplete { .. }
        ));
    });
}

#[test]
fn browser_core_collection_03_live_foreign_child_cannot_spend_or_poison_original() {
    compiled(|rows, owners| {
        let CompiledExecution::Current(core) = &rows[0] else {
            panic!("current")
        };
        let global = BrowserSourceScope::prepare(owners).unwrap();
        let child_a = ExecutionChild::prepare(&global, owners).unwrap();
        let child_b = ExecutionChild::prepare(&global, owners).unwrap();
        let run = PreparedBrowserClientRun::prepare(core, &global, &child_a, owners).unwrap();
        let (collection, mut producer) = {
            let mut loans =
                super::super::BrowserLoans::execution(owners, &global, &child_a).unwrap();
            let mut collection = BrowserRowCollection::prepare(
                &run,
                &mut loans,
                BrowserDocumentBounds::new(2, 1024, 16 + FACT.len()).unwrap(),
            )
            .unwrap();
            let opening = run.openings(&mut loans).unwrap().next().unwrap();
            let producer = collection
                .producer()
                .issue(&run, &opening, &mut loans)
                .unwrap();
            (collection, producer)
        };
        let before = {
            let (d, r, c) = owners.physical_owners().unwrap();
            (d.usage(), r.usage(), c.usage())
        };
        let wire = frame(1, 1, FACT);
        {
            let mut wrong =
                super::super::BrowserLoans::execution(owners, &global, &child_b).unwrap();
            assert!(matches!(
                producer.record_frame(
                    &mut wrong,
                    &wire,
                    std::time::Instant::now() + std::time::Duration::from_secs(5)
                ),
                Err(BrowserCollectionFault::Source)
            ));
        }
        let after = {
            let (d, r, c) = owners.physical_owners().unwrap();
            (d.usage(), r.usage(), c.usage())
        };
        assert_eq!(before, after);
        assert_eq!(collection.document(0).unwrap().record_count(), 0);
        let mut original =
            super::super::BrowserLoans::execution(owners, &global, &child_a).unwrap();
        producer
            .record_frame(
                &mut original,
                &wire,
                std::time::Instant::now() + std::time::Duration::from_secs(5),
            )
            .unwrap();
        assert_eq!(
            collection.document(0).unwrap().record(0).unwrap().frame(),
            wire
        );
    });
}
#[test]
fn browser_core_collection_04_first_fault_survives_new_input_deadline_and_poison() {
    compiled(|rows, owners| {
        let CompiledExecution::Current(core) = &rows[0] else {
            panic!("current")
        };
        let global = BrowserSourceScope::prepare(owners).unwrap();
        let child = ExecutionChild::prepare(&global, owners).unwrap();
        let run = PreparedBrowserClientRun::prepare(core, &global, &child, owners).unwrap();
        let mut loans = super::super::BrowserLoans::execution(owners, &global, &child).unwrap();
        let mut collection = BrowserRowCollection::prepare(
            &run,
            &mut loans,
            BrowserDocumentBounds::new(2, 1024, 16 + FACT.len()).unwrap(),
        )
        .unwrap();
        let opening = run.openings(&mut loans).unwrap().next().unwrap();
        let mut producer = collection
            .producer()
            .issue(&run, &opening, &mut loans)
            .unwrap();
        let fault = producer.record_frame(
            &mut loans,
            &frame(1, 2, FACT),
            std::time::Instant::now() + std::time::Duration::from_secs(5),
        );
        assert!(matches!(fault, Err(BrowserCollectionFault::Order)));
        assert!(matches!(
            producer.record_frame(&mut loans, &[], std::time::Instant::now()),
            Err(BrowserCollectionFault::Order)
        ));
        let _ = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
            let _held = producer.journal.lock().unwrap();
            panic!("literal poison control")
        }));
        producer.refuse(BrowserCollectionFault::Source);
        assert!(matches!(
            producer.record_frame(&mut loans, &[], std::time::Instant::now()),
            Err(BrowserCollectionFault::Order)
        ));
        assert!(matches!(
            collection.terminal(),
            BrowserCollectionTerminal::Incomplete {
                first: Some(BrowserCollectionFault::Order),
                ..
            }
        ));
        assert_eq!(collection.document(0).unwrap().record_count(), 0);
    });
}
#[test]
fn browser_core_collection_05_prior_owner_refusal_remains_funding() {
    compiled(|rows, owners| {
        let CompiledExecution::Current(core) = &rows[0] else {
            panic!("current")
        };
        let global = BrowserSourceScope::prepare(owners).unwrap();
        let child = ExecutionChild::prepare(&global, owners).unwrap();
        let run = PreparedBrowserClientRun::prepare(core, &global, &child, owners).unwrap();
        let mut loans = super::super::BrowserLoans::execution(owners, &global, &child).unwrap();
        let mut collection = BrowserRowCollection::prepare(
            &run,
            &mut loans,
            BrowserDocumentBounds::new(2, 1024, 16 + FACT.len()).unwrap(),
        )
        .unwrap();
        let opening = run.openings(&mut loans).unwrap().next().unwrap();
        let mut producer = collection
            .producer()
            .issue(&run, &opening, &mut loans)
            .unwrap();
        let source = loans.prepare_application_source().unwrap();
        assert!(loans.refuse_application(&source).is_err());
        assert!(matches!(
            producer.record_frame(
                &mut loans,
                &frame(1, 1, FACT),
                std::time::Instant::now() + std::time::Duration::from_secs(5)
            ),
            Err(BrowserCollectionFault::Funding)
        ));
        assert_eq!(collection.document(0).unwrap().record_count(), 0);
    });
}
