//! One authenticated socket owns originals, binding evidence and their credits.
#[cfg(test)]
mod transport_tests;
use super::*;
use crate::commands::ui::{
    model_originals::{
        wire::{self, Binding, Parameters, WireError},
        *,
    },
    provider::originals::OriginalsSelection,
};

pub(super) struct OriginalSession {
    connection: ModelCaptureConnection,
    binding: Option<OwnedBinding>,
}
struct OwnedBinding {
    value: Binding,
    _credit: RetainedEvidenceCredit,
}
impl OriginalSession {
    pub(super) fn new(capacity: HostModelCaptureCapacity) -> Self {
        Self {
            connection: ModelCaptureConnection::new(capacity),
            binding: None,
        }
    }
    pub(super) fn from_host_observation(
        capacity: HostModelCaptureCapacity,
        observation: &HostObservationBinding,
    ) -> Self {
        let connection = match observation {
            HostObservationBinding::Disabled => ModelCaptureConnection::new(capacity),
            HostObservationBinding::Source(source) => {
                ModelCaptureConnection::new_observed(capacity, source.worker_scope())
            }
            HostObservationBinding::Record {
                source,
                registry,
                cleanup,
                #[cfg(test)]
                capture_hook,
            } => {
                let mut connection = ModelCaptureConnection::record_observed(
                    capacity,
                    source,
                    Some(registry.clone()),
                )
                .0;
                connection.attach_cleanup_registry(cleanup);
                #[cfg(test)]
                if let Some(hook) = capture_hook {
                    connection.attach_capture_test_hook(hook);
                }
                connection
            }
        };
        Self {
            connection,
            binding: None,
        }
    }
    pub(super) fn close(&mut self) {
        self.connection.close();
        self.binding = None;
    }
    pub(super) fn disconnect_control(&self) -> CaptureDisconnect {
        self.connection.disconnect_control()
    }
}

fn error(id: u64, error: WireError) -> DispatchResult {
    let mut result = DispatchResult::error(id, INVALID_PARAMS, error.code());
    result.envelope["error"]["data"] =
        json!({"profile":wire::PROFILE,"contractVersion":CONTRACT_VERSION,"code":error.code()});
    result
}
pub(super) fn invalid_frame(id: Value) -> Value {
    let mut envelope = error(0, WireError::InvalidRequest).envelope;
    envelope["id"] = id;
    envelope
}
fn completed(id: u64, result: Result<Value, WireError>) -> DispatchResult {
    match result {
        Ok(value) => DispatchResult::result(id, value),
        Err(fault) => error(id, fault),
    }
}
fn source_version(sources: &CapturedSources) -> Value {
    match sources.source_version() {
        SourceVersionEvidence::Reported(release) => {
            json!({"status":"reported","release":release.to_exact_string()})
        }
        SourceVersionEvidence::NotReported => json!({"status":"not-reported"}),
    }
}

pub(super) async fn dispatch_originals(
    host: &UiHostState,
    state: &mut ConnectionState,
    request: &JsonRpcRequest,
) -> DispatchResult {
    let method = match request.method {
        ConnectedMethod::ModelOriginalsCapture => "morphir.model-originals.capture",
        ConnectedMethod::ModelOriginalsInventory => "morphir.model-originals.inventory",
        ConnectedMethod::ModelOriginalsRead => "morphir.model-originals.read",
        ConnectedMethod::ModelOriginalsRelease => "morphir.model-originals.release",
        _ => unreachable!("model-originals dispatch"),
    };
    let params = match wire::decode(method, &request.params) {
        Ok(params) => params,
        Err(fault) => return error(request.id, fault),
    };
    if !state.initialized {
        return error(request.id, WireError::Unavailable);
    }
    match params {
        Parameters::Capture {
            provider,
            locator,
            project,
            scope,
            semantic,
        } => {
            let offered = host.manifest.providers.iter().any(|offer| {
                offer.id == provider
                    && offer.status == super::super::protocol::ProviderStatus::Available
                    && offer
                        .capabilities
                        .iter()
                        .any(|cap| cap.name == wire::PROFILE && cap.version == CONTRACT_VERSION)
            });
            if !offered {
                return error(request.id, WireError::Unavailable);
            }
            let selection = match OriginalsSelection::parse_identity(&provider, &locator, &project)
            {
                Ok(value) => value,
                Err(fault) => return error(request.id, fault.into()),
            };
            let offer = match host.current.select_originals(selection) {
                Ok(offer) => offer,
                Err(_) => return error(request.id, WireError::Unavailable),
            };
            // Reserve a conservative bound before allocating retained identity
            // strings. Decoded request labels remain separately request-bounded.
            let credit = match host
                .original_capacity
                .reserve_evidence(Binding::retained_bound())
            {
                Ok(credit) => credit,
                Err(fault) => return error(request.id, fault.into()),
            };
            let binding =
                match Binding::new(&host.manifest.session_id, &provider, &locator, &project) {
                    Ok(binding) => binding,
                    Err(fault) => return error(request.id, fault),
                };
            let pending = match state
                .originals
                .connection
                .start_offered_provider(offer, scope)
            {
                Ok(pending) => pending,
                Err(fault) => return error(request.id, fault.into()),
            };
            let result = match pending.wait().await {
                Ok(ModelCaptureCompletion::Ready(id)) => {
                    let result = state
                        .originals
                        .connection
                        .inspect_owned(&id, |sources| {
                            wire::ready(&binding, &id, sources, source_version(sources), semantic)
                        })
                        .map_err(WireError::from)
                        .and_then(|value| value);
                    match result {
                        Ok(value) => {
                            state.originals.binding = Some(OwnedBinding {
                                value: binding,
                                _credit: credit,
                            });
                            Ok(value)
                        }
                        Err(fault) => {
                            let _ = state.originals.connection.release(&id);
                            Err(fault)
                        }
                    }
                }
                Ok(ModelCaptureCompletion::Unavailable(reason)) => Ok(
                    json!({"profile":wire::PROFILE,"contractVersion":CONTRACT_VERSION,"status":"unavailable","reason":match reason { CaptureUnavailable::NotCompiled => "not_compiled", CaptureUnavailable::CompanionsUndeclared => "companions_undeclared" }}),
                ),
                Err(ProviderCaptureError::Capture(fault)) => Err(fault.into()),
                Err(ProviderCaptureError::Authority(_) | ProviderCaptureError::Changed) => {
                    Err(WireError::Unavailable)
                }
            };
            completed(request.id, result)
        }
        Parameters::Inventory {
            capture,
            start,
            maximum,
        } => {
            let Some(binding) = &state.originals.binding else {
                return error(request.id, CaptureError::UnknownHandle.into());
            };
            completed(
                request.id,
                state
                    .originals
                    .connection
                    .inspect_owned(&capture, |sources| {
                        wire::inventory(&binding.value, &capture, sources, start, maximum)
                    })
                    .map_err(WireError::from)
                    .and_then(|value| value),
            )
        }
        Parameters::Read {
            capture,
            target,
            offset,
            maximum,
        } => {
            let Some(binding) = &state.originals.binding else {
                return error(request.id, CaptureError::UnknownHandle.into());
            };
            completed(
                request.id,
                state
                    .originals
                    .connection
                    .inspect_owned(&capture, |sources| {
                        wire::read(&binding.value, &capture, sources, target, offset, maximum)
                    })
                    .map_err(WireError::from)
                    .and_then(|value| value),
            )
        }
        Parameters::Release { capture } => match state.originals.connection.release(&capture) {
            Ok(()) => {
                state.originals.binding = None;
                completed(
                    request.id,
                    wire::bounded(
                        json!({"profile":wire::PROFILE,"contractVersion":CONTRACT_VERSION,"captureId":capture,"status":"released"}),
                    ),
                )
            }
            Err(fault) => error(request.id, fault.into()),
        },
    }
}
