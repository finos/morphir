//! Pure unit metadata arithmetic only. No giant Vec, allocation or host proof.
use super::{PrivateRecordError, record_retention::checked_reservation};
#[test]
fn receiver_cumulative_u64_arithmetic_is_checked_before_any_permission() {
    assert_eq!(
        checked_reservation(u64::MAX - 237, 237, u64::MAX),
        Ok(u64::MAX)
    );
    assert!(matches!(
        checked_reservation(u64::MAX - 236, 237, u64::MAX),
        Err(PrivateRecordError::SizeOverflow)
    ));
    assert!(matches!(
        checked_reservation(237, 237, 473),
        Err(PrivateRecordError::Capacity {
            limit: 473,
            used: 237,
            requested: 237
        })
    ));
    assert_eq!(checked_reservation(0, 0, 0), Ok(0));
}
