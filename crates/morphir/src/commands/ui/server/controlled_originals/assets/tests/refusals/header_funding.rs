//! Prospective child of assets::tests::refusals. Actual HeaderMap component
//! allocation/refusal only; public capacity is not a private-layout proof.
use super::*;

#[test]
fn browser_observed_assets_header_01_zero_work_and_one_short_table_refuse_before_map() {
    let plan = header_table_plan().unwrap();
    let short = u64::try_from(plan.requested.checked_sub(1).unwrap()).unwrap();
    for limits in [
        Limits { work: 0, ..ENOUGH },
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
