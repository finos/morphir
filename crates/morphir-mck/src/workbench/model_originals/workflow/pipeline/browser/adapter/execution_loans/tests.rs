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
    let checker = Policy::from_document(
        &Document::parse_unsigned_counts(include_bytes!(concat!(
            env!("CARGO_MANIFEST_DIR"),
            "/src/workbench/model_originals/workflow/pipeline_controls/explicit-test-policy.json"
        )))
        .unwrap(),
    )
    .unwrap();
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

pub(super) fn controlled_clients<'a, 'case, 'sources, 'raw, 'supplied>(
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
