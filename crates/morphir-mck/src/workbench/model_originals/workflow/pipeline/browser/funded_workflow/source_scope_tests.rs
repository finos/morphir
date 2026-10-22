//! Scope bookkeeping controls only. A retired binding is not physical join
//! evidence; the real host caller must retain and join its actual owners.
use super::{BrowserOwnerLoans, owners};
use crate::workbench::model_originals::workflow::pipeline::browser::{
    inputs::BrowserInputFault,
    source_scope::{BrowserSourceScope, ScopeFault, ScopeIssueFault, ScopeTerminal},
};

#[test]
fn browser_scope_01_zero_storage_refuses_before_control_allocation_and_retry_spend() {
    let (mut owner, mut receiving) = owners(0, 100, 1000);
    let mut loans = BrowserOwnerLoans::new(&mut owner, &mut receiving);
    assert!(matches!(
        BrowserSourceScope::prepare(&mut loans),
        Err(BrowserInputFault::Receiving(_))
    ));
    drop(loans);
    let used = (owner.decode.usage(), receiving.usage());
    assert!(
        BrowserSourceScope::prepare(&mut BrowserOwnerLoans::new(&mut owner, &mut receiving))
            .is_err()
    );
    assert_eq!((owner.decode.usage(), receiving.usage()), used);
}

#[test]
fn browser_scope_02_revocation_blocks_later_effect_and_preserves_outstanding_binding() {
    let (mut owner, mut receiving) = owners(4096, 100, 1000);
    let mut loans = BrowserOwnerLoans::new(&mut owner, &mut receiving);
    let mut scope = BrowserSourceScope::prepare(&mut loans).unwrap();
    let binding = scope.bind(&mut loans).unwrap();
    let identity = binding.identity();
    assert_eq!(binding.while_active(|| 7), Ok(7));
    assert_eq!(scope.revoke(), ScopeTerminal::Unfinished { bindings: 1 });
    let mut called = false;
    assert_eq!(
        binding.while_active(|| called = true),
        Err(ScopeFault::Revoked)
    );
    assert!(!called);
    assert_eq!(binding.identity(), identity);
    binding.retire_after_join().unwrap();
    assert_eq!(scope.terminal(), ScopeTerminal::Quiescent);
}

#[test]
fn browser_scope_03_unresolved_drop_does_not_retire_debt_or_restore_admission() {
    let (mut owner, mut receiving) = owners(4096, 100, 1000);
    let mut loans = BrowserOwnerLoans::new(&mut owner, &mut receiving);
    let mut scope = BrowserSourceScope::prepare(&mut loans).unwrap();
    let binding = scope.bind(&mut loans).unwrap();
    drop(binding);
    assert_eq!(
        scope.terminal(),
        ScopeTerminal::Incomplete {
            first: ScopeFault::Abandoned,
            bindings: 1
        }
    );
    assert!(matches!(
        scope.bind(&mut loans),
        Err(ScopeIssueFault::Scope(ScopeFault::Abandoned))
    ));
    assert_eq!(
        scope.revoke(),
        ScopeTerminal::Incomplete {
            first: ScopeFault::Abandoned,
            bindings: 1
        }
    );
}

#[test]
fn browser_scope_04_foreign_scope_refuses_without_retiring_original_binding() {
    let (mut owner, mut receiving) = owners(8192, 100, 1000);
    let mut loans = BrowserOwnerLoans::new(&mut owner, &mut receiving);
    let mut first = BrowserSourceScope::prepare(&mut loans).unwrap();
    let second = BrowserSourceScope::prepare(&mut loans).unwrap();
    let binding = first.bind(&mut loans).unwrap();
    assert_eq!(
        binding.validate_scope(&second),
        Err(ScopeFault::ForeignSource)
    );
    assert_eq!(binding.validate_scope(&first), Ok(()));
    assert_eq!(first.revoke(), ScopeTerminal::Unfinished { bindings: 1 });
    binding.retire_after_join().unwrap();
    assert_eq!(first.terminal(), ScopeTerminal::Quiescent);
}
