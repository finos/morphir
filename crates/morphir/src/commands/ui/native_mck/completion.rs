//! Reconcile the already-performed business and cleanup effects.
use morphir_mck::workbench::model_originals::native::NativeAdapterError;

pub(super) fn reconcile_completion<T>(
    action: Result<T, NativeAdapterError>,
    cleanup: Result<(), NativeAdapterError>,
) -> Result<T, NativeAdapterError> {
    match (action, cleanup) {
        (Err(primary), Err(cleanup)) => {
            tracing::warn!(
                ?primary,
                ?cleanup,
                "Native host cleanup also failed after action refusal"
            );
            Err(primary)
        }
        (Err(primary), Ok(())) => Err(primary),
        (Ok(_), Err(cleanup)) => Err(cleanup),
        (Ok(value), Ok(())) => Ok(value),
    }
}

#[cfg(test)]
mod error_precedence_tests;
