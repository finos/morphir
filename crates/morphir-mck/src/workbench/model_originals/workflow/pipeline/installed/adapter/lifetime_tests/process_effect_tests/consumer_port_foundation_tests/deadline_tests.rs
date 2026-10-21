//! Pure prospective arithmetic controls. No OS sample, Node probe or I/O claim.
//! Child of consumer_port_foundation_tests, reusing only its Instant/Duration.
use super::*;
use crate::workbench::model_originals::workflow::pipeline::installed::adapter::processes::consumer::deadline::{
    DeadlineError, Timebase, export,
};

#[test]
fn bracket_uses_same_original_end_and_later_rust_sample_conservatively() {
    let base = Instant::now();
    let before = base;
    let after = base + Duration::from_nanos(20);
    let end = base + Duration::from_nanos(100);
    let ratio = Timebase::new(125, 3).unwrap();
    let result = export(end, before, 12, after, ratio).unwrap();
    // floor(12*125/3)=500; SAME end minus after=80; ceil tick=42.
    assert_eq!(result.calibrated_at_ns(), 500u64);
    assert_eq!(result.end_ns(), 538u64);
    assert_eq!(result.timebase().numerator(), 125u32);
    assert_eq!(result.timebase().denominator(), 3u32);
    // Moving only the earlier bracket endpoint cannot grant more time.
    let tighter = export(end, before + Duration::from_nanos(1), 12, after, ratio).unwrap();
    assert_eq!(tighter.calibrated_at_ns(), result.calibrated_at_ns());
    assert_eq!(tighter.end_ns(), result.end_ns());
}

#[test]
fn reversed_bracket_expired_end_and_too_short_guard_refuse() {
    let base = Instant::now();
    let ratio = Timebase::new(125, 3).unwrap();
    let cases = [
        (
            base + Duration::from_nanos(100),
            base + Duration::from_nanos(1),
            base,
            DeadlineError::BracketReversed,
        ),
        (base, base, base, DeadlineError::Expired),
        (
            base,
            base,
            base + Duration::from_nanos(1),
            DeadlineError::Expired,
        ),
        (
            base + Duration::from_nanos(42),
            base,
            base,
            DeadlineError::InsufficientRemaining,
        ),
    ];
    for (end, before, after, expected) in cases {
        assert!(matches!(export(end,before,12,after,ratio), Err(actual) if actual == expected));
    }
    let shortest = export(base + Duration::from_nanos(43), base, 12, base, ratio).unwrap();
    assert_eq!(shortest.end_ns(), 501u64);
}

#[test]
fn timebase_requires_both_nonzero_and_guard_is_checked_integer_ceil() {
    for (numerator, denominator) in [(0, 0), (0, 3), (125, 0)] {
        assert!(matches!(
            Timebase::new(numerator, denominator),
            Err(DeadlineError::InvalidTimebase)
        ));
    }
    for (numerator, denominator, expected) in [
        (125, 3, 42u64),
        (1, 3, 1),
        (1, 1, 1),
        (u32::MAX, 1, u32::MAX as u64),
        (u32::MAX, u32::MAX, 1),
    ] {
        assert_eq!(
            Timebase::new(numerator, denominator)
                .unwrap()
                .tick_guard_ns(),
            expected
        );
    }
}

#[test]
fn uv_intermediate_product_overflow_refuses_even_when_final_ns_would_fit() {
    let base = Instant::now();
    let ratio = Timebase::new(125, 3).unwrap();
    let last_safe_tick = u64::MAX / 125;
    assert_eq!(last_safe_tick, 147_573_952_589_676_412u64);
    let overflowing_tick = last_safe_tick + 1;
    let mathematical_ns = u128::from(overflowing_tick) * 125 / 3;
    assert!(mathematical_ns <= u128::from(u64::MAX));
    assert!(matches!(
        export(
            base + Duration::from_nanos(100),
            base,
            overflowing_tick,
            base,
            ratio
        ),
        Err(DeadlineError::TickProductOverflow)
    ));
}

#[test]
fn exported_horizon_stays_in_uv_product_range_and_addition_never_wraps() {
    let base = Instant::now();
    let end = base + Duration::from_nanos(100);
    let ratio = Timebase::new(125, 3).unwrap();
    // Product of this actual tick still fits, but the desired later deadline
    // crosses the maximum qualified libuv conversion value.
    assert!(matches!(
        export(end, base, u64::MAX / 125, base, ratio),
        Err(DeadlineError::OutsideQualifiedRange)
    ));
    assert!(matches!(
        export(end, base, u64::MAX - 10, base, Timebase::new(1, 1).unwrap()),
        Err(DeadlineError::DeadlineOverflow)
    ));
}

#[test]
fn export_keeps_exact_u64_above_number_integer_precision() {
    let base = Instant::now();
    let sample = 9_007_199_254_740_993u64;
    let result = export(
        base + Duration::from_nanos(1000),
        base,
        sample,
        base,
        Timebase::new(1, 1).unwrap(),
    )
    .unwrap();
    let calibrated: u64 = result.calibrated_at_ns();
    let end: u64 = result.end_ns();
    assert_eq!(calibrated, 9_007_199_254_740_993u64);
    assert_eq!(end, 9_007_199_254_741_992u64);
    assert_eq!(calibrated.to_string(), "9007199254740993");
    assert_eq!(end.to_string(), "9007199254741992");
    // This tests exact pure output, not the future ABI encoder or Node reader.
}

#[test]
fn fixed_continuous_export_may_expire_earlier_after_suspend_without_reset() {
    let base = Instant::now();
    let original_end = base + Duration::from_nanos(100);
    let result = export(original_end, base, 1000, base, Timebase::new(1, 1).unwrap()).unwrap();
    assert_eq!(result.end_ns(), 1099u64);
    // Arithmetic model: one awake ns plus100 suspended ns on continuous clock;
    // Rust uptime has advanced only one ns. The original export stays fixed.
    let rust_after = base + Duration::from_nanos(1);
    let continuous_after = result.calibrated_at_ns() + 1 + 100;
    assert!(rust_after < original_end);
    assert!(continuous_after >= result.end_ns());
    assert_eq!(result.end_ns(), 1099u64);
}
