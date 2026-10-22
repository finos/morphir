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
