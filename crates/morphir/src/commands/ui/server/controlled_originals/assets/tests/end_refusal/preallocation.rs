// Prospective child of assets::tests::end_refusal. Actual allocator-component
// control only, with same explicit test INPUT policy and genuine source scope.
use super::*;
#[test]
fn browser_observed_assets_04_actual_preallocation_refuses_after_original_end() {
    let runtime = runtime();
    let ((refused, actual_capacity, source_was_active), _) =
        with_asset_stimulus(|stimulus, loans| {
            runtime.block_on(async {
                let source = loans.prepare_application_source().unwrap();
                const RAW: usize = 4096;
                loans
                    .reserve_application_storage(
                        &source,
                        RAW + std::mem::size_of::<Vec<u8>>(),
                        1,
                        RAW,
                    )
                    .unwrap();
                let original_end = Instant::now() + Duration::from_millis(80);
                tokio::time::sleep_until(original_end.into()).await;
                let (refused, actual_capacity) =
                    match allocate::<u8>(RAW, loans, &source, original_end) {
                        Err(ObservedAssetsFault::End) => (true, None),
                        Err(_) => (false, None),
                        Ok(actual) => {
                            let capacity = actual.capacity();
                            drop(actual); // Dispose the actual unexpected allocation before assertions.
                            (false, Some(capacity))
                        }
                    };
                let source_was_active = source.while_source_active(|| ()).is_ok();
                drop(stimulus); // No source-debt retirement is fabricated.
                (refused, actual_capacity, source_was_active)
            })
        });
    assert!(
        source_was_active,
        "this control isolates original-end expiry, not source revocation"
    );
    assert!(
        refused,
        "allocation must refuse before reserve; returned actual capacity: {actual_capacity:?}"
    );
    assert!(actual_capacity.is_none());
}
