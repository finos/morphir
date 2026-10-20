//! Source-first controls for the actual fixed host cleanup backing allocation.
//! Child of lifecycle::cleanup; no worker/source events or allocator injection.
use super::*;

fn required_registry_bytes() -> usize {
    std::mem::size_of::<Mutex<CleanupEntries>>()
        .checked_add(2 * std::mem::size_of::<usize>())
        .unwrap()
}

#[test]
fn cleanup_registry_zero_metadata_refuses_without_retained_credit() {
    let capacity = HostModelCaptureCapacity::with_metadata_limit(0);
    assert!(matches!(
        CleanupRegistry::new(&capacity),
        Err(CaptureError::Capacity)
    ));
    assert_eq!(capacity.usage(), ModelCaptureUsage::default());
}

#[test]
fn cleanup_registry_exact_credit_follows_same_table_through_last_pending_owner() {
    let required = required_registry_bytes();
    assert!(required > 0);
    let capacity = HostModelCaptureCapacity::with_metadata_limit(required);
    let registry = CleanupRegistry::new(&capacity).unwrap();
    let cloned = registry.clone();
    let owner = registry.control();
    assert_eq!(registry.retained_metadata_bytes(), required);
    assert_eq!(owner.retained_metadata_bytes(), required);
    let pending = owner.into_pending();
    assert_eq!(pending.retained_metadata_bytes(), required);
    drop(registry);
    assert_eq!(capacity.usage().metadata_bytes(), required);
    drop(cloned);
    assert_eq!(capacity.usage().metadata_bytes(), required);
    assert_eq!(capacity.usage().source_bytes(), 0);
    assert_eq!(capacity.usage().captures(), 0);
    assert_eq!(capacity.usage().active_workers(), 0);
    assert_eq!(pending.retained_handles(), 0);
    drop(pending);
    assert_eq!(capacity.usage(), ModelCaptureUsage::default());
}

#[test]
fn cleanup_registry_one_byte_short_refuses_and_returns_all_credit() {
    let required = required_registry_bytes();
    let capacity = HostModelCaptureCapacity::with_metadata_limit(required - 1);
    assert!(matches!(
        CleanupRegistry::new(&capacity),
        Err(CaptureError::Capacity)
    ));
    assert_eq!(capacity.usage(), ModelCaptureUsage::default());
}

#[test]
fn cleanup_registry_uses_same_cumulative_host_metadata_ledger() {
    let required = required_registry_bytes();
    let capacity =
        HostModelCaptureCapacity::with_metadata_limit(required.checked_mul(2).unwrap() - 1);
    let first = CleanupRegistry::new(&capacity).unwrap();
    assert!(matches!(
        CleanupRegistry::new(&capacity),
        Err(CaptureError::Capacity)
    ));
    assert_eq!(first.retained_metadata_bytes(), required);
    assert_eq!(capacity.usage().metadata_bytes(), required);
    drop(first);
    assert_eq!(capacity.usage(), ModelCaptureUsage::default());
}
