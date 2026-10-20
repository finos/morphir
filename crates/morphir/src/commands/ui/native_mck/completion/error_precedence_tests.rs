//! Pure first-fault controls. These do not prove real worker/socket cleanup.
use super::{NativeAdapterError, reconcile_completion};

#[test]
fn action_exchange_failure_precedes_later_cleanup_failure() {
    assert_eq!(
        reconcile_completion::<()>(
            Err(NativeAdapterError::Exchange),
            Err(NativeAdapterError::Cleanup)
        ),
        Err(NativeAdapterError::Exchange),
    );
}

#[test]
fn action_cancellation_precedes_later_cleanup_failure_without_claiming_cleanup() {
    assert_eq!(
        reconcile_completion::<()>(
            Err(NativeAdapterError::Cancelled),
            Err(NativeAdapterError::Cleanup)
        ),
        Err(NativeAdapterError::Cancelled),
    );
}

#[test]
fn cleanup_failure_refuses_an_otherwise_successful_action() {
    assert_eq!(
        reconcile_completion(Ok(7), Err(NativeAdapterError::Cleanup)),
        Err(NativeAdapterError::Cleanup),
    );
}

#[test]
fn successful_action_requires_successful_cleanup() {
    assert_eq!(reconcile_completion(Ok(7), Ok(())), Ok(7));
}
