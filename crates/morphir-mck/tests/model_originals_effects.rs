//! Independent lifecycle contracts and additive source-backed regressions.
//! These checks validate evidence consistency, not actual production execution.
use morphir_mck::workbench::model_originals::{
    CancellationCause, EffectEvent as Event, EffectKind as Kind, EffectLedger, EffectLedgerError,
    EffectLedgerLimits, EffectPort, EffectRef, FixtureAlias, LateDisposition, LateSignalSource,
    PickerSignal, PublicationDisposition, ResultRetirement, SelectionRefusal, WorkOwner,
};

fn reference(attempt: &str, kind: Kind, ordinal: usize) -> EffectRef {
    EffectRef::new(attempt, kind, ordinal).unwrap()
}
fn ledger() -> EffectLedger<'static> {
    EffectLedger::new(EffectLedgerLimits::new(64, 512, 4096, 8192, 16384).unwrap())
}
fn promise(ledger: &mut EffectLedger<'_>, effect: &EffectRef) {
    ledger
        .record(effect, Event::Pending(EffectPort::Promise))
        .unwrap();
}

#[test]
fn ordered_storage_preserves_gapfree_names_and_independent_work_ownership() {
    let work = FixtureAlias::new("actual-work").unwrap();
    let mut actual = EffectLedger::new(EffectLedgerLimits::new(8, 32, 64, 64, 64).unwrap());
    let z = reference("Z", Kind::Inspection, 0);
    let a = reference("A", Kind::Inspection, 0);
    let a1 = reference("A", Kind::Inspection, 1);
    let gap = reference("A", Kind::Inspection, 3);
    promise(&mut actual, &z);
    promise(&mut actual, &a);
    assert_eq!(
        actual.record(&gap, Event::Pending(EffectPort::Promise)),
        Err(EffectLedgerError::Ordinal)
    );
    promise(&mut actual, &a1);
    let pending: Vec<_> = actual.pending_effects().cloned().collect();
    assert_eq!(pending, vec![a.clone(), a1.clone(), z.clone()]);
    actual
        .record(
            &z,
            Event::WorkStarted {
                work: &work,
                owner: WorkOwner::Inline,
            },
        )
        .unwrap();
    assert_eq!(
        actual.record(
            &a,
            Event::WorkStarted {
                work: &work,
                owner: WorkOwner::Inline
            }
        ),
        Err(EffectLedgerError::Work)
    );
    assert_eq!(actual.recorded_work(&a).unwrap(), None);
    assert_eq!(
        actual.recorded_work(&z).unwrap().unwrap().invocation(),
        &work
    );
    actual
        .record(&z, Event::WorkExited { work: &work })
        .unwrap();
    for effect in [&a, &a1, &z] {
        actual.record(effect, Event::PromiseRejected).unwrap();
    }
    assert_eq!(actual.port_count(), 3);
    assert_eq!(actual.pending_effects().count(), 0);
    actual.finish().unwrap();
}

#[test]
fn non_core_settlement_does_not_substitute_for_produced_work_or_reopen_a_terminal_port() {
    let effect = reference("actual-attempt", Kind::Inspection, 0);
    let work = FixtureAlias::new("actual-work").unwrap();
    for phase in 0..4 {
        let mut actual =
            EffectLedger::new(EffectLedgerLimits::new(64, 512, 4096, 8192, 16384).unwrap());
        promise(&mut actual, &effect);
        if phase < 3 {
            actual
                .record(
                    &effect,
                    Event::WorkStarted {
                        work: &work,
                        owner: WorkOwner::Inline,
                    },
                )
                .unwrap();
            if phase > 0 {
                actual
                    .record(
                        &effect,
                        Event::ResultPrepared {
                            work: &work,
                            raw_reply: "complete actual reply",
                        },
                    )
                    .unwrap();
            }
            if phase == 2 {
                actual
                    .record(
                        &effect,
                        Event::ResultRetired(ResultRetirement::DiscardedOnTeardown),
                    )
                    .unwrap();
            }
        } else {
            actual
                .record(&effect, Event::PromiseResolvedWithoutCoreResult)
                .unwrap();
        }
        assert!(
            actual
                .record(&effect, Event::PromiseResolvedWithoutCoreResult)
                .is_err()
        );
        assert_eq!(actual.pending_effects().count(), usize::from(phase < 3));
        assert_eq!(actual.prepared_effects().count(), usize::from(phase == 1));
    }
}

#[test]
fn workflow_effect_vocabulary_manifest_and_workspace_ports_keep_independent_ordinals_and_settlement()
 {
    let manifest0 = reference("actual-attempt", Kind::ManifestFetch, 0);
    let workspace0 = reference("actual-attempt", Kind::WorkspaceOpen, 0);
    let manifest1 = reference("actual-attempt", Kind::ManifestFetch, 1);
    let workspace1 = reference("actual-attempt", Kind::WorkspaceOpen, 1);
    let mut actual = ledger();
    promise(&mut actual, &manifest0);
    promise(&mut actual, &workspace0);
    assert_eq!(actual.port_count(), 2);
    assert_eq!(actual.finish(), Err(EffectLedgerError::PendingPorts));
    assert_eq!(
        actual.record(&manifest0, Event::Pending(EffectPort::Promise)),
        Err(EffectLedgerError::Duplicate)
    );
    assert_eq!(
        actual.record(
            &reference("actual-attempt", Kind::WorkspaceOpen, 2),
            Event::Pending(EffectPort::Promise)
        ),
        Err(EffectLedgerError::Ordinal)
    );
    actual
        .record(
            &manifest0,
            Event::PromiseResolved {
                actual_reply: "actual manifest response",
            },
        )
        .unwrap();
    assert_eq!(actual.finish(), Err(EffectLedgerError::PendingPorts));
    actual.record(&workspace0, Event::PromiseRejected).unwrap();
    actual.finish().unwrap();
    promise(&mut actual, &manifest1);
    promise(&mut actual, &workspace1);
    actual.record(&manifest1, Event::PromiseRejected).unwrap();
    actual
        .record(
            &workspace1,
            Event::PromiseResolved {
                actual_reply: "actual workspace response",
            },
        )
        .unwrap();
    assert_eq!(actual.port_count(), 4);
    assert_eq!(actual.event_count(), 8);
    assert_eq!(actual.held_result_bytes(), 0);
    actual.finish().unwrap();
}

#[test]
fn workflow_effect_vocabulary_new_io_kinds_cannot_prepare_core_results_or_work() {
    let work = FixtureAlias::new("actual-work").unwrap();
    for kind in [Kind::ManifestFetch, Kind::WorkspaceOpen] {
        let effect = reference("actual-attempt", kind, 0);
        let mut actual = ledger();
        promise(&mut actual, &effect);
        assert_eq!(
            actual.record(
                &effect,
                Event::WorkStarted {
                    work: &work,
                    owner: WorkOwner::Inline
                }
            ),
            Err(EffectLedgerError::Work)
        );
        assert_eq!(
            actual.record(
                &effect,
                Event::ResultPrepared {
                    work: &work,
                    raw_reply: "actual IO reply"
                }
            ),
            Err(EffectLedgerError::Work)
        );
        assert_eq!(actual.held_result_bytes(), 0);
        actual.record(&effect, Event::PromiseRejected).unwrap();
        actual.finish().unwrap();
    }
}

#[test]
fn local_evaluation_settlement_does_not_retire_work_or_exact_result() {
    let work = FixtureAlias::new("local-evaluation-A").unwrap();
    let effect = reference("A", Kind::LocalEvaluation, 0);
    let mut l = EffectLedger::new(EffectLedgerLimits::new(4, 32, 128, 128, 512).unwrap());
    promise(&mut l, &effect);
    l.record(
        &effect,
        Event::WorkStarted {
            work: &work,
            owner: WorkOwner::Inline,
        },
    )
    .unwrap();
    l.record(
        &effect,
        Event::ResultPrepared {
            work: &work,
            raw_reply: "{\"value\":9007199254740993}",
        },
    )
    .unwrap();
    assert_eq!(
        l.record(
            &effect,
            Event::PromiseResolved {
                actual_reply: "{\"value\":9007199254740992}"
            }
        ),
        Err(EffectLedgerError::ResultMismatch)
    );
    assert_eq!(l.finish(), Err(EffectLedgerError::PendingPorts));
    l.record(
        &effect,
        Event::PromiseResolved {
            actual_reply: "{\"value\":9007199254740993}",
        },
    )
    .unwrap();
    assert_eq!(l.finish(), Err(EffectLedgerError::HeldResults));
    l.record(
        &effect,
        Event::ResultRetired(ResultRetirement::DeliveredToPort),
    )
    .unwrap();
    assert_eq!(l.finish(), Err(EffectLedgerError::RunningWork));
    assert_eq!(l.held_result_bytes(), 0);
    assert_eq!(l.produced_result_bytes(), 26);
    l.record(&effect, Event::WorkExited { work: &work })
        .unwrap();
    assert_eq!(
        l.recorded_work(&effect).unwrap().unwrap().owner(),
        WorkOwner::Inline
    );
    l.finish().unwrap();
}

#[test]
fn cancelled_local_evaluation_keeps_work_until_exit_after_late_result_discard() {
    let work = FixtureAlias::new("cancelled-evaluation").unwrap();
    let worker = FixtureAlias::new("evaluation-worker").unwrap();
    let effect = reference("A", Kind::LocalEvaluation, 0);
    let mut l = EffectLedger::new(EffectLedgerLimits::new(4, 32, 16, 16, 64).unwrap());
    promise(&mut l, &effect);
    l.record(
        &effect,
        Event::WorkStarted {
            work: &work,
            owner: WorkOwner::Worker(&worker),
        },
    )
    .unwrap();
    l.record(
        &effect,
        Event::CancellationRequested {
            action_index: 1,
            cause: CancellationCause::CloseModel,
        },
    )
    .unwrap();
    l.record(&effect, Event::PromiseRejected).unwrap();
    assert_eq!(l.finish(), Err(EffectLedgerError::RunningWork));
    l.record(
        &effect,
        Event::ResultPrepared {
            work: &work,
            raw_reply: "375e-1",
        },
    )
    .unwrap();
    l.record(
        &effect,
        Event::LateSignal {
            actual_signal: "375e-1",
            disposition: LateDisposition::SettledPort,
            source: LateSignalSource::HeldCoreResult,
        },
    )
    .unwrap();
    l.record(
        &effect,
        Event::ResultRetired(ResultRetirement::DiscardedAfterGuard),
    )
    .unwrap();
    assert_eq!(l.finish(), Err(EffectLedgerError::RunningWork));
    l.record(&effect, Event::WorkExited { work: &work })
        .unwrap();
    assert_eq!(
        l.recorded_work(&effect).unwrap().unwrap().owner(),
        WorkOwner::Worker(&worker)
    );
    l.finish().unwrap();
}

#[test]
fn discovery_and_native_transport_are_not_core_evaluation_work() {
    let work = FixtureAlias::new("not-a-core-invocation").unwrap();
    let mut l = EffectLedger::new(EffectLedgerLimits::new(8, 32, 128, 128, 512).unwrap());
    for kind in [Kind::Catalog, Kind::NativeInvoke] {
        for ordinal in 0..2 {
            let effect = reference("A", kind, ordinal);
            promise(&mut l, &effect);
            let before = l.event_count();
            assert_eq!(
                l.record(
                    &effect,
                    Event::WorkStarted {
                        work: &work,
                        owner: WorkOwner::Inline
                    }
                ),
                Err(EffectLedgerError::Work)
            );
            assert_eq!(l.event_count(), before);
            assert_eq!(l.recorded_work(&effect).unwrap(), None);
            l.record(&effect, Event::PromiseResolved { actual_reply: "{}" })
                .unwrap();
        }
    }
    assert_eq!(l.port_count(), 4);
    assert_eq!(l.produced_result_bytes(), 0);
    l.finish().unwrap();
}

#[test]
fn ordinals_are_gap_free_per_attempt_and_kind_including_cancelled_and_rejected_ports() {
    let mut l = ledger();
    let a = reference("A", Kind::FileRead, 0);
    promise(&mut l, &a);
    l.record(
        &a,
        Event::CancellationRequested {
            action_index: 0,
            cause: CancellationCause::CloseCurrentModel,
        },
    )
    .unwrap();
    l.record(&a, Event::PromiseRejected).unwrap();
    assert_eq!(
        l.record(&a, Event::Pending(EffectPort::Promise)),
        Err(EffectLedgerError::Duplicate)
    );
    assert_eq!(
        l.record(
            &reference("A", Kind::FileRead, 2),
            Event::Pending(EffectPort::Promise)
        ),
        Err(EffectLedgerError::Ordinal)
    );
    for effect in [
        reference("A", Kind::FileRead, 1),
        reference("B", Kind::FileRead, 0),
        reference("A", Kind::Digest, 0),
    ] {
        promise(&mut l, &effect);
        l.record(&effect, Event::PromiseRejected).unwrap();
    }
    l.finish().unwrap();
}

#[test]
fn a_cancellation_request_never_settles_a_promise() {
    let mut l = ledger();
    let effect = reference("A", Kind::Inspection, 0);
    promise(&mut l, &effect);
    for action_index in [0, 1, 1] {
        l.record(
            &effect,
            Event::CancellationRequested {
                action_index,
                cause: CancellationCause::CancelOpening,
            },
        )
        .unwrap();
    }
    assert_eq!(l.finish(), Err(EffectLedgerError::PendingPorts));
    l.record(&effect, Event::PromiseRejected).unwrap();
    l.record(
        &effect,
        Event::CancellationRequested {
            action_index: 2,
            cause: CancellationCause::Teardown,
        },
    )
    .unwrap();
    assert_eq!(
        l.record(
            &effect,
            Event::PromiseResolved {
                actual_reply: "late"
            }
        ),
        Err(EffectLedgerError::Settlement)
    );
    assert_eq!(
        l.record(&effect, Event::PromiseRejected),
        Err(EffectLedgerError::Settlement)
    );
    l.finish().unwrap();
}

#[test]
fn picker_selection_and_file_read_are_separate_from_receive_retirement() {
    let mut l = ledger();
    let picker = reference("A", Kind::Picker, 0);
    let read = reference("A", Kind::FileRead, 0);
    l.record(&picker, Event::Pending(EffectPort::PickerReceiveCallback))
        .unwrap();
    l.record(&picker, Event::PickerInput(PickerSignal::FileSelection))
        .unwrap();
    promise(&mut l, &read);
    l.record(
        &picker,
        Event::CallbackRetired {
            action_index: 1,
            cause: CancellationCause::CloseCurrentModel,
        },
    )
    .unwrap();
    assert_eq!(l.finish(), Err(EffectLedgerError::PendingPorts));
    l.record(
        &read,
        Event::PromiseResolved {
            actual_reply: "actual read bytes",
        },
    )
    .unwrap();
    l.record(
        &picker,
        Event::LateSignal {
            actual_signal: "actual readModelFile result",
            disposition: LateDisposition::RetiredCallback,
            source: LateSignalSource::FileReadCompletion(&read),
        },
    )
    .unwrap();
    assert_eq!(
        l.record(&picker, Event::CallbackDelivered),
        Err(EffectLedgerError::Settlement)
    );
    l.finish().unwrap();
}

#[test]
fn consumed_and_retired_callbacks_have_distinct_late_guards() {
    let mut l = ledger();
    let picker = reference("A", Kind::Picker, 0);
    l.record(&picker, Event::Pending(EffectPort::PickerReceiveCallback))
        .unwrap();
    l.record(&picker, Event::PickerInput(PickerSignal::CancelEvent))
        .unwrap();
    l.record(&picker, Event::CallbackDelivered).unwrap();
    assert_eq!(
        l.record(
            &picker,
            Event::LateSignal {
                actual_signal: "later input",
                disposition: LateDisposition::RetiredCallback,
                source: LateSignalSource::CancelEvent
            }
        ),
        Err(EffectLedgerError::LateSignal)
    );
    l.record(
        &picker,
        Event::LateSignal {
            actual_signal: "later input",
            disposition: LateDisposition::ConsumedCallback,
            source: LateSignalSource::CancelEvent,
        },
    )
    .unwrap();
    l.finish().unwrap();
}

#[test]
fn ports_cannot_be_created_by_a_settlement_or_mismatched_registration() {
    let mut l = ledger();
    let effect = reference("A", Kind::Inspection, 0);
    assert_eq!(
        l.record(&effect, Event::PromiseRejected),
        Err(EffectLedgerError::UnknownPort)
    );
    assert_eq!(
        l.record(&effect, Event::Pending(EffectPort::PickerReceiveCallback)),
        Err(EffectLedgerError::PortKind)
    );
    assert_eq!(
        EffectRef::new("bad/alias", Kind::Inspection, 0),
        Err(EffectLedgerError::Alias)
    );
    assert_eq!(
        EffectRef::new("A", Kind::Inspection, 8192),
        Err(EffectLedgerError::Ordinal)
    );
}

#[test]
fn prepared_cancelled_result_is_exact_and_retained_independently_of_port_settlement() {
    let work = FixtureAlias::new("actual-core-A").unwrap();
    let mut l = EffectLedger::new(EffectLedgerLimits::new(4, 32, 1024, 1024, 4096).unwrap());
    let effect = reference("A", Kind::Inspection, 0);
    promise(&mut l, &effect);
    l.record(
        &effect,
        Event::WorkStarted {
            work: &work,
            owner: WorkOwner::Inline,
        },
    )
    .unwrap();
    l.record(
        &effect,
        Event::ResultPrepared {
            work: &work,
            raw_reply: "{\"value\":9007199254740993}",
        },
    )
    .unwrap();
    l.record(&effect, Event::PromiseRejected).unwrap();
    assert_eq!(
        l.record(
            &effect,
            Event::LateSignal {
                actual_signal: "{\"value\":9007199254740992}",
                disposition: LateDisposition::SettledPort,
                source: LateSignalSource::HeldCoreResult
            }
        ),
        Err(EffectLedgerError::ResultMismatch)
    );
    l.record(
        &effect,
        Event::LateSignal {
            actual_signal: "{\"value\":9007199254740993}",
            disposition: LateDisposition::SettledPort,
            source: LateSignalSource::HeldCoreResult,
        },
    )
    .unwrap();
    l.record(&effect, Event::WorkExited { work: &work })
        .unwrap();
    assert_eq!(l.finish(), Err(EffectLedgerError::HeldResults));
    l.record(
        &effect,
        Event::ResultRetired(ResultRetirement::DiscardedAfterGuard),
    )
    .unwrap();
    assert_eq!(
        l.record(
            &effect,
            Event::LateSignal {
                actual_signal: "{\"value\":9007199254740993}",
                disposition: LateDisposition::SettledPort,
                source: LateSignalSource::HeldCoreResult
            }
        ),
        Err(EffectLedgerError::HeldResults)
    );
    l.finish().unwrap();
}

#[test]
fn work_can_finish_after_rejection_but_cannot_be_invented_after_settlement() {
    let work = FixtureAlias::new("actual-work").unwrap();
    let mut l = EffectLedger::new(EffectLedgerLimits::new(4, 32, 1024, 1024, 4096).unwrap());
    let effect = reference("A", Kind::Inspection, 0);
    promise(&mut l, &effect);
    l.record(
        &effect,
        Event::WorkStarted {
            work: &work,
            owner: WorkOwner::Inline,
        },
    )
    .unwrap();
    l.record(&effect, Event::PromiseRejected).unwrap();
    l.record(
        &effect,
        Event::ResultPrepared {
            work: &work,
            raw_reply: "actual late result",
        },
    )
    .unwrap();
    l.record(
        &effect,
        Event::ResultRetired(ResultRetirement::DiscardedOnTeardown),
    )
    .unwrap();
    assert_eq!(l.finish(), Err(EffectLedgerError::RunningWork));
    l.record(&effect, Event::WorkExited { work: &work })
        .unwrap();
    assert_eq!(
        l.record(
            &effect,
            Event::WorkStarted {
                work: &work,
                owner: WorkOwner::Inline
            }
        ),
        Err(EffectLedgerError::Work)
    );
    l.finish().unwrap();
}

#[test]
fn teardown_discard_does_not_settle_a_port_or_allow_later_result_delivery() {
    let work = FixtureAlias::new("work").unwrap();
    let mut l = EffectLedger::new(EffectLedgerLimits::new(4, 32, 1024, 1024, 4096).unwrap());
    let effect = reference("A", Kind::Inspection, 0);
    promise(&mut l, &effect);
    l.record(
        &effect,
        Event::WorkStarted {
            work: &work,
            owner: WorkOwner::Inline,
        },
    )
    .unwrap();
    l.record(
        &effect,
        Event::ResultPrepared {
            work: &work,
            raw_reply: "result",
        },
    )
    .unwrap();
    l.record(
        &effect,
        Event::ResultRetired(ResultRetirement::DiscardedOnTeardown),
    )
    .unwrap();
    assert_eq!(
        l.record(
            &effect,
            Event::PromiseResolved {
                actual_reply: "result"
            }
        ),
        Err(EffectLedgerError::HeldResults)
    );
    assert_eq!(l.finish(), Err(EffectLedgerError::PendingPorts));
    l.record(&effect, Event::PromiseRejected).unwrap();
    l.record(&effect, Event::WorkExited { work: &work })
        .unwrap();
    l.finish().unwrap();
}

#[test]
fn publication_is_separate_once_and_never_implies_adoption() {
    let mut l = ledger();
    let effect = reference("A", Kind::Inspection, 0);
    promise(&mut l, &effect);
    assert_eq!(
        l.record(&effect, Event::Publication(PublicationDisposition::Ignored)),
        Err(EffectLedgerError::Publication)
    );
    l.record(
        &effect,
        Event::PromiseResolved {
            actual_reply: "actual result",
        },
    )
    .unwrap();
    l.record(&effect, Event::Publication(PublicationDisposition::Ignored))
        .unwrap();
    assert_eq!(
        l.record(
            &effect,
            Event::Publication(PublicationDisposition::Forwarded)
        ),
        Err(EffectLedgerError::Publication)
    );
    l.finish().unwrap();
}

#[test]
fn held_storage_is_refunded_but_cumulative_produced_bytes_are_not() {
    let work_a = FixtureAlias::new("work-A").unwrap();
    let work_b = FixtureAlias::new("work-B").unwrap();
    let mut l = EffectLedger::new(EffectLedgerLimits::new(4, 32, 4, 7, 64).unwrap());
    let a = reference("A", Kind::Inspection, 0);
    let b = reference("B", Kind::Inspection, 0);
    promise(&mut l, &a);
    l.record(
        &a,
        Event::WorkStarted {
            work: &work_a,
            owner: WorkOwner::Inline,
        },
    )
    .unwrap();
    l.record(
        &a,
        Event::ResultPrepared {
            work: &work_a,
            raw_reply: "éé",
        },
    )
    .unwrap();
    assert_eq!(l.held_result_bytes(), 4);
    l.record(
        &a,
        Event::ResultRetired(ResultRetirement::DiscardedOnTeardown),
    )
    .unwrap();
    assert_eq!(l.held_result_bytes(), 0);
    assert_eq!(l.produced_result_bytes(), 4);
    promise(&mut l, &b);
    l.record(
        &b,
        Event::WorkStarted {
            work: &work_b,
            owner: WorkOwner::Inline,
        },
    )
    .unwrap();
    assert!(matches!(
        l.record(
            &b,
            Event::ResultPrepared {
                work: &work_b,
                raw_reply: "abcd"
            }
        ),
        Err(EffectLedgerError::Resource(_))
    ));
    assert_eq!(l.produced_result_bytes(), 4);
    l.record(
        &b,
        Event::ResultPrepared {
            work: &work_b,
            raw_reply: "abc",
        },
    )
    .unwrap();
    assert_eq!(l.produced_result_bytes(), 7);
}

#[test]
fn rejected_raw_equality_attempts_consume_observer_work_without_settling_the_port() {
    let work = FixtureAlias::new("actual-work").unwrap();
    let effect = reference("A", Kind::Inspection, 0);
    let mut l = EffectLedger::new(EffectLedgerLimits::new(4, 32, 4, 4, 8).unwrap());
    promise(&mut l, &effect);
    l.record(
        &effect,
        Event::WorkStarted {
            work: &work,
            owner: WorkOwner::Inline,
        },
    )
    .unwrap();
    l.record(
        &effect,
        Event::ResultPrepared {
            work: &work,
            raw_reply: "abcd",
        },
    )
    .unwrap();
    assert_eq!(
        l.record(
            &effect,
            Event::PromiseResolved {
                actual_reply: "abce"
            }
        ),
        Err(EffectLedgerError::ResultMismatch)
    );
    assert_eq!(l.observer_bytes(), 8);
    assert!(matches!(
        l.record(
            &effect,
            Event::PromiseResolved {
                actual_reply: "abcd"
            }
        ),
        Err(EffectLedgerError::Resource(_))
    ));
    assert_eq!(l.observer_bytes(), 8);
    assert_eq!(l.finish(), Err(EffectLedgerError::PendingPorts));
}

#[test]
fn an_actual_prepared_result_can_outlive_work_and_resolve_once() {
    let work = FixtureAlias::new("invocation-A").unwrap();
    let worker = FixtureAlias::new("worker-A").unwrap();
    let effect = reference("A", Kind::Inspection, 0);
    let mut l = EffectLedger::new(EffectLedgerLimits::new(4, 32, 4, 4, 8).unwrap());
    promise(&mut l, &effect);
    l.record(
        &effect,
        Event::WorkStarted {
            work: &work,
            owner: WorkOwner::Worker(&worker),
        },
    )
    .unwrap();
    l.record(
        &effect,
        Event::ResultPrepared {
            work: &work,
            raw_reply: "abcd",
        },
    )
    .unwrap();
    l.record(&effect, Event::WorkExited { work: &work })
        .unwrap();
    let binding = l.recorded_work(&effect).unwrap().unwrap();
    assert_eq!(binding.invocation(), &work);
    assert_eq!(binding.owner(), WorkOwner::Worker(&worker));
    assert_eq!(l.held_result_bytes(), 4);
    l.record(
        &effect,
        Event::PromiseResolved {
            actual_reply: "abcd",
        },
    )
    .unwrap();
    l.record(
        &effect,
        Event::Publication(PublicationDisposition::Forwarded),
    )
    .unwrap();
    l.record(
        &effect,
        Event::ResultRetired(ResultRetirement::DeliveredToPort),
    )
    .unwrap();
    assert_eq!(l.observer_bytes(), 8);
    assert_eq!(l.held_result_bytes(), 0);
    assert_eq!(l.produced_result_bytes(), 4);
    l.finish().unwrap();
    let other = reference("B", Kind::Inspection, 0);
    promise(&mut l, &other);
    assert_eq!(
        l.record(
            &other,
            Event::WorkStarted {
                work: &work,
                owner: WorkOwner::Inline
            }
        ),
        Err(EffectLedgerError::Work)
    );
}

#[test]
fn late_file_read_requires_an_actual_resolved_read_of_the_same_attempt() {
    let picker = reference("A", Kind::Picker, 0);
    let read = reference("A", Kind::FileRead, 0);
    let foreign = reference("B", Kind::FileRead, 0);
    let mut l = ledger();
    l.record(&picker, Event::Pending(EffectPort::PickerReceiveCallback))
        .unwrap();
    l.record(
        &picker,
        Event::CallbackRetired {
            action_index: 0,
            cause: CancellationCause::Teardown,
        },
    )
    .unwrap();
    promise(&mut l, &read);
    promise(&mut l, &foreign);
    l.record(
        &foreign,
        Event::PromiseResolved {
            actual_reply: "other file",
        },
    )
    .unwrap();
    for source in [&read, &foreign] {
        assert_eq!(
            l.record(
                &picker,
                Event::LateSignal {
                    actual_signal: "read finished",
                    disposition: LateDisposition::RetiredCallback,
                    source: LateSignalSource::FileReadCompletion(source)
                }
            ),
            Err(EffectLedgerError::LateSignal)
        );
    }
    l.record(
        &read,
        Event::PromiseResolved {
            actual_reply: "A file",
        },
    )
    .unwrap();
    l.record(
        &picker,
        Event::LateSignal {
            actual_signal: "read finished",
            disposition: LateDisposition::RetiredCallback,
            source: LateSignalSource::FileReadCompletion(&read),
        },
    )
    .unwrap();
    l.finish().unwrap();
}

#[test]
fn complete_event_and_port_history_have_inclusive_independent_bounds() {
    let effect = reference("A", Kind::Digest, 0);
    let other = reference("B", Kind::Digest, 0);
    let mut l = EffectLedger::new(EffectLedgerLimits::new(1, 2, 0, 0, 0).unwrap());
    promise(&mut l, &effect);
    assert!(matches!(
        l.record(&other, Event::Pending(EffectPort::Promise)),
        Err(EffectLedgerError::Resource(_))
    ));
    assert_eq!(l.port_count(), 1);
    assert_eq!(l.event_count(), 1);
    l.record(&effect, Event::PromiseRejected).unwrap();
    l.finish().unwrap();
    assert!(matches!(
        l.record(
            &effect,
            Event::CancellationRequested {
                action_index: 0,
                cause: CancellationCause::Teardown
            }
        ),
        Err(EffectLedgerError::Resource(_))
    ));
    assert_eq!(l.event_count(), 2);
}

#[test]
fn no_byte_credit_is_an_explicit_refusal_without_record_or_capacity_changes() {
    let work = FixtureAlias::new("work").unwrap();
    let effect = reference("A", Kind::Inspection, 0);
    let mut l = EffectLedger::new(EffectLedgerLimits::new(1, 8, 0, 0, 0).unwrap());
    promise(&mut l, &effect);
    l.record(
        &effect,
        Event::WorkStarted {
            work: &work,
            owner: WorkOwner::Inline,
        },
    )
    .unwrap();
    assert!(matches!(
        l.record(
            &effect,
            Event::ResultPrepared {
                work: &work,
                raw_reply: "actual"
            }
        ),
        Err(EffectLedgerError::Resource(_))
    ));
    assert_eq!(l.held_result_bytes(), 0);
    assert_eq!(l.produced_result_bytes(), 0);
    assert_eq!(l.observer_bytes(), 0);
    assert_eq!(l.event_count(), 2);
    assert!(EffectLedgerLimits::new(0, 8, 0, 0, 0).is_err());
    assert!(EffectLedgerLimits::new(1, usize::MAX, 0, 0, 0).is_err());
    assert!(EffectLedgerLimits::new(1, 8, usize::MAX, 0, 0).is_err());
}

#[test]
fn terminal_picker_input_can_start_a_new_read_without_reopening_receive() {
    for consumed in [false, true] {
        let mut l = ledger();
        let picker = reference("A", Kind::Picker, 0);
        let read = reference("A", Kind::FileRead, 0);
        l.record(&picker, Event::Pending(EffectPort::PickerReceiveCallback))
            .unwrap();
        if consumed {
            l.record(&picker, Event::CallbackDelivered).unwrap();
        } else {
            l.record(
                &picker,
                Event::CallbackRetired {
                    action_index: 0,
                    cause: CancellationCause::CloseCurrentModel,
                },
            )
            .unwrap();
        }
        l.record(&picker, Event::PickerInput(PickerSignal::FileSelection))
            .unwrap();
        promise(&mut l, &read);
        l.record(
            &read,
            Event::PromiseResolved {
                actual_reply: "actual read",
            },
        )
        .unwrap();
        l.record(
            &picker,
            Event::LateSignal {
                actual_signal: "actual selected result",
                disposition: if consumed {
                    LateDisposition::ConsumedCallback
                } else {
                    LateDisposition::RetiredCallback
                },
                source: LateSignalSource::FileReadCompletion(&read),
            },
        )
        .unwrap();
        assert_eq!(
            l.record(&picker, Event::CallbackDelivered),
            Err(EffectLedgerError::Settlement)
        );
        l.finish().unwrap();
    }
}

#[test]
fn an_actual_rejected_read_can_finish_as_an_ignored_unreadable_result() {
    let mut l = ledger();
    let picker = reference("A", Kind::Picker, 0);
    let read = reference("A", Kind::FileRead, 0);
    l.record(&picker, Event::Pending(EffectPort::PickerReceiveCallback))
        .unwrap();
    l.record(&picker, Event::PickerInput(PickerSignal::FileSelection))
        .unwrap();
    promise(&mut l, &read);
    l.record(
        &picker,
        Event::CallbackRetired {
            action_index: 0,
            cause: CancellationCause::CloseCurrentModel,
        },
    )
    .unwrap();
    l.record(&read, Event::PromiseRejected).unwrap();
    l.record(
        &picker,
        Event::LateSignal {
            actual_signal: "{\"kind\":\"refused\",\"reason\":\"unreadable\"}",
            disposition: LateDisposition::RetiredCallback,
            source: LateSignalSource::FileReadCompletion(&read),
        },
    )
    .unwrap();
    l.finish().unwrap();
}

#[test]
fn started_work_cannot_resolve_before_its_actual_result_exists() {
    let work = FixtureAlias::new("actual-core").unwrap();
    let effect = reference("A", Kind::Inspection, 0);
    let mut l = EffectLedger::new(EffectLedgerLimits::new(4, 32, 16, 16, 32).unwrap());
    promise(&mut l, &effect);
    l.record(
        &effect,
        Event::WorkStarted {
            work: &work,
            owner: WorkOwner::Inline,
        },
    )
    .unwrap();
    assert!(
        l.record(
            &effect,
            Event::PromiseResolved {
                actual_reply: "forged success"
            }
        )
        .is_err()
    );
    assert_eq!(l.observer_bytes(), 0);
    l.record(
        &effect,
        Event::ResultPrepared {
            work: &work,
            raw_reply: "genuine result",
        },
    )
    .unwrap();
    l.record(
        &effect,
        Event::PromiseResolved {
            actual_reply: "genuine result",
        },
    )
    .unwrap();
    l.record(
        &effect,
        Event::ResultRetired(ResultRetirement::DeliveredToPort),
    )
    .unwrap();
    assert_eq!(l.finish(), Err(EffectLedgerError::RunningWork));
    l.record(&effect, Event::WorkExited { work: &work })
        .unwrap();
    l.finish().unwrap();
}

#[test]
fn direct_late_picker_causes_do_not_require_a_fabricated_file_read() {
    for consumed in [false, true] {
        for (signal, source) in [
            (PickerSignal::CancelEvent, LateSignalSource::CancelEvent),
            (
                PickerSignal::EmptySelection,
                LateSignalSource::EmptySelectionEvent,
            ),
            (
                PickerSignal::FileSelection,
                LateSignalSource::SelectionValidation(SelectionRefusal::InvalidName),
            ),
            (
                PickerSignal::FileSelection,
                LateSignalSource::SelectionValidation(SelectionRefusal::UnsupportedCodec),
            ),
            (
                PickerSignal::FileSelection,
                LateSignalSource::SelectionValidation(SelectionRefusal::Oversized),
            ),
        ] {
            let mut l = ledger();
            let picker = reference("A", Kind::Picker, 0);
            l.record(&picker, Event::Pending(EffectPort::PickerReceiveCallback))
                .unwrap();
            if consumed {
                l.record(&picker, Event::CallbackDelivered).unwrap();
            } else {
                l.record(
                    &picker,
                    Event::CallbackRetired {
                        action_index: 0,
                        cause: CancellationCause::Replacement,
                    },
                )
                .unwrap();
            }
            l.record(&picker, Event::PickerInput(signal)).unwrap();
            l.record(
                &picker,
                Event::LateSignal {
                    actual_signal: "actual ignored callback argument",
                    disposition: if consumed {
                        LateDisposition::ConsumedCallback
                    } else {
                        LateDisposition::RetiredCallback
                    },
                    source,
                },
            )
            .unwrap();
            assert_eq!(l.port_count(), 1);
            assert_eq!(
                l.record(&picker, Event::CallbackDelivered),
                Err(EffectLedgerError::Settlement)
            );
            l.finish().unwrap();
        }
    }
}
