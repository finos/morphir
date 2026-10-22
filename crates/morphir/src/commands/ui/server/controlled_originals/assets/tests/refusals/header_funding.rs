//! Prospective child of assets::tests::refusals. Actual HeaderMap component
//! allocation/refusal only; public capacity is not a private-layout proof.
use super::*;

#[test]
fn browser_observed_assets_header_01_zero_work_and_one_short_table_refuse_before_map() {
    let ((first_source_refused, retry_source_refused), _) =
        scope(Limits { work: 0, ..ENOUGH }, |_, loans| {
            (
                loans.prepare_application_source().is_err(),
                loans.prepare_application_source().is_err(),
            )
        });
    assert!(first_source_refused && retry_source_refused);
    // Pay only the source wrapper and its actual Weak-counter initialization.
    // The SAME cumulative owner then has zero work left for either HeaderMap
    // attempt. This does not enlarge the header permission or a profile limit.
    let source_initialization = u64::try_from(
        std::mem::size_of::<morphir_mck::workbench::BrowserApplicationSource>()
            + std::mem::size_of::<std::sync::atomic::AtomicUsize>(),
    )
    .unwrap();
    let plan = header_table_plan().unwrap();
    let short = u64::try_from(plan.requested.checked_sub(1).unwrap()).unwrap();
    for limits in [
        Limits {
            work: source_initialization,
            ..ENOUGH
        },
        Limits {
            retained: short,
            ..ENOUGH
        },
    ] {
        let ((refused, unexpected_map, retry), _) = scope(limits, |_, loans| {
            let source = loans.prepare_application_source().unwrap();
            let end = Instant::now() + Duration::from_secs(10);
            let observe = |result: Result<HeaderMap, ObservedAssetsFault>| match result {
                Err(ObservedAssetsFault::Funding(_)) => (true, None),
                Err(_) => (false, None),
                Ok(actual) => {
                    let observed = (actual.len(), actual.capacity());
                    drop(actual); // Actual unexpected tables disposed before assertions.
                    (false, Some(observed))
                }
            };
            let (refused, unexpected_map) = observe(prepare_asset_headers(
                AssetMime::JavaScript,
                loans,
                &source,
                end,
            ));
            let (retry, retry_map) = observe(prepare_asset_headers(
                AssetMime::JavaScript,
                loans,
                &source,
                end,
            ));
            (refused, unexpected_map.or(retry_map), retry)
        });
        assert!(
            refused,
            "permission must precede real map tables; unexpected len/capacity: {unexpected_map:?}"
        );
        assert!(retry, "same-owner retry must preserve the first refusal");
        assert!(unexpected_map.is_none());
    }
}
