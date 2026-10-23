//! Actual current source/owner preparation. No listener, Page, future action
//! grant or source2 qualification is exercised by this native funding pool.
use super::operation_tests::with_opening_setup;
use super::*;
use crate::workbench::model_originals::workflow::pipeline::browser::controller::{
    SourceResultError, SourceResultPreparation, SourceResultRefusal, SourceResultResource,
    SourceResultResources, SourceResultUnsupported,
};
use std::time::Duration;

#[test]
fn browser_result_escrow_01_cleanup_minimum_precedes_one_same_owner_pool() {
    with_opening_setup(
        Duration::from_secs(10),
        |run, loans, producer, transcript, stimulus, _| {
            let plan = run.prepare_result_plan(loans).unwrap();
            assert_eq!(plan.invocations().len(), 1);
            assert_eq!(
                plan.settlements().len(),
                0,
                "actual current source has no Settle production slot"
            );
            let descriptor_backing = plan.invocations().as_slice().as_ptr();
            let view_usage = loans.business_usage().unwrap();
            for _ in 0..16 {
                assert_eq!(
                    plan.invocations().as_slice().as_ptr(),
                    descriptor_backing,
                    "repeat view borrows the paid snapshot, not a new source scan"
                );
            }
            assert_eq!(view_usage, loans.business_usage().unwrap());
            let invocation = plan.invocations().next().unwrap();
            assert_eq!(invocation.action_position(), 3);
            assert_eq!(
                invocation.production(),
                super::result_plan::SourceResultOperation::Execute
            );
            assert_eq!(invocation.effect().kind, input::EffectKind::Inspection);
            assert_eq!(invocation.effect().ordinal.get(), 0);
            let issued = run.next_action(loans).unwrap().unwrap();
            let (owned, lifetime) = issued
                .prepare_connected_controller(producer, transcript, stimulus, loans)
                .unwrap();
            let prepared =
                SourceResultPreparation::prepare_selected_runtime(plan, &lifetime, loans)
                    .ok()
                    .expect("actual source-derived minimum and shared pool");
            assert_eq!(prepared.cleanup_capacity(), 533);
            let usage = loans.business_usage().unwrap();
            let remaining = loans.remaining_cleanup_resources(&lifetime).unwrap();
            assert_eq!(
                (
                    remaining.retained_bytes,
                    remaining.receiving_visits,
                    remaining.decode_visits,
                    remaining.decode_slots
                ),
                (0, 0, 0, 0)
            );
            assert!(matches!(
                run.actions_terminal(),
                BrowserActionCursorTerminal::Incomplete {
                    consumed: 0,
                    pending: Some(0),
                    ..
                }
            ));
            drop(prepared);
            assert_eq!(
                loans.business_usage().unwrap(),
                usage,
                "dropping unused pool never refunds caller counters"
            );
            assert!(lifetime.finish_without_acquisition().is_ok());
            drop(owned);
        },
    );
}

#[test]
fn browser_result_escrow_02_overlapping_native_subcredits_share_one_pool_not_two_source_invocations()
 {
    with_opening_setup(
        Duration::from_secs(10),
        |run, loans, producer, transcript, stimulus, _| {
            let plan = run.prepare_result_plan(loans).unwrap();
            assert_eq!(
                plan.invocations().len(),
                1,
                "this actual source supplies K1, not a K2 execution proof"
            );
            let action = run.next_action(loans).unwrap().unwrap();
            let (_owned, lifetime) = action
                .prepare_connected_controller(producer, transcript, stimulus, loans)
                .unwrap();
            let mut prepared =
                SourceResultPreparation::prepare_selected_runtime(plan, &lifetime, loans)
                    .ok()
                    .unwrap();
            let caller = loans.business_usage().unwrap();
            let a = prepared
                .claim_native(
                    SourceResultResources {
                        retained_bytes: 97,
                        receiving_visits: 16384,
                        decode_visits: 16384,
                        decode_slots: 2,
                    },
                    &lifetime,
                    loans,
                )
                .unwrap();
            let exact = prepared
                .snapshot()
                .available
                .checked_sub(SourceResultPreparation::native_issue_cost().unwrap())
                .unwrap();
            let b = prepared.claim_native(exact, &lifetime, loans).unwrap();
            assert_eq!(
                prepared.snapshot().available,
                SourceResultResources::default()
            );
            let outstanding = prepared.snapshot().outstanding;
            drop(a);
            assert_ne!(prepared.snapshot().outstanding, outstanding);
            drop(b);
            let final_state = prepared.snapshot();
            assert_eq!(final_state.outstanding, SourceResultResources::default());
            assert_ne!(
                final_state.spent,
                SourceResultResources::default(),
                "issued native headers/Weak and Arc operations remain spent"
            );
            assert_eq!(
                final_state
                    .available
                    .checked_add(final_state.spent)
                    .and_then(|n| n.checked_add(final_state.control_reserved))
                    .unwrap(),
                final_state.total
            );
            assert_eq!(caller, loans.business_usage().unwrap());
            drop(prepared);
            assert!(lifetime.finish_without_acquisition().is_ok());
        },
    );
}

#[test]
fn browser_result_escrow_03_native_spent_work_and_actual_backing_never_refund() {
    with_opening_setup(
        Duration::from_secs(10),
        |run, loans, producer, transcript, stimulus, _| {
            let plan = run.prepare_result_plan(loans).unwrap();
            let action = run.next_action(loans).unwrap().unwrap();
            let (_owned, lifetime) = action
                .prepare_connected_controller(producer, transcript, stimulus, loans)
                .unwrap();
            let mut prepared =
                SourceResultPreparation::prepare_selected_runtime(plan, &lifetime, loans)
                    .ok()
                    .unwrap();
            let caller = loans.business_usage().unwrap();
            let mut credit = prepared
                .claim_native(
                    SourceResultResources {
                        retained_bytes: 4096,
                        receiving_visits: 1_000_000,
                        decode_visits: 1_000_000,
                        decode_slots: 16,
                    },
                    &lifetime,
                    loans,
                )
                .unwrap();
            credit.spend_native_work(65, 67, &lifetime, loans).unwrap();
            let backing = credit.allocate_native(97, &lifetime, loans).unwrap();
            assert_eq!(backing.bytes(), &[0; 97]);
            assert_eq!(prepared.snapshot().live_bytes, backing.capacity());
            let spent = prepared.snapshot().spent;
            drop(credit);
            assert_eq!(prepared.snapshot().spent, spent);
            assert_ne!(
                prepared.snapshot().live_bytes,
                0,
                "actual backing outlives returned unused subcredit"
            );
            drop(backing);
            assert_eq!(prepared.snapshot().live_bytes, 0);
            assert_eq!(
                prepared.snapshot().spent,
                spent,
                "retirement is not a cumulative permission refund"
            );
            assert_eq!(
                prepared
                    .snapshot()
                    .available
                    .checked_add(spent)
                    .and_then(|n| n.checked_add(prepared.snapshot().control_reserved))
                    .unwrap(),
                prepared.snapshot().total
            );
            assert_eq!(caller, loans.business_usage().unwrap());
            drop(prepared);
            assert!(lifetime.finish_without_acquisition().is_ok());
        },
    );
}

#[test]
fn browser_result_escrow_04_local_insufficiency_never_overdraws_or_faults_shared_owners() {
    with_opening_setup(
        Duration::from_secs(10),
        |run, loans, producer, transcript, stimulus, _| {
            let plan = run.prepare_result_plan(loans).unwrap();
            let action = run.next_action(loans).unwrap().unwrap();
            let (_owned, lifetime) = action
                .prepare_connected_controller(producer, transcript, stimulus, loans)
                .unwrap();
            let mut prepared =
                SourceResultPreparation::prepare_selected_runtime(plan, &lifetime, loans)
                    .ok()
                    .unwrap();
            let before = prepared.snapshot();
            let caller = loans.business_usage().unwrap();
            let requested = SourceResultResources {
                retained_bytes: before.available.retained_bytes,
                ..SourceResultResources::default()
            };
            let first = match prepared.claim_native(requested, &lifetime, loans) {
                Err(SourceResultError::Refused(first)) => first,
                _ => panic!("actual metadata plus requested bytes cannot fit"),
            };
            assert!(matches!(
                first,
                SourceResultRefusal::Insufficient {
                    resource: SourceResultResource::RetainedBytes,
                    ..
                }
            ));
            let after = prepared.snapshot();
            assert_eq!(
                after.outstanding, before.outstanding,
                "impossible payload is not reserved"
            );
            assert!(
                after.spent.receiving_visits > before.spent.receiving_visits,
                "the real failed control traversal consumes prepaid permission"
            );
            assert!(
                matches!(prepared.claim_native(SourceResultResources::default(),&lifetime,loans),Err(SourceResultError::Refused(next)) if next==first)
            );
            assert_eq!(
                prepared.snapshot(),
                after,
                "cached terminal fault repeats no source traversal or debit"
            );
            loans.business_test_ready().unwrap();
            // Readonly currentness remains healthy. This does not claim that an old
            // fresh-debit SDK path has acquired a new prepaid decoding adapter.
            lifetime.validate(loans).unwrap();
            assert_eq!(caller, loans.business_usage().unwrap());
            drop(prepared);
            assert!(lifetime.finish_without_acquisition().is_ok());
        },
    );
}

#[test]
fn browser_result_escrow_05_original_end_refuses_new_claim_and_backing_but_returns_unused_native_credit()
 {
    with_opening_setup(
        Duration::from_millis(100),
        |run, loans, producer, transcript, stimulus, end| {
            let plan = run.prepare_result_plan(loans).unwrap();
            let action = run.next_action(loans).unwrap().unwrap();
            let (_owned, lifetime) = action
                .prepare_connected_controller(producer, transcript, stimulus, loans)
                .unwrap();
            let mut prepared =
                SourceResultPreparation::prepare_selected_runtime(plan, &lifetime, loans)
                    .ok()
                    .unwrap();
            let mut credit = prepared
                .claim_native(
                    SourceResultResources {
                        retained_bytes: 4096,
                        receiving_visits: 1_000_000,
                        decode_visits: 1_000_000,
                        decode_slots: 8,
                    },
                    &lifetime,
                    loans,
                )
                .unwrap();
            let before = prepared.snapshot();
            let caller = loans.business_usage().unwrap();
            std::thread::sleep(
                end.saturating_duration_since(std::time::Instant::now()) + Duration::from_millis(1),
            );
            use crate::workbench::model_originals::workflow::pipeline::browser::adapter::BrowserActivityFault;
            assert!(matches!(
                prepared.claim_native(SourceResultResources::default(), &lifetime, loans),
                Err(SourceResultError::Refused(SourceResultRefusal::Activity(
                    BrowserActivityFault::OriginalEnd
                )))
            ));
            assert!(matches!(
                credit.allocate_native(97, &lifetime, loans),
                Err(SourceResultError::Refused(SourceResultRefusal::Activity(
                    BrowserActivityFault::OriginalEnd
                )))
            ));
            assert_eq!(
                prepared.snapshot().outstanding,
                before.outstanding,
                "expired operation does not consume payload"
            );
            assert!(
                prepared.snapshot().spent.receiving_visits > before.spent.receiving_visits,
                "one prepaid terminal allowance is consumed"
            );
            drop(credit);
            assert_eq!(
                prepared.snapshot().outstanding,
                SourceResultResources::default()
            );
            assert_eq!(caller, loans.business_usage().unwrap());
            drop(prepared);
            assert!(lifetime.finish_without_acquisition().is_ok());
        },
    );
}

#[test]
fn browser_result_escrow_06_same_child_foreign_run_refuses_before_any_debit() {
    with_opening_setup(
        Duration::from_secs(10),
        |run, loans, producer, transcript, stimulus, _| {
            let plan = run.prepare_result_plan(loans).unwrap();
            let action = run.next_action(loans).unwrap().unwrap();
            let (_owned, lifetime) = action
                .prepare_connected_controller(producer, transcript, stimulus, loans)
                .unwrap();
            let foreign =
                PreparedBrowserClientRun::prepare(run.core, run.global, run.child, loans.inner)
                    .unwrap();
            let foreign_plan = foreign.prepare_result_plan(loans).unwrap();
            let before = loans.business_usage().unwrap();
            let failure =
                SourceResultPreparation::prepare_selected_runtime(foreign_plan, &lifetime, loans)
                    .err()
                    .unwrap();
            assert_eq!(
                failure.input_fault().unwrap().source_cause(),
                Some(BrowserSourceFault::ForeignSource)
            );
            assert_eq!(before, loans.business_usage().unwrap());
            drop(failure);
            let foreign_child = ExecutionChild::prepare(run.global, loans.inner).unwrap();
            let mut prepared =
                SourceResultPreparation::prepare_selected_runtime(plan, &lifetime, loans)
                    .ok()
                    .unwrap();
            let before = prepared.snapshot();
            let caller = loans.business_usage().unwrap();
            {
                let foreign_loans =
                    BrowserLoans::execution(loans.inner, run.global, &foreign_child).unwrap();
                assert!(
                    matches!(prepared.claim_native(SourceResultResources::default(),&lifetime,&foreign_loans),Err(SourceResultError::Input(error)) if error.source_cause()==Some(BrowserSourceFault::ForeignSource))
                );
            }
            assert_eq!(before.outstanding, prepared.snapshot().outstanding);
            assert!(
                prepared.snapshot().spent.receiving_visits > before.spent.receiving_visits,
                "foreign relation traversal consumes local control permission only"
            );
            assert_eq!(caller, loans.business_usage().unwrap());
            drop(prepared);
            assert!(lifetime.finish_without_acquisition().is_ok());
        },
    );
}

#[test]
fn browser_result_escrow_10_native_allocation_overflow_preserves_local_first_refusal() {
    with_opening_setup(
        Duration::from_secs(10),
        |run, loans, producer, transcript, stimulus, _| {
            let plan = run.prepare_result_plan(loans).unwrap();
            let action = run.next_action(loans).unwrap().unwrap();
            let (_owned, lifetime) = action
                .prepare_connected_controller(producer, transcript, stimulus, loans)
                .unwrap();
            let mut prepared =
                SourceResultPreparation::prepare_selected_runtime(plan, &lifetime, loans)
                    .ok()
                    .unwrap();
            let mut credit = prepared
                .claim_native(
                    SourceResultResources {
                        retained_bytes: 4096,
                        receiving_visits: 1_000_000,
                        decode_visits: 1_000_000,
                        decode_slots: 16,
                    },
                    &lifetime,
                    loans,
                )
                .unwrap();
            let caller = loans.business_usage().unwrap();
            let before = prepared.snapshot();
            assert!(matches!(
                credit.allocate_native(usize::MAX, &lifetime, loans),
                Err(SourceResultError::Refused(SourceResultRefusal::Overflow))
            ));
            assert_eq!(
                prepared.snapshot().first,
                Some(SourceResultRefusal::Overflow)
            );
            assert!(matches!(
                credit.spend_native_work(1, 1, &lifetime, loans),
                Err(SourceResultError::Refused(SourceResultRefusal::Overflow))
            ));
            assert_eq!(before.available, prepared.snapshot().available);
            assert!(
                prepared.snapshot().spent.receiving_visits > before.spent.receiving_visits,
                "failed operation keeps its control permission spent"
            );
            assert_eq!(caller, loans.business_usage().unwrap());
            drop(credit);
            drop(prepared);
            assert!(lifetime.finish_without_acquisition().is_ok());
        },
    );
}

#[test]
fn browser_result_escrow_07_cleanup_minimum_refusal_is_actual_first_owner_fault() {
    with_opening_setup(
        Duration::from_secs(10),
        |run, loans, producer, transcript, stimulus, _| {
            let plan = run.prepare_result_plan(loans).unwrap();
            let action = run.next_action(loans).unwrap().unwrap();
            let (_owned, lifetime) = action
                .prepare_connected_controller(producer, transcript, stimulus, loans)
                .unwrap();
            let remaining = loans.remaining_cleanup_resources(&lifetime).unwrap();
            loans
                .reserve_controlled_host_storage(remaining.retained_bytes, 0, 0)
                .unwrap();
            let failure = SourceResultPreparation::prepare_selected_runtime(plan, &lifetime, loans)
                .err()
                .unwrap();
            use crate::workbench::model_originals::workflow::pipeline::installed::observation::{
                InstalledObservationFault, InstalledObservationResource,
            };
            assert!(matches!(
                failure.input_fault().unwrap().test_cause(),
                inputs::BrowserInputFault::Receiving(InstalledObservationFault::Resource {
                    kind: InstalledObservationResource::RetainedBytes,
                    ..
                })
            ));
            assert!(
                !failure.has_cleanup(),
                "no cleanup backing or pool adopted on minimum refusal"
            );
            assert!(matches!(
                loans.business_test_ready().unwrap_err().test_cause(),
                inputs::BrowserInputFault::Receiving(InstalledObservationFault::Resource {
                    kind: InstalledObservationResource::RetainedBytes,
                    ..
                })
            ));
            drop(failure);
            assert!(lifetime.finish_without_acquisition().is_ok());
        },
    );
}

#[test]
fn browser_result_escrow_08_separate_resources_are_explicitly_unsupported() {
    with_opening_setup(
        Duration::from_secs(10),
        |run, loans, producer, transcript, stimulus, _| {
            let plan = run.prepare_result_plan(loans).unwrap();
            let action = run.next_action(loans).unwrap().unwrap();
            let (_owned, lifetime) = action
                .prepare_connected_controller(producer, transcript, stimulus, loans)
                .unwrap();
            let mut prepared =
                SourceResultPreparation::prepare_selected_runtime(plan, &lifetime, loans)
                    .ok()
                    .unwrap();
            let before = prepared.snapshot();
            let caller = loans.business_usage().unwrap();
            assert!(matches!(
                prepared.refuse_unsupported(
                    SourceResultUnsupported::LiteralReadWork,
                    &lifetime,
                    loans
                ),
                Err(SourceResultError::Refused(
                    SourceResultRefusal::Unsupported(SourceResultUnsupported::LiteralReadWork)
                ))
            ));
            assert_eq!(before.outstanding, prepared.snapshot().outstanding);
            assert!(prepared.snapshot().spent.receiving_visits > before.spent.receiving_visits);
            assert_eq!(caller, loans.business_usage().unwrap());
            assert!(loans.business_test_ready().is_ok());
            drop(prepared);
            assert!(lifetime.finish_without_acquisition().is_ok());
        },
    );
}

#[test]
fn browser_result_escrow_09_native_allocation_error_and_excess_preserve_spent_and_first_fault() {
    for fail in [false, true] {
        with_opening_setup(
            Duration::from_secs(10),
            |run, loans, producer, transcript, stimulus, _| {
                let plan = run.prepare_result_plan(loans).unwrap();
                let action = run.next_action(loans).unwrap().unwrap();
                let (_owned, lifetime) = action
                    .prepare_connected_controller(producer, transcript, stimulus, loans)
                    .unwrap();
                let mut prepared =
                    SourceResultPreparation::prepare_selected_runtime(plan, &lifetime, loans)
                        .ok()
                        .unwrap();
                let mut credit = prepared
                    .claim_native(
                        SourceResultResources {
                            retained_bytes: 4096,
                            receiving_visits: 1_000_000,
                            decode_visits: 1_000_000,
                            decode_slots: 16,
                        },
                        &lifetime,
                        loans,
                    )
                    .unwrap();
                let before = prepared.snapshot();
                if fail {
                    assert!(matches!(
                        credit.test_allocate_failure(97, &lifetime, loans),
                        Err(SourceResultError::Refused(SourceResultRefusal::Allocation))
                    ));
                    assert!(
                        prepared.has_allocation_error(),
                        "retain the actual TryReserveError, not a fabricated IO cause"
                    );
                    assert_eq!(prepared.snapshot().live_bytes, 0);
                    assert!(matches!(
                        credit.allocate_native(97, &lifetime, loans),
                        Err(SourceResultError::Refused(SourceResultRefusal::Allocation))
                    ));
                } else {
                    let backing = credit
                        .test_allocate_excess(97, 31, &lifetime, loans)
                        .unwrap();
                    assert!(backing.capacity() >= 128);
                    assert_eq!(prepared.snapshot().live_bytes, backing.capacity());
                    assert!(
                        prepared.snapshot().spent.retained_bytes
                            >= before.spent.retained_bytes + backing.capacity()
                    );
                    drop(backing);
                }
                assert_ne!(prepared.snapshot().spent, before.spent);
                let spent = prepared.snapshot().spent;
                drop(credit);
                assert_eq!(prepared.snapshot().spent, spent);
                assert_eq!(prepared.snapshot().live_bytes, 0);
                assert_eq!(
                    prepared
                        .snapshot()
                        .available
                        .checked_add(spent)
                        .and_then(|n| n.checked_add(prepared.snapshot().control_reserved))
                        .unwrap(),
                    prepared.snapshot().total
                );
                assert!(loans.business_test_ready().is_ok());
                drop(prepared);
                assert!(lifetime.finish_without_acquisition().is_ok());
            },
        );
    }
}

#[test]
fn browser_result_escrow_11_too_small_control_uses_one_terminal_allowance_and_never_rechecks_source()
 {
    with_opening_setup(
        Duration::from_secs(10),
        |run, loans, producer, transcript, stimulus, _| {
            let opening = run.openings(loans).unwrap().next().unwrap();
            let abandoned = run.prepare_controlled_host(&opening, loans).unwrap();
            let plan = run.prepare_result_plan(loans).unwrap();
            let action = run.next_action(loans).unwrap().unwrap();
            let (_owned, lifetime) = action
                .prepare_connected_controller(producer, transcript, stimulus, loans)
                .unwrap();
            let mut prepared =
                SourceResultPreparation::prepare_selected_runtime(plan, &lifetime, loans)
                    .ok()
                    .unwrap();
            let available = prepared.snapshot().available;
            let overhead = SourceResultPreparation::native_issue_cost().unwrap();
            let held = prepared
                .claim_native(
                    SourceResultResources {
                        receiving_visits: available.receiving_visits - overhead.receiving_visits,
                        decode_visits: available.decode_visits - overhead.decode_visits,
                        ..SourceResultResources::default()
                    },
                    &lifetime,
                    loans,
                )
                .unwrap();
            let before = prepared.snapshot();
            let caller = loans.business_usage().unwrap();
            let first =
                match prepared.claim_native(SourceResultResources::default(), &lifetime, loans) {
                    Err(SourceResultError::Refused(first)) => first,
                    _ => panic!("no control work remains"),
                };
            let after = prepared.snapshot();
            assert!(
                after.spent.receiving_visits > before.spent.receiving_visits,
                "prepaid terminal path is consumed before closing"
            );
            assert_eq!(
                after.outstanding, before.outstanding,
                "held payload subcredit remains owned"
            );
            drop(abandoned);
            assert_eq!(
                lifetime.validate(loans).unwrap_err().source_cause(),
                Some(BrowserSourceFault::Abandoned)
            );
            assert!(
                matches!(prepared.claim_native(SourceResultResources::default(),&lifetime,loans),Err(SourceResultError::Refused(next)) if next==first),
                "closed path performs no source traversal after later actual source fault"
            );
            assert_eq!(prepared.snapshot(), after);
            assert_eq!(loans.business_usage().unwrap(), caller);
            drop(held);
            drop(prepared);
            assert!(lifetime.finish_without_acquisition().is_ok());
        },
    );
}

#[test]
fn browser_result_escrow_12_genuine_contended_pool_crosses_original_end_before_three_boundaries() {
    use crate::workbench::model_originals::workflow::pipeline::browser::adapter::BrowserActivityFault;
    use crate::workbench::model_originals::workflow::pipeline::browser::controller::TestNativeEndBoundary;
    for boundary in [
        TestNativeEndBoundary::Payload,
        TestNativeEndBoundary::Allocation,
        TestNativeEndBoundary::Initialization,
    ] {
        with_opening_setup(
            Duration::from_millis(500),
            |run, loans, producer, transcript, stimulus, end| {
                let plan = run.prepare_result_plan(loans).unwrap();
                let action = run.next_action(loans).unwrap().unwrap();
                let (_owned, lifetime) = action
                    .prepare_connected_controller(producer, transcript, stimulus, loans)
                    .unwrap();
                let mut prepared =
                    SourceResultPreparation::prepare_selected_runtime(plan, &lifetime, loans)
                        .ok()
                        .unwrap();
                let mut credit = prepared
                    .claim_native(
                        SourceResultResources {
                            retained_bytes: 4096,
                            receiving_visits: 1_000_000,
                            decode_visits: 1_000_000,
                            decode_slots: 16,
                        },
                        &lifetime,
                        loans,
                    )
                    .unwrap();
                let paid = credit
                    .test_prepare_end_boundary(boundary, &lifetime, loans)
                    .unwrap();
                let before = prepared.snapshot();
                let caller = loans.business_usage().unwrap();
                let locked = prepared.test_lock_pool();
                let (entered_tx, entered_rx) = std::sync::mpsc::sync_channel(0);
                let (entered, result) = std::thread::scope(|scope| {
                    let task = scope
                        .spawn(|| credit.test_complete_end_boundary(paid, &lifetime, entered_tx));
                    // Signal is sent INSIDE the actual source gate before trying
                    // the actual locked pool. This establishes the tested ordering.
                    let entered = entered_rx
                        .recv_timeout(end.saturating_duration_since(std::time::Instant::now()));
                    if entered.is_ok() {
                        std::thread::sleep(
                            end.saturating_duration_since(std::time::Instant::now())
                                + Duration::from_millis(1),
                        );
                    }
                    drop(locked);
                    (entered, task.join().unwrap())
                });
                let after = prepared.snapshot();
                drop(credit);
                drop(prepared);
                assert!(lifetime.finish_without_acquisition().is_ok());
                assert!(
                    entered.is_ok(),
                    "must actually enter the original gate before expiry, {boundary:?}"
                );
                assert!(
                    matches!(
                        result,
                        Err(SourceResultError::Refused(SourceResultRefusal::Activity(
                            BrowserActivityFault::OriginalEnd
                        )))
                    ),
                    "{boundary:?}: {result:?}"
                );
                assert_eq!(
                    (
                        before.available,
                        before.outstanding,
                        before.spent,
                        before.live_bytes
                    ),
                    (
                        after.available,
                        after.outstanding,
                        after.spent,
                        after.live_bytes
                    ),
                    "no post-lock payload commit/allocation/init, {boundary:?}"
                );
                assert_eq!(caller, loans.business_usage().unwrap());
            },
        );
    }
}

#[test]
fn browser_result_escrow_13_preissued_document_uses_same_literal_work_after_sweep() {
    with_opening_setup(
        Duration::from_secs(10),
        |run, loans, producer, transcript, stimulus, end| {
            let plan = run.prepare_result_plan(loans).unwrap();
            let action = run.next_action(loans).unwrap().unwrap();
            let (owned, lifetime) = action
                .prepare_connected_controller(producer, transcript, stimulus, loans)
                .unwrap();
            let sdk = owned
                .connected_opening(producer, transcript, stimulus, loans)
                .unwrap();
            assert_eq!(
                sdk.validate_host(producer, transcript, stimulus, loans)
                    .unwrap(),
                end
            );
            // The actual fixture already issued this producer's decoder and
            // requested journal/frame backing. No new parser or owner is made.
            let prepared =
                SourceResultPreparation::prepare_selected_runtime(plan, &lifetime, loans)
                    .ok()
                    .unwrap();
            let remaining = loans.remaining_cleanup_resources(&lifetime).unwrap();
            assert_eq!(
                (
                    remaining.retained_bytes,
                    remaining.receiving_visits,
                    remaining.decode_visits,
                    remaining.decode_slots
                ),
                (0, 0, 0, 0)
            );
            let before = loans.business_usage().unwrap();
            producer.validate_host(loans, stimulus).unwrap();
            lifetime.while_business_active(|| ()).unwrap();
            assert_eq!(before, loans.business_usage().unwrap());

            // Existing literal decoder controls, not actual product facts or
            // observations of the authored workflow, native host or Page.
            let mut fact = vec![1, 1, 0, 0];
            fact.extend_from_slice(&1u64.to_be_bytes());
            let payload = br#"{"sequence":1,"kind":"model-closed","actual":{"workspace":"unit","opening":0}}"#;
            fact.extend_from_slice(&(payload.len() as u32).to_be_bytes());
            fact.extend_from_slice(payload);
            let retained_fact = producer.record_frame(loans, &fact, end).unwrap();
            let mut closed = vec![1, 2, 0, 0];
            closed.extend_from_slice(&2u64.to_be_bytes());
            let payload = br#"{"lastSequence":1,"observer":{"kind":"closed"}}"#;
            closed.extend_from_slice(&(payload.len() as u32).to_be_bytes());
            closed.extend_from_slice(payload);
            let retained_end = producer.record_frame(loans, &closed, end).unwrap();
            let after = loans.business_usage().unwrap();
            let terminal = lifetime.while_business_active(|| ());
            drop(prepared);
            assert!(lifetime.finish_without_acquisition().is_ok());

            assert_eq!((retained_fact.kind(), retained_fact.sequence()), (1, 1));
            assert_eq!((retained_end.kind(), retained_end.sequence()), (2, 2));
            assert!(after.0.literal.decode_bytes > before.0.literal.decode_bytes);
            assert!(after.0.literal.values > before.0.literal.values);
            assert_eq!(
                (before.0.byte_visits, before.0.slots, before.1, before.2),
                (after.0.byte_visits, after.0.slots, after.1, after.2)
            );
            assert!(
                matches!(terminal, Err(error) if matches!(error.test_cause(), inputs::BrowserInputFault::DocumentClosed))
            );
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
fn browser_result_escrow_14_delayed_sdk_host_join_still_requires_fresh_operand_work() {
    with_opening_setup(
        Duration::from_secs(10),
        |run, loans, producer, transcript, stimulus, _| {
            let plan = run.prepare_result_plan(loans).unwrap();
            let action = run.next_action(loans).unwrap().unwrap();
            let (owned, lifetime) = action
                .prepare_connected_controller(producer, transcript, stimulus, loans)
                .unwrap();
            let sdk = owned
                .connected_opening(producer, transcript, stimulus, loans)
                .unwrap();
            let prepared =
                SourceResultPreparation::prepare_selected_runtime(plan, &lifetime, loans)
                    .ok()
                    .unwrap();
            producer.validate_host(loans, stimulus).unwrap();
            lifetime.while_business_active(|| ()).unwrap();
            // This is the real unsupported ordering, not an assertion that an
            // actual host join or transport adapter has somehow been funded.
            let join = sdk.validate_host(producer, transcript, stimulus, loans);
            let sticky = loans.business_test_ready();
            drop(prepared);
            assert!(lifetime.finish_without_acquisition().is_ok());
            use crate::workbench::model_originals::workflow::decode::{
                DecodeError, OperandResource,
            };
            assert!(
                matches!(join, Err(BrowserActionIssueError::Input(error)) if matches!(
                    error.test_cause(), inputs::BrowserInputFault::Decode(DecodeError::Work(OperandResource::ByteVisits))
                ))
            );
            assert!(matches!(sticky, Err(error) if matches!(
                error.test_cause(), inputs::BrowserInputFault::Decode(DecodeError::Work(OperandResource::ByteVisits))
            )));
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
