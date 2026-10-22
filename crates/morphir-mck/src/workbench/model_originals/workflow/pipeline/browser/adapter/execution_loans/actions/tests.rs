//! Real reviewed compiler rows and SAME owners. Test consumption only advances
//! source input; it never claims a browser operation or workflow qualification.
use super::super::tests::{controlled_clients, with_compiled};
use super::*;
use crate::workbench::model_originals::workflow::source_compile::CompiledExecution;

#[test]
fn browser_action_cursor_01_all317_source_positions_and_first17_operands_are_preserved() {
    with_compiled(|compiled, inner| {
        let global = BrowserSourceScope::prepare(inner).unwrap();
        let mut total = 0;
        for (index, execution) in compiled.iter().enumerate() {
            let CompiledExecution::Current(core) = execution else {
                panic!("selected client input expected")
            };
            let child = ExecutionChild::prepare(&global, inner).unwrap();
            let run = PreparedBrowserClientRun::prepare(core, &global, &child, inner).unwrap();
            let mut loans = BrowserLoans::execution(inner, &global, &child).unwrap();
            let mut position = 0;
            while let Some(action) = run.next_action(&mut loans).unwrap() {
                assert_eq!(action.position(), position);
                if index == 0 {
                    match (position, action.kind()) {
                        (
                            0,
                            BrowserActionKind::BeginConnectedOpening {
                                scope: BrowserScope::Complete,
                                semantic: BrowserSemantic::Projection,
                                ..
                            },
                        ) => {}
                        (
                            1,
                            BrowserActionKind::AwaitConnectedBoundary {
                                pending,
                                boundary: BrowserConnectedBoundary::InspectionPending,
                            },
                        ) => assert_eq!(pending, "connected-opening-A"),
                        (3, BrowserActionKind::ExecutePendingCore { effect }) => {
                            assert_eq!(effect.attempt(), "attempt-A");
                            assert_eq!(effect.kind(), BrowserEffectKind::Inspection);
                            assert_eq!(effect.ordinal(), 0);
                        }
                        (
                            4,
                            BrowserActionKind::AwaitConnectedBoundary {
                                boundary: BrowserConnectedBoundary::OpeningSettled,
                                ..
                            },
                        ) => {}
                        (10, BrowserActionKind::SearchCurrent { query }) => {
                            assert_eq!(query, "fixture:core")
                        }
                        (14, BrowserActionKind::DisposeConnectedOpening { pending })
                        | (15, BrowserActionKind::AwaitConnectedDisposal { pending }) => {
                            assert_eq!(pending, "connected-opening-A")
                        }
                        (1 | 3 | 4 | 10 | 14 | 15, _) => {
                            panic!("actual authored action must not collapse to Unsupported")
                        }
                        _ => {}
                    }
                }
                action
                    .consume_source_only_for_test(&run, &mut loans)
                    .unwrap();
                position += 1;
            }
            if index == 0 {
                assert_eq!(position, 17);
            }
            assert_eq!(
                run.actions_terminal(),
                BrowserActionCursorTerminal::FullSourceActionsConsumed { actions: position }
            );
            assert!(run.next_action(&mut loans).unwrap().is_none());
            total += position;
        }
        assert_eq!(total, 317);
    });
}

#[test]
fn browser_action_cursor_02_foreign_run_child_refuses_before_owner_spending_or_cursor_touch() {
    with_compiled(|compiled, inner| {
        let cores = controlled_clients(compiled);
        let global = BrowserSourceScope::prepare(inner).unwrap();
        let child_a = ExecutionChild::prepare(&global, inner).unwrap();
        let child_b = ExecutionChild::prepare(&global, inner).unwrap();
        let a = PreparedBrowserClientRun::prepare(cores[0], &global, &child_a, inner).unwrap();
        let b = PreparedBrowserClientRun::prepare(cores[1], &global, &child_b, inner).unwrap();
        let action = {
            let mut loans = BrowserLoans::execution(inner, &global, &child_a).unwrap();
            a.next_action(&mut loans).unwrap().unwrap()
        };
        let before = {
            let (decode, receiving, compare) = inner.physical_owners().unwrap();
            (decode.usage(), receiving.usage(), compare.usage())
        };
        {
            let mut loans = BrowserLoans::execution(inner, &global, &child_b).unwrap();
            assert!(a.validate_action(&action, &loans).is_err());
            assert!(b.validate_action(&action, &loans).is_err());
            assert!(a.next_action(&mut loans).is_err());
        }
        let after = {
            let (decode, receiving, compare) = inner.physical_owners().unwrap();
            (decode.usage(), receiving.usage(), compare.usage())
        };
        assert_eq!(before, after);
        assert_eq!(
            b.actions_terminal(),
            BrowserActionCursorTerminal::NoneIssued
        );
        let mut loans = BrowserLoans::execution(inner, &global, &child_a).unwrap();
        action.consume_source_only_for_test(&a, &mut loans).unwrap();
        assert_eq!(a.next_action(&mut loans).unwrap().unwrap().position(), 1);
    });
}

#[test]
fn browser_action_cursor_03_one_outstanding_and_drop_refuse_same_run_continuation() {
    with_compiled(|compiled, inner| {
        let core = controlled_clients(compiled)[0];
        let global = BrowserSourceScope::prepare(inner).unwrap();
        let child = ExecutionChild::prepare(&global, inner).unwrap();
        let run = PreparedBrowserClientRun::prepare(core, &global, &child, inner).unwrap();
        let mut loans = BrowserLoans::execution(inner, &global, &child).unwrap();
        assert_eq!(
            run.actions_terminal(),
            BrowserActionCursorTerminal::NoneIssued
        );
        let current = run.next_action(&mut loans).unwrap().unwrap();
        assert_eq!(current.position(), 0);
        assert!(run.next_action(&mut loans).is_err());
        drop(current);
        assert!(matches!(
            run.actions_terminal(),
            BrowserActionCursorTerminal::Refused {
                position: 0,
                cause: BrowserActionCursorFault::AlreadyOutstanding
            }
        ));
        assert!(run.next_action(&mut loans).is_err());
    });
}

#[test]
fn browser_action_cursor_04_prior_owner_refusal_precedes_cursor_issuance() {
    with_compiled(|compiled, inner| {
        let core = controlled_clients(compiled)[0];
        let global = BrowserSourceScope::prepare(inner).unwrap();
        let child = ExecutionChild::prepare(&global, inner).unwrap();
        let run = PreparedBrowserClientRun::prepare(core, &global, &child, inner).unwrap();
        let mut loans = BrowserLoans::execution(inner, &global, &child).unwrap();
        assert!(
            loans
                .reserve_controlled_host_storage(usize::MAX, 0, 0)
                .is_err()
        );
        let first = run.next_action(&mut loans).err().unwrap();
        let second = run.next_action(&mut loans).err().unwrap();
        assert_eq!(format!("{first:?}"), format!("{second:?}"));
        assert_eq!(
            run.actions_terminal(),
            BrowserActionCursorTerminal::NoneIssued
        );
    });
}

#[test]
fn browser_action_cursor_05_zero_and_one_byte_remaining_refuse_before_run_cursor_exists() {
    for leave in [0, 1] {
        with_compiled(|compiled, inner| {
            let core = controlled_clients(compiled)[0];
            let global = BrowserSourceScope::prepare(inner).unwrap();
            let child = ExecutionChild::prepare(&global, inner).unwrap();
            {
                let (_, receiving, _) = inner.physical_owners().unwrap();
                let remaining =
                    8_388_608 - usize::try_from(receiving.usage().retained_bytes()).unwrap();
                receiving
                    .reserve_span(
                        InstalledObservationResource::RetainedBytes,
                        remaining - leave,
                    )
                    .unwrap();
            }
            let failure = PreparedBrowserClientRun::prepare(core, &global, &child, inner)
                .err()
                .unwrap();
            assert!(matches!(
                failure.cause,
                inputs::BrowserInputFault::Receiving(InstalledObservationFault::Resource {
                    kind: InstalledObservationResource::RetainedBytes,
                    ..
                })
            ));
            assert_eq!(child.terminal(), BrowserSourceTerminal::Quiescent);
        });
    }
}

#[test]
fn browser_source_operation_01_prepared_source_operand_keeps_exact_action_outstanding() {
    with_compiled(|compiled, inner| {
        let core = controlled_clients(compiled)[0];
        let global = BrowserSourceScope::prepare(inner).unwrap();
        let child = ExecutionChild::prepare(&global, inner).unwrap();
        let run = PreparedBrowserClientRun::prepare(core, &global, &child, inner).unwrap();
        let mut loans = BrowserLoans::execution(inner, &global, &child).unwrap();
        let action = run.next_action(&mut loans).unwrap().unwrap();
        let BrowserActionKind::BeginConnectedOpening {
            source,
            project_id,
            pending,
            ..
        } = action.kind()
        else {
            panic!("genuine first action");
        };
        let prepared = PreparedConnectedOpening::prepare(&run, action, &mut loans).unwrap();
        assert_eq!(prepared.provider_id(), source.provider_id);
        assert_eq!(prepared.locator(), source.locator);
        assert_eq!(prepared.project_id(), project_id);
        assert_eq!(prepared.pending_alias(), pending);
        assert_eq!(prepared.position(), 0);
        assert!(matches!(
            run.actions_terminal(),
            BrowserActionCursorTerminal::Incomplete {
                consumed: 0,
                pending: Some(0),
                ..
            }
        ));
        // Preparing DATA is never an actual selection receipt.
        drop(prepared);
        assert!(matches!(
            run.actions_terminal(),
            BrowserActionCursorTerminal::Refused {
                position: 0,
                cause: BrowserActionCursorFault::OutstandingAbandoned
            }
        ));
    });
}

#[test]
fn browser_source_operation_02_foreign_child_refuses_before_preparation_spending() {
    with_compiled(|compiled, inner| {
        let cores = controlled_clients(compiled);
        let global = BrowserSourceScope::prepare(inner).unwrap();
        let a_child = ExecutionChild::prepare(&global, inner).unwrap();
        let b_child = ExecutionChild::prepare(&global, inner).unwrap();
        let a = PreparedBrowserClientRun::prepare(cores[0], &global, &a_child, inner).unwrap();
        let b = PreparedBrowserClientRun::prepare(cores[1], &global, &b_child, inner).unwrap();
        let action = {
            let mut loans = BrowserLoans::execution(inner, &global, &a_child).unwrap();
            a.next_action(&mut loans).unwrap().unwrap()
        };
        let before = {
            let (decode, receiving, comparison) = inner.physical_owners().unwrap();
            (decode.usage(), receiving.usage(), comparison.usage())
        };
        let mut loans = BrowserLoans::execution(inner, &global, &b_child).unwrap();
        assert!(PreparedConnectedOpening::prepare(&b, action, &mut loans).is_err());
        let after = {
            let (decode, receiving, comparison) = inner.physical_owners().unwrap();
            (decode.usage(), receiving.usage(), comparison.usage())
        };
        assert_eq!(before, after);
        assert_eq!(
            b.actions_terminal(),
            BrowserActionCursorTerminal::NoneIssued
        );
    });
}

#[test]
fn browser_source_operation_03_funding_failure_cannot_settle_action() {
    with_compiled(|compiled, inner| {
        let core = controlled_clients(compiled)[0];
        let global = BrowserSourceScope::prepare(inner).unwrap();
        let child = ExecutionChild::prepare(&global, inner).unwrap();
        let run = PreparedBrowserClientRun::prepare(core, &global, &child, inner).unwrap();
        let action = {
            let mut loans = BrowserLoans::execution(inner, &global, &child).unwrap();
            run.next_action(&mut loans).unwrap().unwrap()
        };
        {
            let (_, receiving, _) = inner.physical_owners().unwrap();
            let left = 8_388_608 - usize::try_from(receiving.usage().retained_bytes()).unwrap();
            receiving
                .reserve_span(InstalledObservationResource::RetainedBytes, left)
                .unwrap();
        }
        let mut loans = BrowserLoans::execution(inner, &global, &child).unwrap();
        assert!(PreparedConnectedOpening::prepare(&run, action, &mut loans).is_err());
        assert!(matches!(
            run.actions_terminal(),
            BrowserActionCursorTerminal::Refused {
                position: 0,
                cause: BrowserActionCursorFault::OutstandingAbandoned
            }
        ));
    });
}

#[test]
fn browser_source_operation_04_choice_plan_uses_same_prepared_reply_rows_without_selection() {
    with_compiled(|compiled, inner| {
        let core = controlled_clients(compiled)[0];
        let global = BrowserSourceScope::prepare(inner).unwrap();
        let child = ExecutionChild::prepare(&global, inner).unwrap();
        let run = PreparedBrowserClientRun::prepare(core, &global, &child, inner).unwrap();
        let mut loans = BrowserLoans::execution(inner, &global, &child).unwrap();
        let opening = run.openings(&mut loans).unwrap().next().unwrap();
        let stimulus = run.prepare_controlled_host(&opening, &mut loans).unwrap();
        let action = run.next_action(&mut loans).unwrap().unwrap();
        let mut prepared = PreparedConnectedOpening::prepare(&run, action, &mut loans).unwrap();
        let expected_identity_bytes =
            prepared.provider_id().len() + prepared.locator().len() + prepared.project_id().len();
        let plan = prepared
            .prepare_choice_funding(&stimulus, &mut loans)
            .unwrap();
        assert_eq!(plan.source_rows(), 1);
        assert_eq!(plan.project_rows(), 1);
        assert_eq!(plan.identity_bytes(), expected_identity_bytes);
        assert!(matches!(
            run.actions_terminal(),
            BrowserActionCursorTerminal::Incomplete {
                consumed: 0,
                pending: Some(0),
                ..
            }
        ));
        // Prepared literal DATA/choice bounds never attest a network exchange,
        // nominal application selection or a joined controlled host.
    });
}

#[test]
fn browser_source_operation_05_foreign_prepared_replies_refuse_before_parser_or_receiving_debit() {
    with_compiled(|compiled, inner| {
        let cores = controlled_clients(compiled);
        let global = BrowserSourceScope::prepare(inner).unwrap();
        let a_child = ExecutionChild::prepare(&global, inner).unwrap();
        let b_child = ExecutionChild::prepare(&global, inner).unwrap();
        let a = PreparedBrowserClientRun::prepare(cores[0], &global, &a_child, inner).unwrap();
        let b = PreparedBrowserClientRun::prepare(cores[1], &global, &b_child, inner).unwrap();
        let foreign = {
            let mut loans = BrowserLoans::execution(inner, &global, &b_child).unwrap();
            let opening = b.openings(&mut loans).unwrap().next().unwrap();
            b.prepare_controlled_host(&opening, &mut loans).unwrap()
        };
        let mut prepared = {
            let mut loans = BrowserLoans::execution(inner, &global, &a_child).unwrap();
            let action = a.next_action(&mut loans).unwrap().unwrap();
            PreparedConnectedOpening::prepare(&a, action, &mut loans).unwrap()
        };
        let before = {
            let (decode, receiving, comparison) = inner.physical_owners().unwrap();
            (decode.usage(), receiving.usage(), comparison.usage())
        };
        let mut loans = BrowserLoans::execution(inner, &global, &a_child).unwrap();
        assert!(
            prepared
                .prepare_choice_funding(&foreign, &mut loans)
                .is_err()
        );
        let after = {
            let (decode, receiving, comparison) = inner.physical_owners().unwrap();
            (decode.usage(), receiving.usage(), comparison.usage())
        };
        assert_eq!(before, after);
    });
}

pub(in crate::workbench::model_originals::workflow::pipeline::browser) fn with_source_controller_lifetime(
    action: impl FnOnce(SourceControllerLifetime, &mut BrowserLoans<'_, '_>),
) {
    with_source_controller_fixture(
        |lifetime, inner, global, child| {
            let mut loans = BrowserLoans::execution(inner, global, child).unwrap();
            action(lifetime, &mut loans);
        },
        |_| {},
    );
}

pub(in crate::workbench::model_originals::workflow::pipeline::browser) fn with_source_controller_limits(
    limits: &[u8],
    action: impl FnOnce(SourceControllerLifetime, &mut BrowserLoans<'_, '_>),
) {
    with_source_controller_fixture_limits(
        limits,
        |lifetime, inner, global, child| {
            let mut loans = BrowserLoans::execution(inner, global, child).unwrap();
            action(lifetime, &mut loans);
        },
        |_| {},
    );
}

pub(in crate::workbench::model_originals::workflow::pipeline::browser) fn with_foreign_source_controller_lifetime(
    action: impl FnOnce(SourceControllerLifetime, &mut BrowserLoans<'_, '_>),
) {
    with_source_controller_fixture(
        |lifetime, inner, global, _| {
            let other = ExecutionChild::prepare(global, inner).unwrap();
            let mut loans = BrowserLoans::execution(inner, global, &other).unwrap();
            action(lifetime, &mut loans);
        },
        |_| {},
    );
}

pub(in crate::workbench::model_originals::workflow::pipeline::browser) fn with_revoked_source_controller_lifetime<
    R,
>(
    prepare: impl FnOnce(SourceControllerLifetime, &mut BrowserLoans<'_, '_>) -> R,
    after_revoke: impl FnOnce(R),
) {
    with_source_controller_fixture(
        |lifetime, inner, global, child| {
            let mut loans = BrowserLoans::execution(inner, global, child).unwrap();
            prepare(lifetime, &mut loans)
        },
        after_revoke,
    );
}

fn with_source_controller_fixture<R>(
    prepare: impl FnOnce(
        SourceControllerLifetime,
        &mut inputs::BrowserOwnerLoans<'_>,
        &BrowserSourceScope,
        &ExecutionChild,
    ) -> R,
    finish: impl FnOnce(R),
) {
    with_source_controller_fixture_limits(
        br#"{"rpcFrames":"checker-capture","retainedBytes":8388608,"stdoutPrefixBytes":4096,"stderrPrefixBytes":4096,"snapshotReadBytes":1048576,"byteVisits":8388608,"records":0}"#,
        prepare, finish,
    );
}

fn with_source_controller_fixture_limits<R>(
    limits: &[u8],
    prepare: impl FnOnce(
        SourceControllerLifetime,
        &mut inputs::BrowserOwnerLoans<'_>,
        &BrowserSourceScope,
        &ExecutionChild,
    ) -> R,
    finish: impl FnOnce(R),
) {
    use crate::workbench::model_originals::workflow::pipeline::browser::{
        BrowserDocumentBounds, BrowserRowCollection,
    };
    super::super::tests::with_compiled_limits(limits, |compiled, inner| {
        let core = controlled_clients(compiled)[0];
        let global = BrowserSourceScope::prepare(inner).unwrap();
        let mut child = ExecutionChild::prepare(&global, inner).unwrap();
        let run = PreparedBrowserClientRun::prepare(core, &global, &child, inner).unwrap();
        let mut loans = BrowserLoans::execution(inner, &global, &child).unwrap();
        let opening = run.openings(&mut loans).unwrap().next().unwrap();
        let stimulus = run.prepare_controlled_host(&opening, &mut loans).unwrap();
        let mut collection = BrowserRowCollection::prepare(
            &run,
            &mut loans,
            BrowserDocumentBounds::new(1, 128, 128).unwrap(),
        )
        .unwrap();
        let mut producer = collection
            .producer()
            .issue(&run, &opening, &mut loans)
            .unwrap();
        let transcript = producer
            .prepare_host_transcript(
                &mut loans,
                &stimulus,
                std::time::Instant::now() + std::time::Duration::from_secs(10),
            )
            .unwrap();
        let issued = run.next_action(&mut loans).unwrap().unwrap();
        let prepared = PreparedConnectedOpening::prepare(&run, issued, &mut loans).unwrap();
        let (action_owner, lifetime) = prepared
            .into_controller_parts(&producer, &transcript, &stimulus, &mut loans)
            .unwrap();
        drop(loans);
        let result = prepare(lifetime, inner, &global, &child);
        drop(action_owner);
        drop(opening);
        drop(run);
        // The real issuing scope revokes after the callback/borrowed run
        // ends; no synthetic identity or alternate revocation broker.
        child.revoke();
        finish(result);
    });
}

#[test]
fn browser_source_operation_06_lifetime_keeps_actual_host_end_and_outstanding_source0() {
    use crate::workbench::model_originals::workflow::pipeline::browser::{
        BrowserDocumentBounds, BrowserRowCollection,
    };
    with_compiled(|compiled, inner| {
        let core = controlled_clients(compiled)[0];
        let global = BrowserSourceScope::prepare(inner).unwrap();
        let child = ExecutionChild::prepare(&global, inner).unwrap();
        let run = PreparedBrowserClientRun::prepare(core, &global, &child, inner).unwrap();
        let mut loans = BrowserLoans::execution(inner, &global, &child).unwrap();
        let opening = run.openings(&mut loans).unwrap().next().unwrap();
        let stimulus = run.prepare_controlled_host(&opening, &mut loans).unwrap();
        let mut collection = BrowserRowCollection::prepare(
            &run,
            &mut loans,
            BrowserDocumentBounds::new(1, 128, 128).unwrap(),
        )
        .unwrap();
        let mut producer = collection
            .producer()
            .issue(&run, &opening, &mut loans)
            .unwrap();
        let end = std::time::Instant::now() + std::time::Duration::from_secs(10);
        let transcript = producer
            .prepare_host_transcript(&mut loans, &stimulus, end)
            .unwrap();
        let action = run.next_action(&mut loans).unwrap().unwrap();
        let prepared = PreparedConnectedOpening::prepare(&run, action, &mut loans).unwrap();
        let (action_owner, lifetime) = prepared
            .into_controller_parts(&producer, &transcript, &stimulus, &mut loans)
            .unwrap();
        assert_eq!(lifetime.end(), end);
        lifetime.validate(&loans).unwrap();
        assert_eq!(action_owner.position(), 0);
        assert!(matches!(
            run.actions_terminal(),
            BrowserActionCursorTerminal::Incomplete {
                pending: Some(0),
                ..
            }
        ));
        assert_eq!(
            child.terminal(),
            BrowserSourceTerminal::Unfinished { bindings: 2 }
        );
    });
}

#[test]
fn browser_source_operation_07_same_child_other_host_journal_refuses_before_debit() {
    use crate::workbench::model_originals::workflow::pipeline::browser::{
        BrowserDocumentBounds, BrowserRowCollection,
    };
    with_compiled(|compiled, inner| {
        let core = controlled_clients(compiled)[0];
        let global = BrowserSourceScope::prepare(inner).unwrap();
        let child = ExecutionChild::prepare(&global, inner).unwrap();
        let run = PreparedBrowserClientRun::prepare(core, &global, &child, inner).unwrap();
        let mut loans = BrowserLoans::execution(inner, &global, &child).unwrap();
        let opening = run.openings(&mut loans).unwrap().next().unwrap();
        let stimulus = run.prepare_controlled_host(&opening, &mut loans).unwrap();
        let mut a = BrowserRowCollection::prepare(
            &run,
            &mut loans,
            BrowserDocumentBounds::new(1, 128, 128).unwrap(),
        )
        .unwrap();
        let mut b = BrowserRowCollection::prepare(
            &run,
            &mut loans,
            BrowserDocumentBounds::new(1, 128, 128).unwrap(),
        )
        .unwrap();
        let producer_a = a.producer().issue(&run, &opening, &mut loans).unwrap();
        let mut producer_b = b.producer().issue(&run, &opening, &mut loans).unwrap();
        let transcript_b = producer_b
            .prepare_host_transcript(
                &mut loans,
                &stimulus,
                std::time::Instant::now() + std::time::Duration::from_secs(10),
            )
            .unwrap();
        let action = run.next_action(&mut loans).unwrap().unwrap();
        let prepared = PreparedConnectedOpening::prepare(&run, action, &mut loans).unwrap();
        let before = {
            let (decode, receiving, comparison) = loans.inner.physical_owners().unwrap();
            (decode.usage(), receiving.usage(), comparison.usage())
        };
        assert!(
            prepared
                .into_controller_parts(&producer_a, &transcript_b, &stimulus, &mut loans)
                .is_err()
        );
        let after = {
            let (decode, receiving, comparison) = loans.inner.physical_owners().unwrap();
            (decode.usage(), receiving.usage(), comparison.usage())
        };
        assert_eq!(before, after);
    });
}
