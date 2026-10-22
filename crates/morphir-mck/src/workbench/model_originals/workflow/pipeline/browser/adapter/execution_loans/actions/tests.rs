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

const SOURCE_CONTROLLER_FIXTURE_LIMITS:&[u8]=br#"{"rpcFrames":"checker-capture","retainedBytes":8388608,"stdoutPrefixBytes":4096,"stderrPrefixBytes":4096,"snapshotReadBytes":1048576,"byteVisits":8388608,"records":0}"#;

// Full controller setup includes its immutable ten-second business envelope.
// One GiB matches the existing Standard checker work ceiling. Only receiving
// work differs from the small control above; this is not a production default.
const FULL_CONTROLLER_SETUP_LIMITS:&[u8]=br#"{"rpcFrames":"checker-capture","retainedBytes":8388608,"stdoutPrefixBytes":4096,"stderrPrefixBytes":4096,"snapshotReadBytes":1048576,"byteVisits":1073741824,"records":0}"#;

pub(in crate::workbench::model_originals::workflow::pipeline::browser) fn with_full_controller_setup(
    action: impl FnOnce(SourceControllerLifetime, &mut BrowserLoans<'_, '_>),
) {
    with_source_controller_limits(FULL_CONTROLLER_SETUP_LIMITS, action);
}

pub(in crate::workbench::model_originals::workflow::pipeline::browser) fn with_revoked_full_controller_setup<
    R,
>(
    prepare: impl FnOnce(SourceControllerLifetime, &mut BrowserLoans<'_, '_>) -> R,
    after_revoke: impl FnOnce(R),
) {
    with_source_controller_fixture_limits(
        FULL_CONTROLLER_SETUP_LIMITS,
        |lifetime, inner, global, child| {
            let mut loans = BrowserLoans::execution(inner, global, child).unwrap();
            prepare(lifetime, &mut loans)
        },
        after_revoke,
    );
}

/// Initial transcript construction only, never an end mutation or renewal.
pub(in crate::workbench::model_originals::workflow::pipeline::browser) fn with_source_controller_end(
    original_for: std::time::Duration,
    action: impl FnOnce(SourceControllerLifetime, &mut BrowserLoans<'_, '_>),
) {
    with_source_controller_fixture_endpoint(
        SOURCE_CONTROLLER_FIXTURE_LIMITS,
        crate::workbench::model_originals::workflow::pipeline::browser::BrowserDocumentBounds::new(
            1, 128, 128,
        )
        .unwrap(),
        original_for,
        |lifetime, inner, global, child, _producer| {
            let mut loans = BrowserLoans::execution(inner, global, child).unwrap();
            action(lifetime, &mut loans);
        },
        |_| {},
    )
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
    with_source_controller_fixture_limits(SOURCE_CONTROLLER_FIXTURE_LIMITS, prepare, finish);
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
    with_source_controller_fixture_endpoint(
        limits,
        crate::workbench::model_originals::workflow::pipeline::browser::BrowserDocumentBounds::new(
            1, 128, 128,
        )
        .unwrap(),
        std::time::Duration::from_secs(10),
        |lifetime, inner, global, child, _producer| prepare(lifetime, inner, global, child),
        finish,
    )
}

pub(in crate::workbench::model_originals::workflow::pipeline::browser) fn with_source_controller_endpoint(
    limits: &[u8],
    action: impl FnOnce(
        SourceControllerLifetime,
        &mut BrowserLoans<'_, '_>,
        &mut crate::workbench::model_originals::workflow::pipeline::browser::BrowserDocumentProducer,
    ),
) {
    with_source_controller_fixture_endpoint(
        limits,
        crate::workbench::model_originals::workflow::pipeline::browser::BrowserDocumentBounds::new(
            2, 1024, 512,
        )
        .unwrap(),
        std::time::Duration::from_secs(10),
        |lifetime, inner, global, child, producer| {
            let mut loans = BrowserLoans::execution(inner, global, child).unwrap();
            action(lifetime, &mut loans, producer);
        },
        |_| {},
    )
}

/// Named high-work artifact control only. Ordinary helpers and their explicit
/// one-GiB decoder refusal remain unchanged.
pub(in crate::workbench::model_originals::workflow::pipeline::browser) fn with_source_controller_artifact_control(
    action: impl FnOnce(SourceControllerLifetime, &mut BrowserLoans<'_, '_>),
) {
    with_source_controller_artifact_endpoint(|lifetime, loans, _producer| action(lifetime, loans))
}
/// Deliberately small retained backing with the SAME explicit artifact work.
/// Used to expose cleanup-capacity refusal, never as a production default.
pub(in crate::workbench::model_originals::workflow::pipeline::browser) fn with_source_controller_cleanup_control(
    action: impl FnOnce(SourceControllerLifetime, &mut BrowserLoans<'_, '_>),
) {
    with_source_controller_fixture_policy(
        SourceControllerFixture::CleanupCapacityControl,
        crate::workbench::model_originals::workflow::pipeline::browser::BrowserDocumentBounds::new(
            2, 1024, 512,
        )
        .unwrap(),
        std::time::Duration::from_secs(10),
        |lifetime, inner, global, child, _producer| {
            let mut loans = BrowserLoans::execution(inner, global, child).unwrap();
            action(lifetime, &mut loans)
        },
        |_| {},
    )
}
pub(in crate::workbench::model_originals::workflow::pipeline::browser) fn with_source_controller_artifact_endpoint(
    action: impl FnOnce(
        SourceControllerLifetime,
        &mut BrowserLoans<'_, '_>,
        &mut crate::workbench::model_originals::workflow::pipeline::browser::BrowserDocumentProducer,
    ),
) {
    with_source_controller_fixture_policy(
        SourceControllerFixture::ArtifactControl,
        crate::workbench::model_originals::workflow::pipeline::browser::BrowserDocumentBounds::new(
            2, 1024, 512,
        )
        .unwrap(),
        std::time::Duration::from_secs(10),
        |lifetime, inner, global, child, producer| {
            let mut loans = BrowserLoans::execution(inner, global, child).unwrap();
            action(lifetime, &mut loans, producer)
        },
        |_| {},
    )
}
enum SourceControllerFixture<'a> {
    Standard(&'a [u8]),
    ArtifactControl,
    CleanupCapacityControl,
}
fn with_source_controller_fixture_endpoint<R>(
    limits: &[u8],
    document_bounds:crate::workbench::model_originals::workflow::pipeline::browser::BrowserDocumentBounds,
    original_for: std::time::Duration,
    prepare: impl FnOnce(
        SourceControllerLifetime,
        &mut inputs::BrowserOwnerLoans<'_>,
        &BrowserSourceScope,
        &ExecutionChild,
        &mut crate::workbench::model_originals::workflow::pipeline::browser::BrowserDocumentProducer,
    ) -> R,
    finish: impl FnOnce(R),
) {
    with_source_controller_fixture_policy(
        SourceControllerFixture::Standard(limits),
        document_bounds,
        original_for,
        prepare,
        finish,
    )
}
fn with_source_controller_fixture_policy<R>(
    fixture: SourceControllerFixture<'_>,
    document_bounds:crate::workbench::model_originals::workflow::pipeline::browser::BrowserDocumentBounds,
    original_for: std::time::Duration,
    prepare: impl FnOnce(
        SourceControllerLifetime,
        &mut inputs::BrowserOwnerLoans<'_>,
        &BrowserSourceScope,
        &ExecutionChild,
        &mut crate::workbench::model_originals::workflow::pipeline::browser::BrowserDocumentProducer,
    ) -> R,
    finish: impl FnOnce(R),
) {
    use crate::workbench::model_originals::workflow::pipeline::browser::{
        BrowserDocumentBounds, BrowserRowCollection,
    };
    with_source_controller_compiled_fixture(fixture, |compiled, inner| {
        let core = controlled_clients(compiled)[0];
        let global = BrowserSourceScope::prepare(inner).unwrap();
        let mut child = ExecutionChild::prepare(&global, inner).unwrap();
        let run = PreparedBrowserClientRun::prepare(core, &global, &child, inner).unwrap();
        let mut loans = BrowserLoans::execution(inner, &global, &child).unwrap();
        let opening = run.openings(&mut loans).unwrap().next().unwrap();
        let stimulus = run.prepare_controlled_host(&opening, &mut loans).unwrap();
        let mut collection =
            BrowserRowCollection::prepare(&run, &mut loans, document_bounds).unwrap();
        let mut producer = collection
            .producer()
            .issue(&run, &opening, &mut loans)
            .unwrap();
        let transcript = producer
            .prepare_host_transcript(
                &mut loans,
                &stimulus,
                std::time::Instant::now() + original_for,
            )
            .unwrap();
        let issued = run.next_action(&mut loans).unwrap().unwrap();
        let prepared = PreparedConnectedOpening::prepare(&run, issued, &mut loans).unwrap();
        let (action_owner, lifetime) = prepared
            .into_controller_parts(&producer, &transcript, &stimulus, &mut loans)
            .unwrap();
        drop(loans);
        let result = prepare(lifetime, inner, &global, &child, &mut producer);
        drop(action_owner);
        drop(opening);
        drop(run);
        // The real issuing scope revokes after the callback/borrowed run
        // ends; no synthetic identity or alternate revocation broker.
        child.revoke();
        finish(result);
    });
}
fn with_source_controller_compiled_fixture(
    fixture: SourceControllerFixture<'_>,
    action: impl FnOnce(&[CompiledExecution<'_, '_, '_, '_>], &mut inputs::BrowserOwnerLoans<'_>),
) {
    match fixture {
        SourceControllerFixture::Standard(limits) => {
            super::super::tests::with_compiled_limits(limits, action)
        }
        SourceControllerFixture::ArtifactControl => {
            super::super::tests::with_compiled_artifact_control(action)
        }
        SourceControllerFixture::CleanupCapacityControl => {
            super::super::tests::with_compiled_cleanup_control(action)
        }
    }
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

#[test]
fn browser_source_operation_08_borrowed_source0_tracks_same_journal_across_host_moves() {
    use crate::workbench::model_originals::workflow::pipeline::browser::{
        BrowserDocumentBounds, BrowserRowCollection,
    };
    with_compiled(|compiled, inner| {
        let core = controlled_clients(compiled)[0];
        let global = BrowserSourceScope::prepare(inner).unwrap();
        let child = ExecutionChild::prepare(&global, inner).unwrap();
        let run = PreparedBrowserClientRun::prepare(core, &global, &child, inner).unwrap();
        let mut loans = BrowserLoans::execution(inner, &global, &child).unwrap();
        let application = loans.prepare_application_source().unwrap();
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
        let BrowserActionKind::BeginConnectedOpening {
            source, project_id, ..
        } = action.kind()
        else {
            panic!("genuine source0")
        };
        let borrowed = action
            .connected_opening(&producer, &transcript, &stimulus, &mut loans)
            .unwrap();
        assert_eq!(borrowed.provider_id(), source.provider_id);
        assert_eq!(borrowed.locator(), source.locator);
        assert_eq!(borrowed.project_id(), project_id);
        // Actual native host construction moves these owners. Wrapper addresses
        // cannot be the source association, and the borrowed SDK cannot pin them.
        let moved = (producer, transcript, stimulus);
        assert_eq!(
            borrowed
                .validate_host(&moved.0, &moved.1, &moved.2, &mut loans)
                .unwrap(),
            end
        );
        borrowed
            .validate_application(&application, &moved.2, &mut loans)
            .unwrap();
        assert!(matches!(
            run.actions_terminal(),
            BrowserActionCursorTerminal::Incomplete {
                consumed: 0,
                pending: Some(0),
                ..
            }
        ));
        drop(borrowed);
        assert!(matches!(
            run.actions_terminal(),
            BrowserActionCursorTerminal::Incomplete {
                pending: Some(0),
                ..
            }
        ));
    });
}

#[test]
fn browser_source_operation_09_borrowed_source0_rejects_other_same_child_journal_before_debit() {
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
        let mut pa = a.producer().issue(&run, &opening, &mut loans).unwrap();
        let mut pb = b.producer().issue(&run, &opening, &mut loans).unwrap();
        let end = std::time::Instant::now() + std::time::Duration::from_secs(10);
        let ta = pa
            .prepare_host_transcript(&mut loans, &stimulus, end)
            .unwrap();
        let tb = pb
            .prepare_host_transcript(&mut loans, &stimulus, end)
            .unwrap();
        let action = run.next_action(&mut loans).unwrap().unwrap();
        let borrowed = action
            .connected_opening(&pa, &ta, &stimulus, &mut loans)
            .unwrap();
        let before = {
            let (d, r, c) = loans.inner.physical_owners().unwrap();
            (d.usage(), r.usage(), c.usage())
        };
        assert!(
            borrowed
                .validate_host(&pb, &tb, &stimulus, &mut loans)
                .is_err()
        );
        let after = {
            let (d, r, c) = loans.inner.physical_owners().unwrap();
            (d.usage(), r.usage(), c.usage())
        };
        assert_eq!(before, after);
        borrowed
            .validate_host(&pa, &ta, &stimulus, &mut loans)
            .unwrap();
    });
}

#[test]
fn browser_source_operation_10_borrowed_source0_keeps_original_expired_end() {
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
        let end = std::time::Instant::now() + std::time::Duration::from_millis(100);
        let transcript = producer
            .prepare_host_transcript(&mut loans, &stimulus, end)
            .unwrap();
        let action = run.next_action(&mut loans).unwrap().unwrap();
        let borrowed = action
            .connected_opening(&producer, &transcript, &stimulus, &mut loans)
            .unwrap();
        std::thread::sleep(
            end.saturating_duration_since(std::time::Instant::now())
                + std::time::Duration::from_millis(1),
        );
        assert!(matches!(borrowed.validate_host(&producer,&transcript,&stimulus,&mut loans),Err(BrowserActionIssueError::Host(crate::workbench::model_originals::workflow::pipeline::browser::BrowserHostTranscriptFault::End))));
        assert!(matches!(
            run.actions_terminal(),
            BrowserActionCursorTerminal::Incomplete {
                pending: Some(0),
                ..
            }
        ));
    });
}

#[test]
fn browser_source_operation_11_original_end_refuses_buffer_allocation_without_new_debit() {
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
        let end = std::time::Instant::now() + std::time::Duration::from_millis(100);
        let transcript = producer
            .prepare_host_transcript(&mut loans, &stimulus, end)
            .unwrap();
        let action = run.next_action(&mut loans).unwrap().unwrap();
        let prepared = PreparedConnectedOpening::prepare(&run, action, &mut loans).unwrap();
        let (_action, lifetime) = prepared
            .into_controller_parts(&producer, &transcript, &stimulus, &mut loans)
            .unwrap();
        std::thread::sleep(
            end.saturating_duration_since(std::time::Instant::now())
                + std::time::Duration::from_millis(1),
        );
        let before = {
            let (d, r, c) = loans.inner.physical_owners().unwrap();
            (d.usage(), r.usage(), c.usage())
        };
        let refused = loans.prepare_controller_buffers(
            &lifetime,
            crate::transport::Limits {
                max_frame: 128,
                stderr_capture: 64,
                ..crate::transport::Limits::DEFAULT
            },
        );
        let error = refused
            .err()
            .expect("expired source must not allocate a new physical capture owner");
        assert!(matches!(
            error.cause,
            inputs::BrowserInputFault::OriginalEnd
        ));
        let after = {
            let (d, r, c) = loans.inner.physical_owners().unwrap();
            (d.usage(), r.usage(), c.usage())
        };
        assert_eq!(before, after);
        // Teardown bookkeeping remains usable after the deadline. This fixture
        // makes no actual process/file join assertion and deliberately retains debt.
        assert!(matches!(
            child.terminal(),
            BrowserSourceTerminal::Unfinished { bindings: 2 }
        ));
    });
}

#[test]
fn browser_source_operation_12_document_fault_or_end_prevents_new_source_retention() {
    use crate::workbench::model_originals::workflow::pipeline::browser::{
        BrowserDocumentBounds, BrowserRowCollection,
    };
    fn literal(kind: u8, sequence: u64, payload: &[u8]) -> Vec<u8> {
        let mut frame = vec![0; 16];
        frame[0] = 1;
        frame[1] = kind;
        frame[4..12].copy_from_slice(&sequence.to_be_bytes());
        frame[12..16].copy_from_slice(&u32::try_from(payload.len()).unwrap().to_be_bytes());
        frame.extend_from_slice(payload);
        frame
    }
    enum ActualTerminal {
        Fault,
        End,
    }
    let mut outcomes = Vec::new();
    for terminal in [ActualTerminal::Fault, ActualTerminal::End] {
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
            let end = std::time::Instant::now() + std::time::Duration::from_secs(10);
            let transcript = producer
                .prepare_host_transcript(&mut loans, &stimulus, end)
                .unwrap();
            let action = run.next_action(&mut loans).unwrap().unwrap();
            let source0 = action
                .connected_opening(&producer, &transcript, &stimulus, &mut loans)
                .unwrap();
            match terminal {
                ActualTerminal::Fault => {
                    producer
                        .record_frame(&mut loans, &[], end)
                        .err()
                        .expect("actual framing refusal");
                }
                ActualTerminal::End => {
                    let fact=literal(1,1,br#"{"sequence":1,"kind":"model-closed","actual":{"workspace":"unit","opening":0}}"#);
                    let close =
                        literal(2, 2, br#"{"lastSequence":1,"observer":{"kind":"closed"}}"#);
                    producer.record_frame(&mut loans, &fact, end).unwrap();
                    producer.record_frame(&mut loans, &close, end).unwrap();
                }
            }
            let mut invoked = false;
            let refused = source0.while_host_active(&mut loans, || {
                invoked = true;
            });
            outcomes.push((refused.err(), invoked));
            assert!(matches!(
                run.actions_terminal(),
                BrowserActionCursorTerminal::Incomplete {
                    pending: Some(0),
                    ..
                }
            ));
        });
    }
    assert!(matches!(outcomes.as_slice(), [
        (Some(BrowserActionIssueError::Collection(crate::workbench::model_originals::workflow::pipeline::browser::BrowserCollectionFault::Framing)),false),
        (Some(BrowserActionIssueError::DocumentClosed),false),
    ]),"actual framing fault and normal END preserve their distinct refusal kinds");
}
