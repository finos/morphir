//! Independent lifecycle-v2 contract eada8d9f, before ledger implementation.
//! These checks validate evidence consistency, not actual production execution.
use morphir_mck::workbench::model_originals::{
    CancellationCause, EffectEvent as Event, EffectKind as Kind, EffectLedger, EffectLedgerError,
    EffectLedgerLimits, EffectPort, EffectRef, FixtureAlias, LateDisposition, LateSignalSource,
    PickerSignal, PublicationDisposition, ResultRetirement, WorkOwner,
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
                source: LateSignalSource::InputEvent
            }
        ),
        Err(EffectLedgerError::LateSignal)
    );
    l.record(
        &picker,
        Event::LateSignal {
            actual_signal: "later input",
            disposition: LateDisposition::ConsumedCallback,
            source: LateSignalSource::InputEvent,
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
