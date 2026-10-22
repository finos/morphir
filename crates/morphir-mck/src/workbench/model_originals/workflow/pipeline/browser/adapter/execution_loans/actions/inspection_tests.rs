//! Genuine source action relationships with private literal receipt DATA.
//! These controls do not execute a controller, browser or inspection core.
use super::super::operation_tests::with_opening_setup;
use super::super::*;
use super::*;
use std::time::{Duration, Instant};

#[test]
fn browser_inspection_action_01_exact_next_action_lends_same_host_without_consumption() {
    with_opening_setup(
        Duration::from_secs(10),
        |run, loans, producer, transcript, stimulus, end| {
            let action0 = run.next_action(loans).unwrap().unwrap();
            let (mut opening, lifetime) = action0
                .prepare_connected_controller(producer, transcript, stimulus, loans)
                .unwrap();
            // Private sealed DATA establishes only the logical source relationship.
            let measured = lock(&run.actions)
                .operations
                .requested(SourceOperationKind::Opening)
                .unwrap()
                .opening(BrowserOpeningSelectionReply::ProjectSelected)
                .ok()
                .unwrap();
            opening
                .settle_controller_reply(&measured, &lifetime, loans)
                .unwrap();
            drop(opening);
            let action1 = run.next_action(loans).unwrap().unwrap();
            assert_eq!(action1.position(), 1);
            let owned = BrowserOwnedInspectionBoundary::prepare(action1, &lifetime, loans)
                .unwrap_or_else(|_| panic!("genuine source1"));
            let borrowed = owned.source(&lifetime, loans).unwrap();
            assert_eq!(
                borrowed
                    .validate_host(producer, transcript, stimulus, loans)
                    .unwrap(),
                end
            );
            assert_eq!(
                borrowed
                    .with_prepared_controller_step(loans, |permit| permit.original_end())
                    .unwrap(),
                end
            );
            assert!(matches!(
                run.actions_terminal(),
                BrowserActionCursorTerminal::Incomplete {
                    consumed: 1,
                    pending: Some(1),
                    ..
                }
            ));
            drop(borrowed);
            drop(owned);
            assert!(matches!(
                run.actions_terminal(),
                BrowserActionCursorTerminal::Refused {
                    position: 1,
                    cause: BrowserActionCursorFault::OutstandingAbandoned
                }
            ));
        },
    );
}

#[test]
fn browser_inspection_action_02_same_child_foreign_run_refuses_before_funding() {
    with_opening_setup(
        Duration::from_secs(10),
        |run, loans, producer, transcript, stimulus, _| {
            let action0 = run.next_action(loans).unwrap().unwrap();
            let (_opening, lifetime) = action0
                .prepare_connected_controller(producer, transcript, stimulus, loans)
                .unwrap();
            let foreign =
                PreparedBrowserClientRun::prepare(run.core, run.global, run.child, loans.inner)
                    .unwrap();
            foreign
                .next_action(loans)
                .unwrap()
                .unwrap()
                .consume_source_only_for_test(&foreign, loans)
                .unwrap();
            let action1 = foreign.next_action(loans).unwrap().unwrap();
            let before = {
                let (d, r, c) = loans.inner.physical_owners().unwrap();
                (d.usage(), r.usage(), c.usage())
            };
            let (returned, cause) =
                match BrowserOwnedInspectionBoundary::prepare(action1, &lifetime, loans) {
                    Err(refused) => refused,
                    Ok(_) => panic!("same child cannot substitute another compiled run"),
                };
            assert_eq!(returned.position(), 1);
            assert!(matches!(
                cause,
                BrowserActionIssueError::Cursor(BrowserActionCursorFault::ForeignAction)
            ));
            let after = {
                let (d, r, c) = loans.inner.physical_owners().unwrap();
                (d.usage(), r.usage(), c.usage())
            };
            assert_eq!(before, after);
        },
    );
}

#[derive(Clone, Copy)]
enum ReceiptControl {
    Foreign,
    Refused,
    Faulted,
    Healthy,
}

#[test]
fn browser_inspection_action_03_only_same_healthy_sealed_receipt_consumes_source1() {
    for scenario in [
        ReceiptControl::Foreign,
        ReceiptControl::Refused,
        ReceiptControl::Faulted,
        ReceiptControl::Healthy,
    ] {
        with_opening_setup(
            Duration::from_secs(10),
            |run, loans, producer, transcript, stimulus, _| {
                let action0 = run.next_action(loans).unwrap().unwrap();
                let (mut opening, lifetime) = action0
                    .prepare_connected_controller(producer, transcript, stimulus, loans)
                    .unwrap();
                let measured = lock(&run.actions)
                    .operations
                    .requested(SourceOperationKind::Opening)
                    .unwrap()
                    .opening(BrowserOpeningSelectionReply::ProjectSelected)
                    .ok()
                    .unwrap();
                opening
                    .settle_controller_reply(&measured, &lifetime, loans)
                    .unwrap();
                drop(opening);
                let action1 = run.next_action(loans).unwrap().unwrap();
                let mut owned = BrowserOwnedInspectionBoundary::prepare(action1, &lifetime, loans)
                    .unwrap_or_else(|_| panic!("source1"));
                let foreign = SourceOperationJournal::prepare(loans.inner).unwrap();
                let mut pending = if matches!(scenario, ReceiptControl::Foreign) {
                    foreign
                        .requested(SourceOperationKind::InspectionBoundary)
                        .unwrap()
                } else {
                    lock(&run.actions)
                        .operations
                        .requested(SourceOperationKind::InspectionBoundary)
                        .unwrap()
                };
                if matches!(scenario, ReceiptControl::Faulted) {
                    pending.fault(BrowserConnectedControlFault::Cancelled);
                }
                let reply = if matches!(scenario, ReceiptControl::Refused) {
                    BrowserInspectionPendingReply::OriginalsOnly
                } else {
                    BrowserInspectionPendingReply::InspectionPending
                };
                let receipt = pending.inspection(reply).ok().unwrap();
                let result = owned.settle_controller_reply(&receipt, &lifetime, loans);
                if matches!(scenario, ReceiptControl::Healthy) {
                    result.unwrap();
                    assert!(matches!(
                        run.actions_terminal(),
                        BrowserActionCursorTerminal::Incomplete {
                            consumed: 2,
                            pending: None,
                            ..
                        }
                    ));
                    let checkpoint = run.next_action(loans).unwrap().unwrap();
                    assert_eq!(
                        checkpoint.position(),
                        2,
                        "checkpoint2 is still required before core"
                    );
                    let (_, cause) =
                        match BrowserOwnedInspectionBoundary::prepare(checkpoint, &lifetime, loans)
                        {
                            Err(refused) => refused,
                            Ok(_) => panic!("checkpoint is not source1"),
                        };
                    assert!(matches!(
                        cause,
                        BrowserActionIssueError::Cursor(
                            BrowserActionCursorFault::UnsupportedOperation
                        )
                    ));
                } else {
                    let cause = result
                        .err()
                        .expect("unhealthy/foreign DATA cannot settle source1");
                    if matches!(scenario, ReceiptControl::Foreign) {
                        assert!(matches!(
                            cause,
                            BrowserActionIssueError::Cursor(
                                BrowserActionCursorFault::ForeignAction
                            )
                        ));
                    }
                    owned.refuse_controller(cause);
                    owned.inspect_controller_cause(|_| ());
                    assert!(matches!(
                        run.actions_terminal(),
                        BrowserActionCursorTerminal::Refused {
                            position: 1,
                            cause: BrowserActionCursorFault::OperationRefused
                        }
                    ));
                }
            },
        );
    }
}

#[test]
fn browser_inspection_action_04_prior_owner_fault_is_retained_on_preparation() {
    with_opening_setup(
        Duration::from_secs(10),
        |run, loans, producer, transcript, stimulus, _| {
            let action0 = run.next_action(loans).unwrap().unwrap();
            let (mut opening, lifetime) = action0
                .prepare_connected_controller(producer, transcript, stimulus, loans)
                .unwrap();
            let measured = lock(&run.actions)
                .operations
                .requested(SourceOperationKind::Opening)
                .unwrap()
                .opening(BrowserOpeningSelectionReply::ProjectSelected)
                .ok()
                .unwrap();
            opening
                .settle_controller_reply(&measured, &lifetime, loans)
                .unwrap();
            drop(opening);
            let action1 = run.next_action(loans).unwrap().unwrap();
            let original = loans
                .reserve_controlled_host_storage(usize::MAX, 0, 0)
                .err()
                .expect("genuine cumulative owner refusal");
            let refused = match BrowserOwnedInspectionBoundary::prepare(action1, &lifetime, loans) {
                Err((returned, BrowserActionIssueError::Input(cause))) => {
                    assert_eq!(returned.position(), 1);
                    cause
                }
                _ => panic!("prior owner refusal must dominate source1 preparation"),
            };
            // physical_owners itself requires ready owners. Compare the actual
            // retained typed cause instead of bypassing that protected API.
            assert_eq!(format!("{original:?}"), format!("{refused:?}"));
        },
    );
}

#[test]
fn browser_inspection_action_05_prepared_holder_cannot_settle_after_original_end() {
    with_opening_setup(
        Duration::from_millis(250),
        |run, loans, producer, transcript, stimulus, end| {
            let action0 = run.next_action(loans).unwrap().unwrap();
            let (mut opening, lifetime) = action0
                .prepare_connected_controller(producer, transcript, stimulus, loans)
                .unwrap();
            let measured = lock(&run.actions)
                .operations
                .requested(SourceOperationKind::Opening)
                .unwrap()
                .opening(BrowserOpeningSelectionReply::ProjectSelected)
                .ok()
                .unwrap();
            opening
                .settle_controller_reply(&measured, &lifetime, loans)
                .unwrap();
            drop(opening);
            let action1 = run.next_action(loans).unwrap().unwrap();
            let mut owned = BrowserOwnedInspectionBoundary::prepare(action1, &lifetime, loans)
                .unwrap_or_else(|_| panic!("source1"));
            let receipt = lock(&run.actions)
                .operations
                .requested(SourceOperationKind::InspectionBoundary)
                .unwrap()
                .inspection(BrowserInspectionPendingReply::InspectionPending)
                .ok()
                .unwrap();
            std::thread::sleep(
                end.saturating_duration_since(Instant::now()) + Duration::from_millis(1),
            );
            assert!(matches!(owned.settle_controller_reply(&receipt, &lifetime, loans), Err(BrowserActionIssueError::Host(crate::workbench::model_originals::workflow::pipeline::browser::BrowserHostTranscriptFault::End))));
            let mut called = false;
            assert!(
                owned
                    .source(&lifetime, loans)
                    .and_then(|source| source.with_prepared_controller_step(loans, |_| {
                        called = true;
                    }))
                    .is_err()
            );
            assert!(!called);
            assert!(matches!(
                run.actions_terminal(),
                BrowserActionCursorTerminal::Incomplete {
                    consumed: 1,
                    pending: Some(1),
                    ..
                }
            ));
        },
    );
}
#[cfg(target_os = "macos")]
#[test]
fn browser_inspection_action_06_prepaid_source1_after_residual_uses_no_fresh_budget() {
    use super::super::super::tests::{controlled_clients, with_compiled_artifact_control};
    use crate::workbench::model_originals::workflow::pipeline::browser::{
        BrowserDocumentBounds, BrowserRowCollection,
        controller::source_business::{SourceBusinessEnvelope, SourceBusinessOperation},
    };
    with_compiled_artifact_control(|compiled, inner| {
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
        let end = Instant::now() + Duration::from_secs(10);
        let transcript = producer
            .prepare_host_transcript(&mut loans, &stimulus, end)
            .unwrap();
        let action0 = run.next_action(&mut loans).unwrap().unwrap();
        let (mut owned0, lifetime) = action0
            .prepare_connected_controller(&producer, &transcript, &stimulus, &mut loans)
            .unwrap();
        let mut envelope = SourceBusinessEnvelope::prepare(&lifetime, &mut loans).unwrap();
        // Literal sealed DATA controls logical progression only, not a real
        // controller reply or business execution.
        let measured0 = lock(&run.actions)
            .operations
            .requested(SourceOperationKind::Opening)
            .unwrap()
            .opening(BrowserOpeningSelectionReply::ProjectSelected)
            .ok()
            .unwrap();
        owned0
            .settle_controller_reply(&measured0, &lifetime, &mut loans)
            .unwrap();
        drop(owned0);
        let action1 = run.next_action(&mut loans).unwrap().unwrap();
        let remainder = loans.remaining_cleanup_resources(&lifetime).unwrap();
        loans
            .reserve_controlled_host_storage(remainder.retained_bytes, 0, 0)
            .unwrap();
        let before = loans.business_usage().unwrap();
        let mut owned = BrowserOwnedInspectionBoundary::prepare_prepaid(
            action1,
            &lifetime,
            envelope
                .take(SourceBusinessOperation::InspectionPreparation)
                .unwrap(),
            &loans,
        )
        .unwrap_or_else(|_| panic!("prepaid source1"));
        let source = owned
            .source_prepaid(
                &lifetime,
                envelope
                    .take(SourceBusinessOperation::InspectionSource)
                    .unwrap(),
                &loans,
            )
            .unwrap();
        drop(source);
        let measured1 = lock(&run.actions)
            .operations
            .requested(SourceOperationKind::InspectionBoundary)
            .unwrap()
            .inspection(BrowserInspectionPendingReply::InspectionPending)
            .ok()
            .unwrap();
        owned
            .settle_controller_reply_prepaid(
                &measured1,
                &lifetime,
                envelope
                    .take(SourceBusinessOperation::InspectionSettlement)
                    .unwrap(),
                &loans,
            )
            .unwrap();
        let after = loans.business_usage().unwrap();
        assert_eq!(before, after);
        assert!(matches!(
            run.actions_terminal(),
            BrowserActionCursorTerminal::Incomplete {
                consumed: 2,
                pending: None,
                ..
            }
        ));
    });
}
