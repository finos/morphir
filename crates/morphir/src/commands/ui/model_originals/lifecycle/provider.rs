//! One actual worker owns provider resolution, capture and revalidation effects.
use super::*;
use crate::{
    commands::ui::provider::originals::{SelectedOriginalsOffer, SourceResolution},
    error::CliError,
};

/// Internal source authority and storage failures, without a public wire mapping.
#[derive(Debug, thiserror::Error)]
pub enum ProviderCaptureError {
    #[error(transparent)]
    Capture(#[from] CaptureError),
    #[error("Original-source authority resolution failed: {0}")]
    Authority(#[from] CliError),
    #[error("The selected project or output authority changed before publication.")]
    Changed,
}
impl From<std::io::Error> for ProviderCaptureError {
    fn from(error: std::io::Error) -> Self {
        Self::Authority(error.into())
    }
}
impl ModelCaptureConnection {
    /// Capture using an actual provider, retaining work through fresh authority
    /// checks. This internal foundation advertises no connected capability.
    pub fn start_offered_provider(
        &self,
        offer: SelectedOriginalsOffer,
        scope: CaptureScope,
    ) -> Result<PendingProviderCapture, CaptureError> {
        self.start_offered_provider_with(offer, scope, CaptureControl::new(), Arc::new(NoopHooks))
    }
    pub(in crate::commands::ui::model_originals) fn start_offered_provider_with(
        &self,
        offer: SelectedOriginalsOffer,
        scope: CaptureScope,
        control: CaptureControl,
        hooks: Arc<dyn WorkerHooks>,
    ) -> Result<PendingProviderCapture, CaptureError> {
        let runtime =
            tokio::runtime::Handle::try_current().map_err(|_| CaptureError::CaptureFailed)?;
        control.check()?;
        let mut state = self.state.lock().expect("model capture connection");
        match &*state {
            ConnectionState::Capturing { .. }
            | ConnectionState::Prepared(_)
            | ConnectionState::Ready(_) => return Err(CaptureError::ActiveCapture),
            ConnectionState::Closed => return Err(CaptureError::UnknownHandle),
            _ => {}
        }
        // This reservation precedes ALL provider resolution, config traversal,
        // installed activation/discovery and source capture effects.
        let (mut reservation, permit) = self.capacity.reserve()?;
        let attempt = AttemptKey(uuid::Uuid::new_v4());
        *state = ConnectionState::Capturing {
            attempt,
            control: control.clone(),
        };
        drop(state);
        let owner = Arc::downgrade(&self.state);
        let worker_owner = owner.clone();
        let worker_control = control.clone();
        let guest_runtime = runtime.clone();
        let capacity = self.capacity.clone();
        let result = runtime.spawn_blocking(move || {
            // Never abort this worker on waiter cancellation. It owns the same
            // one permit through genuine synchronous/async guest effects and
            // their cleanup, including private preparation and publication.
            let _worker_permit = permit.clone();
            hooks.before_capture();
            worker_control.check()?;
            offer.with_current(|valid| valid)?;
            let provider = offer.provider();
            let selection = offer.selection();
            let resolved = match guest_runtime.block_on(provider.resolve(selection, &capacity))? {
                SourceResolution::Compiled(resolved) => resolved,
                SourceResolution::NotCompiled => {
                    finish(
                        &worker_owner,
                        attempt,
                        &worker_control,
                        Ok(CaptureResult::Unavailable(CaptureUnavailable::NotCompiled)),
                        reservation,
                        permit,
                    )?;
                    return Ok(ModelCaptureCompletion::Unavailable(
                        CaptureUnavailable::NotCompiled,
                    ));
                }
            };
            worker_control.check()?;
            let captured = capture_accounted(
                resolved.output(),
                resolved.module(),
                scope,
                &worker_control,
                Limits::default(),
                &mut reservation,
            )
            .and_then(|mut result| {
                if let CaptureResult::Ready(sources) = &mut result {
                    worker_control.check()?;
                    let bytes = std::mem::size_of::<SourceVersionEvidence>();
                    let metadata = sources
                        .metadata_bytes
                        .checked_add(bytes)
                        .filter(|total| *total <= MAX_METADATA_BYTES)
                        .ok_or(CaptureError::InventoryLimit)?;
                    // The closed retained evidence is charged on the SAME host
                    // ledger before probing, before its final owned value exists.
                    reservation.metadata(bytes)?;
                    sources.metadata_bytes = metadata;
                    hooks.before_source_header();
                    worker_control.check()?;
                    sources.source_version = frozen_source_version(sources);
                    worker_control.check()?;
                }
                Ok(result)
            });
            let completion = finish(
                &worker_owner,
                attempt,
                &worker_control,
                captured,
                reservation,
                permit,
            )?;
            let WorkerCompletion::Prepared = completion else {
                let WorkerCompletion::Unavailable(reason) = completion else {
                    unreachable!()
                };
                return Ok(ModelCaptureCompletion::Unavailable(reason));
            };
            let prepared = PreparedModelCapture {
                owner: worker_owner,
                attempt,
                control: worker_control.clone(),
                armed: true,
            };
            hooks.after_capture(); // private Prepared, before actual revalidation
            worker_control.check()?;
            let current = guest_runtime.block_on(provider.resolve(selection, &capacity));
            let result = match current {
                Ok(SourceResolution::Compiled(current)) if resolved.same_authority(&current) => {
                    offer.with_current(|valid| match valid {
                        Ok(()) => prepared.publish().map_err(Into::into),
                        Err(error) => {
                            prepared.reject();
                            Err(error)
                        }
                    })
                }
                Ok(_) => {
                    prepared.reject();
                    Err(ProviderCaptureError::Changed)
                }
                Err(error) => {
                    prepared.reject();
                    Err(error)
                }
            };
            hooks.before_worker_exit();
            result
        });
        Ok(PendingProviderCapture {
            owner,
            attempt,
            control,
            result,
            armed: true,
        })
    }
}

fn frozen_source_version(sources: &CapturedSources) -> SourceVersionEvidence {
    use super::super::source_header::{SourceHeader, inspect};
    use morphir_core::ir::decode::{DecodeBudget, DecodeLimits};
    use morphir_devkit::IrLayout;

    let format = sources.record().descriptor().format();
    let bytes = match sources.record().descriptor().layout() {
        IrLayout::SingleFile => sources.file_bytes(sources.primary().path()),
        IrLayout::DocumentTree => {
            // Match actual document-tree discovery: exactly one supported
            // root manifest, whose format agrees with the selected descriptor.
            // Borrow inventory paths; do not reopen live files or build paths.
            let mut found = None;
            for entry in sources.entries() {
                if entry.kind() != SourceKind::File {
                    continue;
                }
                let Some(relative) = entry
                    .path()
                    .as_str()
                    .strip_prefix(sources.primary().path().as_str())
                    .and_then(|suffix| suffix.strip_prefix('/'))
                else {
                    continue;
                };
                let selected = match relative {
                    "manifest.json" => SourceFormat::Json,
                    "manifest.yaml" | "manifest.yml" => SourceFormat::Yaml,
                    "manifest.ion" => SourceFormat::Ion,
                    _ => continue,
                };
                if found.is_some() {
                    return SourceVersionEvidence::NotReported;
                }
                found = Some((selected, entry.path()));
            }
            found
                .filter(|(selected, _)| *selected == format)
                .and_then(|(_, path)| sources.file_bytes(path))
        }
    };
    let mut budget = DecodeBudget::new(DecodeLimits::model_originals());
    match bytes.map(|bytes| inspect(format, bytes, &mut budget)) {
        Some(Ok(SourceHeader::Reported(header))) => SourceVersionEvidence::Reported(header.release),
        _ => SourceVersionEvidence::NotReported,
    }
}
impl PreparedModelCapture {
    // Completed authority refusal is not waiter cancellation. Drop retained
    // ownership without signalling a racing Timeout instead of the real error.
    fn reject(mut self) {
        if let Some(owner) = self.owner.upgrade() {
            let prior = {
                let mut state = owner.lock().expect("model capture connection");
                state
                    .matches(self.attempt)
                    .then(|| std::mem::replace(&mut *state, ConnectionState::Empty))
            };
            drop(prior);
        }
        self.armed = false;
    }
}
/// A waiter may be dropped while actual provider work continues. Its Drop only
/// cancels this attempt; the genuine worker retains its reserved work credit.
pub struct PendingProviderCapture {
    owner: Weak<Mutex<ConnectionState>>,
    attempt: AttemptKey,
    control: CaptureControl,
    result: JoinHandle<Result<ModelCaptureCompletion, ProviderCaptureError>>,
    armed: bool,
}
impl PendingProviderCapture {
    pub fn cancel(&self) {
        abandon(&self.owner, self.attempt, &self.control);
    }
    pub async fn wait(mut self) -> Result<ModelCaptureCompletion, ProviderCaptureError> {
        let deadline = tokio::time::Instant::from_std(self.control.deadline());
        let result = tokio::select! {
            result = &mut self.result => result.map_err(|_| CaptureError::CaptureFailed)?,
            () = self.control.cancelled() => return Err(CaptureError::Timeout.into()),
            () = tokio::time::sleep_until(deadline) => return Err(CaptureError::Timeout.into()),
        }?;
        self.control.check()?;
        if let ModelCaptureCompletion::Ready(id) = &result {
            let owner = self.owner.upgrade().ok_or(CaptureError::Timeout)?;
            if !matches!(&*owner.lock().expect("model capture connection"),
                ConnectionState::Ready(capture) if capture.attempt == self.attempt && &capture.id == id)
            {
                return Err(CaptureError::Timeout.into());
            }
        }
        self.armed = false;
        Ok(result)
    }
}
impl Drop for PendingProviderCapture {
    fn drop(&mut self) {
        if self.armed {
            self.cancel();
        }
    }
}
