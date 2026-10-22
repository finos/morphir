//! Genuine source0 preparation and immutable factual-cache controls.
//! No browser, native startup or successful source settlement is asserted.
use super::super::tests::{controlled_clients, with_compiled};
use super::*;
use crate::workbench::model_originals::workflow::pipeline::browser::{
    BrowserDocumentBounds, BrowserDocumentProducer, BrowserHostTranscript, BrowserRowCollection,
    ControlledHostStimulus,
};
use std::time::{Duration, Instant};

pub(super) fn with_opening_setup(
    original_for: Duration,
    operation: impl FnOnce(
        &PreparedBrowserClientRun<'_, '_, '_, '_, '_, '_>,
        &mut BrowserLoans<'_, '_>,
        &mut BrowserDocumentProducer,
        &BrowserHostTranscript,
        &ControlledHostStimulus,
        Instant,
    ),
) {
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
            BrowserDocumentBounds::new(2, 1024, 512).unwrap(),
        )
        .unwrap();
        let mut producer = collection
            .producer()
            .issue(&run, &opening, &mut loans)
            .unwrap();
        let end = Instant::now() + original_for;
        let transcript = producer
            .prepare_host_transcript(&mut loans, &stimulus, end)
            .unwrap();
        operation(&run, &mut loans, &mut producer, &transcript, &stimulus, end);
    });
}

#[test]
fn browser_owned_source_01_bound_factory_reborrows_same_owned_token_without_consuming() {
    with_opening_setup(
        Duration::from_secs(10),
        |run, loans, producer, transcript, stimulus, end| {
            let action = run.next_action(loans).unwrap().unwrap();
            let (owned, preparation) = action
                .prepare_connected_controller(producer, transcript, stimulus, loans)
                .unwrap_or_else(|_| panic!("genuine source0 preparation"));
            assert_eq!(owned.position(), 0);
            assert_eq!(preparation.end(), end);
            let borrowed = owned
                .connected_opening(producer, transcript, stimulus, loans)
                .unwrap();
            assert_eq!(
                borrowed
                    .validate_host(producer, transcript, stimulus, loans)
                    .unwrap(),
                end
            );
            drop(borrowed);
            assert!(matches!(
                run.actions_terminal(),
                BrowserActionCursorTerminal::Incomplete {
                    consumed: 0,
                    pending: Some(0),
                    ..
                }
            ));
            // This is an unlaunched owner with genuine source debt, not joined work.
            // Dropping it cannot advance source0 or retire the native host's debt.
            drop(preparation);
            drop(owned);
        },
    );
}

#[test]
fn browser_owned_source_02_expired_original_refuses_before_selector_allocation_and_retains_cause() {
    with_opening_setup(
        Duration::from_millis(100),
        |run, loans, producer, transcript, stimulus, end| {
            let action = run.next_action(loans).unwrap().unwrap();
            std::thread::sleep(
                end.saturating_duration_since(Instant::now()) + Duration::from_millis(1),
            );
            let before = {
                let (decode, receiving, comparison) = loans.inner.physical_owners().unwrap();
                (decode.usage(), receiving.usage(), comparison.usage())
            };
            let failure =
                match action.prepare_connected_controller(producer, transcript, stimulus, loans) {
                    Err(failure) => failure,
                    Ok(_) => panic!("expired original end must not copy owned selectors"),
                };
            failure.inspect_cause(|cause| assert!(matches!(cause,
            BrowserActionIssueError::Host(crate::workbench::model_originals::workflow::pipeline::browser::BrowserHostTranscriptFault::End)
        )));
            drop(failure);
            let after = {
                let (decode, receiving, comparison) = loans.inner.physical_owners().unwrap();
                (decode.usage(), receiving.usage(), comparison.usage())
            };
            assert_eq!(before, after);
            assert!(matches!(
                run.actions_terminal(),
                BrowserActionCursorTerminal::Refused {
                    position: 0,
                    cause: BrowserActionCursorFault::PreparationRefused,
                }
            ));
        },
    );
}

#[test]
fn browser_listener_permit_01_scoped_original_end_is_data_not_start_or_completion() {
    with_opening_setup(
        Duration::from_secs(10),
        |run, loans, producer, transcript, stimulus, end| {
            let action = run.next_action(loans).unwrap().unwrap();
            let sdk = action
                .connected_opening(producer, transcript, stimulus, loans)
                .unwrap();
            let seen = sdk
                .with_prepared_listener_start(loans, |permit| permit.original_end())
                .unwrap();
            assert_eq!(seen, end);
            assert!(matches!(
                run.actions_terminal(),
                BrowserActionCursorTerminal::Incomplete {
                    consumed: 0,
                    pending: Some(0),
                    ..
                }
            ));
        },
    );
}

#[test]
fn browser_listener_permit_02_actual_source_abandoned_refuses_before_callback() {
    with_opening_setup(
        Duration::from_secs(10),
        |run, loans, producer, transcript, stimulus, _end| {
            let action = run.next_action(loans).unwrap().unwrap();
            let sdk = action
                .connected_opening(producer, transcript, stimulus, loans)
                .unwrap();
            let spare_opening = run.openings(loans).unwrap().next().unwrap();
            let spare = run.prepare_controlled_host(&spare_opening, loans).unwrap();
            drop(spare); // Actual SAME child binding drop records Abandoned.
            let mut called = false;
            let refused = sdk.with_prepared_listener_start(loans, |_permit| {
                called = true;
            });
            assert!(!called);
            assert!(matches!(refused, Err(BrowserActionIssueError::Input(error))
            if error.source_cause() == Some(BrowserSourceFault::Abandoned)));
        },
    );
}

#[test]
fn browser_listener_permit_03_document_fault_or_original_end_refuses_before_callback() {
    with_opening_setup(
        Duration::from_secs(10),
        |run, loans, producer, transcript, stimulus, end| {
            let action = run.next_action(loans).unwrap().unwrap();
            let sdk = action
                .connected_opening(producer, transcript, stimulus, loans)
                .unwrap();
            producer
                .record_frame(loans, &[], end)
                .err()
                .expect("genuine document framing fault");
            let mut called = false;
            let refused = sdk.with_prepared_listener_start(loans, |_permit| {
                called = true;
            });
            assert!(!called);
            assert!(matches!(refused, Err(BrowserActionIssueError::Collection(
            crate::workbench::model_originals::workflow::pipeline::browser::BrowserCollectionFault::Framing
        ))));
        },
    );
    with_opening_setup(
        Duration::from_millis(100),
        |run, loans, producer, transcript, stimulus, end| {
            let action = run.next_action(loans).unwrap().unwrap();
            let sdk = action
                .connected_opening(producer, transcript, stimulus, loans)
                .unwrap();
            std::thread::sleep(
                end.saturating_duration_since(Instant::now()) + Duration::from_millis(1),
            );
            let mut called = false;
            let refused = sdk.with_prepared_listener_start(loans, |_permit| {
                called = true;
            });
            assert!(!called);
            assert!(matches!(refused, Err(BrowserActionIssueError::Host(
            crate::workbench::model_originals::workflow::pipeline::browser::BrowserHostTranscriptFault::End
        ))));
        },
    );
}

#[test]
fn browser_source_receipts_01_genuine_run_starts_with_no_requested_operations() {
    with_compiled(|compiled, inner| {
        let core = controlled_clients(compiled)[0];
        let global = BrowserSourceScope::prepare(inner).unwrap();
        let child = ExecutionChild::prepare(&global, inner).unwrap();
        let run = PreparedBrowserClientRun::prepare(core, &global, &child, inner).unwrap();
        let before = run.connected_operations();
        assert_eq!(
            before.opening(),
            BrowserConnectedOperationObservation::NotRequested
        );
        assert_eq!(
            before.inspection_boundary(),
            BrowserConnectedOperationObservation::NotRequested
        );
        let mut loans = BrowserLoans::execution(inner, &global, &child).unwrap();
        let token = run.next_action(&mut loans).unwrap().unwrap();
        // Issuing source DATA is not requesting an actual controller command.
        assert_eq!(run.connected_operations(), before);
        drop(token);
        let (terminal, retained, first_issue) = run.into_action_capture();
        assert!(first_issue.is_none());
        assert_eq!(retained.snapshot(), before);
        assert!(matches!(
            terminal,
            BrowserActionCursorTerminal::Refused {
                cause: BrowserActionCursorFault::OutstandingAbandoned,
                ..
            }
        ));
    });
}

#[test]
fn browser_source_receipts_02_requested_drop_and_late_data_do_not_mutate_prior_cut() {
    with_compiled(|_, inner| {
        let journal = SourceOperationJournal::prepare(inner).unwrap();
        let mut pending = journal.requested(SourceOperationKind::Opening).unwrap();
        let cut = journal.snapshot();
        assert_eq!(
            cut.opening(),
            BrowserConnectedOperationObservation::Requested {
                reply: None,
                first_control_fault: None,
            }
        );
        pending.fault(BrowserConnectedControlFault::Cancelled);
        drop(pending);
        assert_eq!(
            cut.opening(),
            BrowserConnectedOperationObservation::Requested {
                reply: None,
                first_control_fault: None,
            }
        );
        assert_eq!(
            journal.snapshot().opening(),
            BrowserConnectedOperationObservation::Requested {
                reply: None,
                first_control_fault: Some(BrowserConnectedControlFault::Cancelled),
            }
        );
        assert!(journal.requested(SourceOperationKind::Opening).is_err());
        assert_eq!(
            journal.snapshot().inspection_boundary(),
            BrowserConnectedOperationObservation::NotRequested
        );
    });
}

#[test]
fn browser_controller_step_01_exact_source_original_end_and_outstanding_token() {
    with_opening_setup(
        Duration::from_secs(10),
        |run, loans, producer, transcript, stimulus, end| {
            let action = run.next_action(loans).unwrap().unwrap();
            let sdk = action
                .connected_opening(producer, transcript, stimulus, loans)
                .unwrap();
            let seen = sdk
                .with_prepared_controller_step(loans, |permit| permit.original_end())
                .unwrap();
            assert_eq!(seen, end);
            assert!(matches!(
                run.actions_terminal(),
                BrowserActionCursorTerminal::Incomplete {
                    consumed: 0,
                    pending: Some(0),
                    ..
                }
            ));
        },
    );
}

#[test]
fn browser_controller_step_02_original_expiry_refuses_callback_before_permit_allocation() {
    with_opening_setup(
        Duration::from_millis(100),
        |run, loans, producer, transcript, stimulus, end| {
            let action = run.next_action(loans).unwrap().unwrap();
            let sdk = action
                .connected_opening(producer, transcript, stimulus, loans)
                .unwrap();
            std::thread::sleep(
                end.saturating_duration_since(Instant::now()) + Duration::from_millis(1),
            );
            let before = {
                let (decode, receiving, comparison) = loans.inner.physical_owners().unwrap();
                (decode.usage(), receiving.usage(), comparison.usage())
            };
            let mut called = false;
            let refused = sdk.with_prepared_controller_step(loans, |_| {
                called = true;
            });
            assert!(!called);
            assert!(matches!(refused, Err(BrowserActionIssueError::Host(
            crate::workbench::model_originals::workflow::pipeline::browser::BrowserHostTranscriptFault::End
        ))));
            let after = {
                let (decode, receiving, comparison) = loans.inner.physical_owners().unwrap();
                (decode.usage(), receiving.usage(), comparison.usage())
            };
            // The existing currentness guard pays its actual validation visits.
            // It must refuse before retaining a new permit/wrapper or dispatching.
            assert_eq!(before.0.slots, after.0.slots);
            assert_eq!(before.1.retained_bytes(), after.1.retained_bytes());
            assert_eq!(before.2, after.2);
        },
    );
}

#[test]
fn browser_source_settlement_01_foreign_sealed_data_cannot_consume_genuine_action() {
    with_opening_setup(
        Duration::from_secs(10),
        |run, loans, producer, transcript, stimulus, _| {
            let action = run.next_action(loans).unwrap().unwrap();
            let (mut owned, lifetime) = action
                .prepare_connected_controller(producer, transcript, stimulus, loans)
                .unwrap();
            let foreign = SourceOperationJournal::prepare(loans.inner).unwrap();
            let measured = foreign
                .requested(SourceOperationKind::Opening)
                .unwrap()
                .opening(BrowserOpeningSelectionReply::ProjectSelected)
                .ok()
                .unwrap();
            assert!(matches!(
                owned.settle_controller_reply(&measured, &lifetime, loans),
                Err(BrowserActionIssueError::Cursor(
                    BrowserActionCursorFault::ForeignAction
                ))
            ));
            assert!(matches!(
                run.actions_terminal(),
                BrowserActionCursorTerminal::Incomplete {
                    consumed: 0,
                    pending: Some(0),
                    ..
                }
            ));
        },
    );
}

#[test]
fn browser_source_settlement_02_matching_unaccepted_data_is_not_logical_success() {
    with_opening_setup(
        Duration::from_secs(10),
        |run, loans, producer, transcript, stimulus, _| {
            let action = run.next_action(loans).unwrap().unwrap();
            let (mut owned, lifetime) = action
                .prepare_connected_controller(producer, transcript, stimulus, loans)
                .unwrap();
            // Private DATA constructor control, not a controller/client execution.
            let measured = lock(&run.actions)
                .operations
                .requested(SourceOperationKind::Opening)
                .unwrap()
                .opening(BrowserOpeningSelectionReply::Unavailable)
                .ok()
                .unwrap();
            assert!(matches!(
                owned.settle_controller_reply(&measured, &lifetime, loans),
                Err(BrowserActionIssueError::Cursor(
                    BrowserActionCursorFault::UnsupportedOperation
                ))
            ));
            assert!(matches!(
                run.actions_terminal(),
                BrowserActionCursorTerminal::Incomplete {
                    consumed: 0,
                    pending: Some(0),
                    ..
                }
            ));
        },
    );
}

#[test]
fn browser_source_settlement_03_earlier_data_cannot_settle_after_original_end() {
    with_opening_setup(
        Duration::from_millis(100),
        |run, loans, producer, transcript, stimulus, end| {
            let action = run.next_action(loans).unwrap().unwrap();
            let (mut owned, lifetime) = action
                .prepare_connected_controller(producer, transcript, stimulus, loans)
                .unwrap();
            let measured = lock(&run.actions)
                .operations
                .requested(SourceOperationKind::Opening)
                .unwrap()
                .opening(BrowserOpeningSelectionReply::ProjectSelected)
                .ok()
                .unwrap();
            std::thread::sleep(
                end.saturating_duration_since(Instant::now()) + Duration::from_millis(1),
            );
            assert!(matches!(owned.settle_controller_reply(&measured,&lifetime,loans),Err(BrowserActionIssueError::Host(crate::workbench::model_originals::workflow::pipeline::browser::BrowserHostTranscriptFault::End))));
            assert!(matches!(
                run.actions_terminal(),
                BrowserActionCursorTerminal::Incomplete {
                    consumed: 0,
                    pending: Some(0),
                    ..
                }
            ));
        },
    );
}
