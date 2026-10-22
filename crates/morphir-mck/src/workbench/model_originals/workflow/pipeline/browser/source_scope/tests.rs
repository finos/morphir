//! Actual lifetime/owner bookkeeping only; no effect or physical join evidence.
use super::*;
use crate::{
    json::strict::Document,
    workbench::{
        configuration::InstalledObservationLimits,
        model_originals::workflow::pipeline::{
            installed::observation::InstalledObservationOwner,
            policy::{Owners, Policy},
        },
    },
};
const CHECKER: &str = include_str!(concat!(
    env!("CARGO_MANIFEST_DIR"),
    "/src/workbench/model_originals/workflow/pipeline_controls/explicit-test-policy.json"
));

#[test]
fn browser_invocation_scope_09_retirement_refusal_keeps_actual_issued_binding() {
    let (mut owners, mut receiving) = owners(8192, 100, 8192);
    let mut loans = BrowserOwnerLoans::new(&mut owners, &mut receiving);
    let source = BrowserSourceScope::prepare(&mut loans).unwrap();
    let child = source.prepare_invocation(&mut loans).unwrap();
    let mut binding = child.bind(&mut loans).unwrap();
    // Exercise the existing private count-integrity failure after real issuance.
    // No production constructor or caller count setter is introduced.
    *source.control.lock() = State::Active { bindings: 0 };
    *child.control.inner.lock() = State::Active { bindings: 0 };
    assert_eq!(
        binding.retire_after_join_in_place(),
        Err(ScopeFault::SizeOverflow)
    );
    assert_eq!(binding.while_active(|| ()), Err(ScopeFault::SizeOverflow));
    // Restore only the fixture's corrupted counts to consume its actual owner.
    for control in [source.control.as_ref(), &child.control.inner] {
        match &mut *control.lock() {
            State::Active { bindings } | State::Revoked { bindings, .. } => *bindings = 1,
        }
    }
    assert_eq!(binding.retire_after_join_in_place(), Ok(()));
    assert_eq!(
        source.terminal(),
        ScopeTerminal::Incomplete {
            first: ScopeFault::SizeOverflow,
            bindings: 0
        }
    );
    assert_eq!(
        child.terminal(),
        ScopeTerminal::Incomplete {
            first: ScopeFault::SizeOverflow,
            bindings: 0
        }
    );
}

// Same actual policy/decoder/receiving fixture as funded_workflow::tests.
fn owners(retained: usize, slots: usize, visits: usize) -> (Owners, InstalledObservationOwner) {
    let mut checker: serde_json::Value = serde_json::from_str(CHECKER).unwrap();
    checker["decode"]["slots"] = slots.into();
    let owners = Policy::from_document(
        &Document::parse_unsigned_counts(checker.to_string().as_bytes()).unwrap(),
    )
    .unwrap()
    .owners();
    let counts = format!(
        r#"{{"rpcFrames":"checker-capture","retainedBytes":{retained},"stdoutPrefixBytes":1000,"stderrPrefixBytes":1000,"snapshotReadBytes":0,"byteVisits":{visits},"records":0}}"#
    );
    let receiving = InstalledObservationOwner::new(
        &InstalledObservationLimits::from_document(
            &Document::parse_unsigned_counts(counts.as_bytes()).unwrap(),
        )
        .unwrap(),
    );
    (owners, receiving)
}

#[test]
fn browser_invocation_scope_01_callback_return_refuses_earlier_child_without_revoking_application()
{
    let (mut owners, mut receiving) = owners(8192, 100, 8192);
    let mut loans = BrowserOwnerLoans::new(&mut owners, &mut receiving);
    let source = BrowserSourceScope::prepare(&mut loans).unwrap();
    let application = source.application_identity().unwrap();
    let ((first_binding, first_identity), terminal) = source
        .with_invocation(&mut loans, |child, loans| {
            let identity = child.identity(loans).unwrap();
            let binding = child.bind(loans).unwrap();
            assert_eq!(identity.validate(child), Ok(()));
            assert_eq!(binding.validate_invocation(&identity), Ok(()));
            assert_eq!(
                binding.validate_scope(&source),
                Err(ScopeFault::ForeignSource)
            );
            assert_eq!(binding.while_active(|| 17), Ok(17));
            (binding, identity)
        })
        .unwrap();
    assert_eq!(terminal, ScopeTerminal::Unfinished { bindings: 1 });
    assert_eq!(first_binding.while_active(|| ()), Err(ScopeFault::Revoked));
    assert_eq!(first_identity.while_active(|| ()), Err(ScopeFault::Revoked));
    assert_eq!(application.validate(&source), Ok(()));
    let second = source.prepare_invocation(&mut loans).unwrap();
    let second_identity = second.identity(&mut loans).unwrap();
    let second_binding = second.bind(&mut loans).unwrap();
    assert_eq!(
        first_identity.validate(&second),
        Err(ScopeFault::ForeignSource)
    );
    assert_eq!(
        second_binding.validate_invocation(&first_identity),
        Err(ScopeFault::ForeignSource)
    );
    assert_eq!(
        first_binding.validate_invocation(&second_identity),
        Err(ScopeFault::ForeignSource)
    );
    assert_eq!(second_binding.validate_invocation(&second_identity), Ok(()));
    first_binding.retire_after_join().unwrap();
    assert_eq!(source.terminal(), ScopeTerminal::Unfinished { bindings: 1 });
    second_binding.retire_after_join().unwrap();
    drop(second);
    assert_eq!(source.terminal(), ScopeTerminal::Quiescent);
    assert_eq!(application.validate(&source), Ok(()));
}

#[test]
fn browser_invocation_scope_02_parent_revoke_refuses_child_and_retirement_settles_both_counts() {
    let (mut owners, mut receiving) = owners(8192, 100, 8192);
    let mut loans = BrowserOwnerLoans::new(&mut owners, &mut receiving);
    let mut source = BrowserSourceScope::prepare(&mut loans).unwrap();
    let mut child = source.prepare_invocation(&mut loans).unwrap();
    let identity = child.identity(&mut loans).unwrap();
    let binding = child.bind(&mut loans).unwrap();
    assert_eq!(source.revoke(), ScopeTerminal::Unfinished { bindings: 1 });
    assert_eq!(binding.while_active(|| ()), Err(ScopeFault::Revoked));
    assert_eq!(identity.while_active(|| ()), Err(ScopeFault::Revoked));
    assert_eq!(child.revoke(), ScopeTerminal::Unfinished { bindings: 1 });
    binding.retire_after_join().unwrap();
    assert_eq!(child.terminal(), ScopeTerminal::Quiescent);
    assert_eq!(source.terminal(), ScopeTerminal::Quiescent);
}

#[test]
fn browser_invocation_scope_03_unsettled_binding_drop_preserves_global_abandoned_debt() {
    let (mut owners, mut receiving) = owners(8192, 100, 8192);
    let mut loans = BrowserOwnerLoans::new(&mut owners, &mut receiving);
    let source = BrowserSourceScope::prepare(&mut loans).unwrap();
    let child = source.prepare_invocation(&mut loans).unwrap();
    let binding = child.bind(&mut loans).unwrap();
    drop(binding);
    let expected = ScopeTerminal::Incomplete {
        first: ScopeFault::Abandoned,
        bindings: 1,
    };
    assert_eq!(child.terminal(), expected);
    assert_eq!(source.terminal(), expected);
    assert!(matches!(
        source.prepare_invocation(&mut loans),
        Err(ScopeIssueFault::Scope(ScopeFault::Abandoned))
    ));
    drop(child);
    assert_eq!(source.terminal(), expected);
}

fn global_bytes() -> usize {
    arc_backing_layout::<Control>().unwrap().size() + std::mem::size_of::<BrowserSourceScope>()
}
fn child_bytes() -> usize {
    arc_backing_layout::<InvocationControl>().unwrap().size()
        + std::mem::size_of::<BrowserInvocationScope>()
}

#[test]
fn browser_invocation_scope_04_zero_one_short_storage_slots_and_initialization_refuse_before_owner()
{
    for (retained, slots, visits) in [
        (global_bytes(), 100, 8192),
        (global_bytes() + child_bytes() - 1, 100, 8192),
        (8192, 2, 8192), // Global takes1; child needs2 actual owner/control slots.
        (8192, 100, 0),
        (
            8192,
            100,
            child_bytes() + std::mem::size_of::<AtomicUsize>() - 1,
        ),
    ] {
        let (mut owners, mut receiving) = owners(retained, slots, visits);
        let mut loans = BrowserOwnerLoans::new(&mut owners, &mut receiving);
        let source = BrowserSourceScope::prepare(&mut loans).unwrap();
        let before = Arc::strong_count(&source.control);
        assert!(matches!(
            source.prepare_invocation(&mut loans),
            Err(ScopeIssueFault::Input(_))
        ));
        assert_eq!(Arc::strong_count(&source.control), before);
        assert_eq!(source.terminal(), ScopeTerminal::Quiescent);
    }
}

#[test]
fn browser_invocation_scope_05_identity_funding_precedes_downgrade_and_prior_fault_dominates_retry()
{
    let retained =
        global_bytes() + child_bytes() + std::mem::size_of::<BrowserInvocationIdentity>() - 1;
    let (mut owners, mut receiving) = owners(retained, 100, 8192);
    let mut source;
    let child;
    {
        let mut loans = BrowserOwnerLoans::new(&mut owners, &mut receiving);
        source = BrowserSourceScope::prepare(&mut loans).unwrap();
        child = source.prepare_invocation(&mut loans).unwrap();
        assert_eq!(Arc::weak_count(&source.control), 0);
        assert_eq!(Arc::weak_count(&child.control), 0);
        assert!(matches!(
            child.identity(&mut loans),
            Err(ScopeIssueFault::Input(BrowserInputFault::Receiving(_)))
        ));
        assert_eq!(Arc::weak_count(&source.control), 0);
        assert_eq!(Arc::weak_count(&child.control), 0);
    }
    let used = (owners.decode.usage(), receiving.usage());
    source.revoke();
    let mut loans = BrowserOwnerLoans::new(&mut owners, &mut receiving);
    assert!(matches!(
        child.identity(&mut loans),
        Err(ScopeIssueFault::Input(BrowserInputFault::Receiving(_)))
    ));
    assert!(matches!(
        source.prepare_invocation(&mut loans),
        Err(ScopeIssueFault::Input(BrowserInputFault::Receiving(_)))
    ));
    drop(loans);
    assert_eq!((owners.decode.usage(), receiving.usage()), used);
}

#[test]
fn browser_invocation_scope_06_child_guard_drop_and_panic_revoke_without_poisoning_parent() {
    let (mut owners, mut receiving) = owners(8192, 100, 8192);
    let mut loans = BrowserOwnerLoans::new(&mut owners, &mut receiving);
    let source = BrowserSourceScope::prepare(&mut loans).unwrap();
    let child = source.prepare_invocation(&mut loans).unwrap();
    let binding = child.bind(&mut loans).unwrap();
    drop(child);
    assert_eq!(binding.while_active(|| ()), Err(ScopeFault::Revoked));
    assert_eq!(source.ready(), Ok(()));
    binding.retire_after_join().unwrap();
    let mut escaped = None;
    let panic = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        let _ = source.with_invocation(&mut loans, |child, loans| {
            escaped = Some(child.bind(loans).unwrap());
            panic!("actual callback unwind control");
        });
    }));
    assert!(panic.is_err());
    let binding = escaped.unwrap();
    assert_eq!(binding.while_active(|| ()), Err(ScopeFault::Revoked));
    assert_eq!(source.ready(), Ok(()));
    binding.retire_after_join().unwrap();
    assert_eq!(source.terminal(), ScopeTerminal::Quiescent);
}

#[test]
fn browser_invocation_scope_07_foreign_parent_and_global_binding_cannot_be_promoted() {
    let (mut owners, mut receiving) = owners(8192, 100, 8192);
    let mut loans = BrowserOwnerLoans::new(&mut owners, &mut receiving);
    let source = BrowserSourceScope::prepare(&mut loans).unwrap();
    let other = BrowserSourceScope::prepare(&mut loans).unwrap();
    let child = source.prepare_invocation(&mut loans).unwrap();
    let foreign = other.prepare_invocation(&mut loans).unwrap();
    let identity = child.identity(&mut loans).unwrap();
    assert_eq!(identity.validate(&foreign), Err(ScopeFault::ForeignSource));
    let global = source.bind(&mut loans).unwrap();
    assert_eq!(global.validate_scope(&source), Ok(()));
    assert_eq!(
        global.validate_invocation(&identity),
        Err(ScopeFault::ForeignSource)
    );
    global.retire_after_join().unwrap();
}

#[test]
fn browser_invocation_scope_08_counter_overflow_refuses_before_either_debt_changes() {
    let (mut owners, mut receiving) = owners(8192, 100, 8192);
    let mut loans = BrowserOwnerLoans::new(&mut owners, &mut receiving);
    let source = BrowserSourceScope::prepare(&mut loans).unwrap();
    let child = source.prepare_invocation(&mut loans).unwrap();
    // Boundary fixture for the real checked bookkeeping path; this synthetic
    // count is not evidence that physical owners were created or joined.
    *child.control.inner.lock() = State::Active {
        bindings: usize::MAX,
    };
    assert!(matches!(
        child.bind(&mut loans),
        Err(ScopeIssueFault::Scope(ScopeFault::SizeOverflow))
    ));
    assert_eq!(
        source.terminal(),
        ScopeTerminal::Incomplete {
            first: ScopeFault::SizeOverflow,
            bindings: 0,
        }
    );
    assert_eq!(
        child.terminal(),
        ScopeTerminal::Incomplete {
            first: ScopeFault::SizeOverflow,
            bindings: usize::MAX,
        }
    );
}

#[test]
fn browser_invocation_scope_09_capture_holds_same_parent_child_until_revocation() {
    let (mut owners, mut receiving) = owners(8192, 100, 8192);
    let mut loans = BrowserOwnerLoans::new(&mut owners, &mut receiving);
    let source = BrowserSourceScope::prepare(&mut loans).unwrap();
    let mut child = source.prepare_invocation(&mut loans).unwrap();
    let probe = child.identity(&mut loans).unwrap();
    let inspect = child.identity(&mut loans).unwrap();
    let barrier = std::sync::Barrier::new(2);
    std::thread::scope(|threads| {
        let barrier = &barrier;
        let (started, started_rx) = std::sync::mpsc::channel();
        let (finished, finished_rx) = std::sync::mpsc::channel();
        let worker = threads.spawn(move || {
            barrier.wait();
            started.send(()).unwrap();
            finished.send(probe.while_active(|| 17)).unwrap();
        });
        let (captured, terminal) = child.revoke_with_capture(|| {
            // Inspect actual issued controls, never call a nested source gate.
            assert!(matches!(
                source.control.state.try_lock(),
                Err(std::sync::TryLockError::WouldBlock)
            ));
            let actual_child = inspect.child.upgrade().unwrap();
            assert!(matches!(
                actual_child.inner.state.try_lock(),
                Err(std::sync::TryLockError::WouldBlock)
            ));
            barrier.wait();
            started_rx.recv().unwrap();
            assert!(matches!(
                finished_rx.try_recv(),
                Err(std::sync::mpsc::TryRecvError::Empty)
            ));
            71
        });
        assert_eq!(captured, 71);
        assert_eq!(terminal, ScopeTerminal::Quiescent);
        assert_eq!(finished_rx.recv().unwrap(), Err(ScopeFault::Revoked));
        worker.join().unwrap();
    });
    assert_eq!(inspect.while_active(|| ()), Err(ScopeFault::Revoked));
    assert_eq!(source.ready(), Ok(()));
}

#[test]
fn browser_invocation_scope_10_capture_panic_revokes_without_losing_original_payload() {
    let (mut owners, mut receiving) = owners(8192, 100, 8192);
    let mut loans = BrowserOwnerLoans::new(&mut owners, &mut receiving);
    let source = BrowserSourceScope::prepare(&mut loans).unwrap();
    let mut child = source.prepare_invocation(&mut loans).unwrap();
    let identity = child.identity(&mut loans).unwrap();
    let original = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        child.revoke_with_capture(|| std::panic::panic_any(619_u32))
    }))
    .unwrap_err();
    assert_eq!(original.downcast_ref::<u32>(), Some(&619));
    assert_eq!(identity.while_active(|| ()), Err(ScopeFault::Revoked));
    assert_eq!(child.terminal(), ScopeTerminal::Quiescent);
    assert_eq!(source.ready(), Ok(()));
}
