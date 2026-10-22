//! Real reviewed compiler/owner relation controls, not physical execution.
use super::*;
use crate::{
    json::strict::Document,
    workbench::{
        configuration::InstalledObservationLimits,
        corpus::CorpusSource,
        model_originals::workflow::{
            input::{ClientFixtureMode, ClientRuntime},
            pairing::PairedRun,
            pipeline::{Source, policy::Policy, prepared_typed},
            reviewed_sources::ReviewedSources,
            source_compile::CompiledExecution,
        },
    },
};

pub(super) fn with_compiled(
    action: impl FnOnce(&[CompiledExecution<'_, '_, '_, '_>], &mut inputs::BrowserOwnerLoans<'_>),
) {
    with_compiled_limits(br#"{"rpcFrames":"checker-capture","retainedBytes":8388608,"stdoutPrefixBytes":0,"stderrPrefixBytes":0,"snapshotReadBytes":1048576,"byteVisits":8388608,"records":0}"#, action)
}

pub(super) fn with_compiled_limits(
    limits: &[u8],
    action: impl FnOnce(&[CompiledExecution<'_, '_, '_, '_>], &mut inputs::BrowserOwnerLoans<'_>),
) {
    with_compiled_fixture(limits, CompiledControlPolicy::Standard, action)
}

// Explicit actual-archive controls only. This does not alter the ordinary
// one-GiB fixture, configured production policy or its permanent refusal test.
pub(in crate::workbench::model_originals::workflow::pipeline::browser) fn with_compiled_artifact_control(
    action: impl FnOnce(&[CompiledExecution<'_, '_, '_, '_>], &mut inputs::BrowserOwnerLoans<'_>),
) {
    with_compiled_fixture(
        br#"{"rpcFrames":"checker-capture","retainedBytes":67108864,"stdoutPrefixBytes":4096,"stderrPrefixBytes":4096,"snapshotReadBytes":33554432,"byteVisits":34359738368,"records":0}"#,
        CompiledControlPolicy::ArtifactControl,
        action,
    )
}
pub(super) fn with_compiled_cleanup_control(
    action: impl FnOnce(&[CompiledExecution<'_, '_, '_, '_>], &mut inputs::BrowserOwnerLoans<'_>),
) {
    // Measured Darwin EntryCell=1088; ordinary eight-MiB input funds1474
    // cleanup slots. This retained input funds532, one below the selected
    // source's conservative533-entry obligation. It is not a default limit.
    with_compiled_fixture(
        br#"{"rpcFrames":"checker-capture","retainedBytes":7363712,"stdoutPrefixBytes":4096,"stderrPrefixBytes":4096,"snapshotReadBytes":33554432,"byteVisits":34359738368,"records":0}"#,
        CompiledControlPolicy::ArtifactControl,
        action,
    )
}
#[derive(Clone, Copy)]
enum CompiledControlPolicy {
    Standard,
    ArtifactControl,
}
fn with_compiled_fixture(
    limits: &[u8],
    policy: CompiledControlPolicy,
    action: impl FnOnce(&[CompiledExecution<'_, '_, '_, '_>], &mut inputs::BrowserOwnerLoans<'_>),
) {
    let root = tempfile::tempdir().unwrap();
    std::fs::write(
        root.path().join("cases.json"),
        include_str!(concat!(
            env!("CARGO_MANIFEST_DIR"),
            "/src/workbench/model_originals/workflow/pipeline_controls/cases.json"
        )),
    )
    .unwrap();
    let source = Source::new(CorpusSource::load(root.path()).unwrap()).unwrap();
    let checker_bytes: &[u8] = match policy {
        CompiledControlPolicy::Standard => include_bytes!(concat!(
            env!("CARGO_MANIFEST_DIR"),
            "/src/workbench/model_originals/workflow/pipeline_controls/explicit-test-policy.json"
        )),
        CompiledControlPolicy::ArtifactControl => br#"{"kind":"model-originals","decode":{"savedBytes":16777216,"literalBytes":1073741824,"literalValues":4000000,"byteVisits":34359738368,"slots":4000000},"savedRead":{"bytes":16777216,"values":4000000},"closure":{"definitions":1000000,"references":1000000,"lookupBytes":100000000,"structuralVisits":100000000},"expansion":{"recipeBytes":1073741824,"frameBytes":1073741824,"literalStorageBytes":1073741824,"entries":1000000,"visits":10000000,"readRows":1000000,"readWindowBytes":4294967296,"readWireBytes":8589934592,"readObserverBytes":8589934592},"comparison":{"structuralVisits":100000,"comparisonBytes":1000000,"checks":100000},"capture":{"requestBytes":16777216,"replyBytes":16777216,"aggregateBytes":16777216}}"#,
    };
    let checker =
        Policy::from_document(&Document::parse_unsigned_counts(checker_bytes).unwrap()).unwrap();
    let mut receiving =
        super::super::super::super::installed::observation::InstalledObservationOwner::new(
            &InstalledObservationLimits::from_document(
                &Document::parse_unsigned_counts(limits).unwrap(),
            )
            .unwrap(),
        );
    prepared_typed(
        &source,
        &checker,
        ReviewedSources::selected(),
        |compiled, owners| {
            assert_eq!(
                compiled.len(),
                23,
                "complete selected inventory remains intact"
            );
            action(
                compiled,
                &mut inputs::BrowserOwnerLoans::new(owners, &mut receiving),
            );
            Ok::<_, BrowserInputError>(())
        },
    )
    .unwrap();
}

pub(in crate::workbench::model_originals::workflow::pipeline::browser) fn controlled_clients<
    'a,
    'case,
    'sources,
    'raw,
    'supplied,
>(
    compiled: &'a [CompiledExecution<'case, 'sources, 'raw, 'supplied>],
) -> Vec<
    &'a crate::workbench::model_originals::workflow::source_compile::CompiledSourceCase<
        'case,
        'sources,
        'raw,
        'supplied,
    >,
> {
    compiled.iter().filter_map(|execution| match execution {
        CompiledExecution::Current(core) => Some(core),
        _ => None,
    }).filter(|core| {
        matches!(core.source().paired().run(), PairedRun::Client { fixture, .. }
            if matches!(fixture.mode, ClientFixtureMode::Runtime { runtime: ClientRuntime::ControlledModelOriginalsHttpV1 { .. } }))
    }).take(2).collect()
}

#[test]
fn browser_execution_loans_01_actual_a_stimulus_and_stamp_refuse_b_before_copy_or_adoption() {
    with_compiled(|compiled, inner| {
        let cores = controlled_clients(compiled);
        assert_eq!(cores.len(), 2);
        let global = BrowserSourceScope::prepare(inner).unwrap();
        let image = BrowserLoans::application(inner, &global)
            .unwrap()
            .prepare_application_source()
            .unwrap();
        let (stamp_a, stimulus_a) = {
            let child_a = ExecutionChild::prepare(&global, inner).unwrap();
            let run_a =
                PreparedBrowserClientRun::prepare(cores[0], &global, &child_a, inner).unwrap();
            assert!(std::ptr::eq(run_a.core, cores[0]));
            let mut loans_a = BrowserLoans::execution(inner, &global, &child_a).unwrap();
            let stamp = loans_a.prepare_relation_stamp().unwrap();
            let opening = run_a.openings(&mut loans_a).unwrap().next().unwrap();
            let stimulus = run_a
                .prepare_controlled_host(&opening, &mut loans_a)
                .unwrap();
            loans_a
                .validate_controlled_application(&image, &stimulus)
                .unwrap();
            (stamp, stimulus)
        };
        assert_eq!(stimulus_a.admit(), Err(BrowserSourceFault::Revoked));
        let child_b = ExecutionChild::prepare(&global, inner).unwrap();
        let run_b = PreparedBrowserClientRun::prepare(cores[1], &global, &child_b, inner).unwrap();
        assert!(std::ptr::eq(run_b.core, cores[1]));
        assert_ne!(
            run_b.core.source().case().id(),
            cores[0].source().case().id()
        );
        let before = {
            let (decode, receiving, comparison) = inner.physical_owners().unwrap();
            (decode.usage(), receiving.usage(), comparison.usage())
        };
        {
            let loans_b = BrowserLoans::execution(inner, &global, &child_b).unwrap();
            loans_b.validate_application_source(&image).unwrap();
            assert!(loans_b.validate_relation_stamp(&stamp_a).is_err());
            assert!(loans_b.validate_controlled_source(&stimulus_a).is_err());
            assert!(
                loans_b
                    .validate_controlled_application(&image, &stimulus_a)
                    .is_err()
            );
        }
        let after = {
            let (decode, receiving, comparison) = inner.physical_owners().unwrap();
            (decode.usage(), receiving.usage(), comparison.usage())
        };
        assert_eq!(
            before, after,
            "wrong-child refusal precedes parse/copy/adoption/funding"
        );
        let mut loans_b = BrowserLoans::execution(inner, &global, &child_b).unwrap();
        let opening_b = run_b.openings(&mut loans_b).unwrap().next().unwrap();
        let stimulus_b = run_b
            .prepare_controlled_host(&opening_b, &mut loans_b)
            .unwrap();
        loans_b
            .validate_controlled_application(&image, &stimulus_b)
            .unwrap();
        stimulus_b.prepare_delivery(&mut loans_b).unwrap();
        // Actual physical owners were not created in this bookkeeping control;
        // dropping issued bindings therefore retains Abandoned debt as designed.
    });
}

#[test]
fn browser_execution_loans_02_application_execution_stamps_do_not_upgrade_or_downgrade() {
    with_compiled(|_, inner| {
        let global = BrowserSourceScope::prepare(inner).unwrap();
        let app_stamp = BrowserLoans::application(inner, &global)
            .unwrap()
            .prepare_relation_stamp()
            .unwrap();
        let child = ExecutionChild::prepare(&global, inner).unwrap();
        let exec_stamp = {
            let mut loans = BrowserLoans::execution(inner, &global, &child).unwrap();
            assert!(loans.validate_relation_stamp(&app_stamp).is_err());
            loans.prepare_relation_stamp().unwrap()
        };
        let app = BrowserLoans::application(inner, &global).unwrap();
        app.validate_relation_stamp(&app_stamp).unwrap();
        assert!(app.validate_relation_stamp(&exec_stamp).is_err());
        drop(child);
        app.validate_relation_stamp(&app_stamp).unwrap();
    });
}

#[test]
fn browser_execution_loans_03_global_facade_cannot_rebind_actual_a_input_under_child_b() {
    with_compiled(|compiled, inner| {
        let cores = controlled_clients(compiled);
        let global = BrowserSourceScope::prepare(inner).unwrap();
        let clients = BrowserClients {
            inner: inputs::BorrowedOriginalClients::new(compiled),
            scope: &global,
        };
        let mut exercised = false;
        clients
            .visit(
                &mut BrowserLoans::application(inner, &global).unwrap(),
                |client, application_loans| {
                    if exercised {
                        return Ok::<_, BrowserInputError>(());
                    }
                    let child_b =
                        ExecutionChild::prepare(&global, application_loans.inner).unwrap();
                    let _run_b = PreparedBrowserClientRun::prepare(
                        cores[1],
                        &global,
                        &child_b,
                        application_loans.inner,
                    )
                    .unwrap();
                    let before = {
                        let (d, r, c) = application_loans.inner.physical_owners().unwrap();
                        (d.usage(), r.usage(), c.usage())
                    };
                    let mut execution_loans =
                        BrowserLoans::execution(application_loans.inner, &global, &child_b)
                            .unwrap();
                    assert!(client.actions(&mut execution_loans).is_err());
                    assert!(
                        client
                            .prepare_controlled_host(&mut execution_loans, 0)
                            .is_err()
                    );
                    drop(execution_loans);
                    let (d, r, c) = application_loans.inner.physical_owners().unwrap();
                    assert_eq!(before, (d.usage(), r.usage(), c.usage()));
                    exercised = true;
                    Ok(())
                },
            )
            .unwrap();
        assert!(exercised);
    });
}

#[test]
fn browser_execution_loans_04_earlier_opening_operand_refuses_other_live_child() {
    with_compiled(|compiled, inner| {
        let cores = controlled_clients(compiled);
        let global = BrowserSourceScope::prepare(inner).unwrap();
        let child_a = ExecutionChild::prepare(&global, inner).unwrap();
        let run_a = PreparedBrowserClientRun::prepare(cores[0], &global, &child_a, inner).unwrap();
        let opening_a = run_a
            .openings(&mut BrowserLoans::execution(inner, &global, &child_a).unwrap())
            .unwrap()
            .next()
            .unwrap();
        let child_b = ExecutionChild::prepare(&global, inner).unwrap();
        let run_b = PreparedBrowserClientRun::prepare(cores[1], &global, &child_b, inner).unwrap();
        let before = {
            let (d, r, c) = inner.physical_owners().unwrap();
            (d.usage(), r.usage(), c.usage())
        };
        let mut loans_b = BrowserLoans::execution(inner, &global, &child_b).unwrap();
        assert!(
            run_b
                .prepare_controlled_host(&opening_a, &mut loans_b)
                .is_err()
        );
        drop(loans_b);
        let (d, r, c) = inner.physical_owners().unwrap();
        assert_eq!(before, (d.usage(), r.usage(), c.usage()));
    });
}
