//! A capture binding exists only after the genuine selected capture succeeds.
use morphir_mck::workbench::model_originals::native::{
    NativeAdapterError, NativeOriginalRun, data,
};
use serde_json::Value;

use super::{
    super::model_originals::{CaptureId, PrivateRecordObserver, observation::HostSourceSnapshot},
    measurements::{self, data_error, text},
};

pub(super) struct Discovery {
    pub connection: data::FixtureAlias,
    pub provider: data::FixtureAlias,
    pub projects: Vec<DiscoveredProject>,
}
pub(super) struct DiscoveredProject {
    pub id: data::ProjectId,
    pub module: String,
}
impl DiscoveredProject {
    pub fn from_reply(value: &Value) -> Result<Self, NativeAdapterError> {
        Ok(Self {
            id: data::ProjectId::new(text(value, "id")?)
                .map_err(|_| NativeAdapterError::Discovery)?,
            module: text(value, "relativePath")?.to_owned(),
        })
    }
}
pub(super) struct CaptureBinding {
    pub connection: data::FixtureAlias,
    pub provider: data::FixtureAlias,
    pub project: data::FixtureAlias,
    pub registration: data::FixtureAlias,
    pub capture: data::FixtureAlias,
    pub id: CaptureId,
    pub session: data::SessionId,
    pub source: data::SourceIdentity,
    pub project_id: data::ProjectId,
}
impl CaptureBinding {
    pub fn selection(self) -> Result<data::ResolvedSelectionData, NativeAdapterError> {
        Ok(data::ResolvedSelectionData {
            connection: self.connection,
            provider: self.provider,
            project: self.project,
            registration: self.registration,
            session_id: self.session,
            source: self.source,
            project_id: self.project_id,
            capture: self.capture,
            capture_id: data::CaptureId::new(self.id.as_str())
                .map_err(|_| NativeAdapterError::Selection)?,
        })
    }
}
pub(super) enum RecordOwnership {
    InHost {
        observer: PrivateRecordObserver,
        digest: data::ContentSha256,
        declaration: data::FrozenDeclaration,
    },
    Adopted {
        observer: PrivateRecordObserver,
        record: data::FrozenPrivateRecord,
    },
}
impl RecordOwnership {
    pub fn retained_bytes(&self) -> usize {
        match self {
            Self::InHost { observer, .. } | Self::Adopted { observer, .. } => {
                observer.snapshot().retained_bytes()
            }
        }
    }
    pub fn adopt(
        self,
        id: &CaptureId,
        run: &mut NativeOriginalRun<'_>,
    ) -> Result<Self, NativeAdapterError> {
        match self {
            Self::Adopted { .. } => Ok(self),
            Self::InHost {
                observer,
                digest,
                declaration,
            } => {
                // Length is allocation metadata. No byte scan happens before
                // the receiving owner precharges the SAME allocation.
                let length = observer
                    .with_ready_record(id, Vec::len)
                    .map_err(|_| NativeAdapterError::ObservationIncomplete)?;
                let ticket = observer
                    .with_ready_record(id, |raw| run.prepare_private_record_adoption(raw))
                    .map_err(|_| NativeAdapterError::ObservationIncomplete)?
                    .map_err(|_| NativeAdapterError::ObservationIncomplete)?;
                let bytes = observer
                    .take(id)
                    .map_err(|_| NativeAdapterError::ObservationIncomplete)?
                    .adopt(ticket)
                    .map_err(|_| NativeAdapterError::ObservationIncomplete)?;
                Ok(Self::Adopted {
                    observer,
                    record: data::FrozenPrivateRecord {
                        bytes,
                        byte_length: data::ObservedCount(length as u64),
                        sha256: digest,
                        declaration,
                    },
                })
            }
        }
    }
    pub fn complete(
        self,
    ) -> Result<(PrivateRecordObserver, data::FrozenPrivateRecord), NativeAdapterError> {
        match self {
            Self::Adopted { observer, record } => Ok((observer, record)),
            Self::InHost { .. } => Err(NativeAdapterError::ObservationIncomplete),
        }
    }
}
pub(super) struct ReadyCapture {
    pub binding: CaptureBinding,
    pub evidence: data::CapturedEvidence,
    pub record: RecordOwnership,
}
pub(super) struct CompletedCapture {
    pub binding: CaptureBinding,
    pub evidence: data::CapturedEvidence,
    pub observer: PrivateRecordObserver,
    pub record: data::FrozenPrivateRecord,
}
pub(super) enum State {
    Unconnected,
    Connected {
        connection: data::FixtureAlias,
    },
    Discovered(Discovery),
    Ready(ReadyCapture),
    Released(CompletedCapture),
    Closed {
        capture: CompletedCapture,
        snapshot: Box<HostSourceSnapshot>,
    },
}
impl State {
    pub fn binding(&self) -> Result<&CaptureBinding, NativeAdapterError> {
        match self {
            Self::Ready(capture) => Ok(&capture.binding),
            Self::Released(capture) | Self::Closed { capture, .. } => Ok(&capture.binding),
            Self::Unconnected | Self::Connected { .. } | Self::Discovered(_) => {
                Err(NativeAdapterError::Selection)
            }
        }
    }
    pub fn retained_record_bytes(&self) -> Result<usize, NativeAdapterError> {
        match self {
            Self::Ready(capture) => Ok(capture.record.retained_bytes()),
            Self::Released(capture) | Self::Closed { capture, .. } => {
                Ok(capture.observer.snapshot().retained_bytes())
            }
            Self::Unconnected | Self::Connected { .. } | Self::Discovered(_) => {
                Err(NativeAdapterError::Selection)
            }
        }
    }
    pub fn measured_state(&self) -> Result<data::CaptureState, NativeAdapterError> {
        let binding = self.binding()?;
        match self {
            Self::Ready(_) => Ok(data::CaptureState::Ready {
                capture: binding.capture.clone(),
                connection: binding.connection.clone(),
            }),
            Self::Released(_) => Ok(data::CaptureState::Released {
                last_capture: binding.capture.clone(),
                connection: binding.connection.clone(),
            }),
            Self::Closed { .. } => Ok(data::CaptureState::Closed {
                cleanup: data::CaptureStateClosedCleanup::None {},
            }),
            Self::Unconnected | Self::Connected { .. } | Self::Discovered(_) => {
                Err(NativeAdapterError::Selection)
            }
        }
    }
    pub fn adopt(self, run: &mut NativeOriginalRun<'_>) -> Result<Self, NativeAdapterError> {
        match self {
            Self::Ready(ReadyCapture {
                binding,
                evidence,
                record,
            }) => {
                let record = record.adopt(&binding.id, run)?;
                Ok(Self::Ready(ReadyCapture {
                    binding,
                    evidence,
                    record,
                }))
            }
            Self::Released(_) | Self::Closed { .. } => Ok(self),
            Self::Unconnected | Self::Connected { .. } | Self::Discovered(_) => {
                Err(NativeAdapterError::Selection)
            }
        }
    }
}
pub(super) fn declaration(ready: &Value) -> Result<data::FrozenDeclaration, NativeAdapterError> {
    if text(&ready["coverage"], "kind")? != "complete"
        || text(&ready["coverage"], "declaration")? != "0.1.0-draft.1"
    {
        return Err(NativeAdapterError::ObservationIncomplete);
    }
    Ok(data::FrozenDeclaration::Declared {
        version: data::DeclaredVersion,
        companions: data::Items::new(
            ready["companions"]
                .as_array()
                .ok_or(NativeAdapterError::Exchange)?
                .iter()
                .map(measurements::declaration_root)
                .collect::<Result<Vec<_>, _>>()?,
        )
        .map_err(data_error)?,
    })
}
