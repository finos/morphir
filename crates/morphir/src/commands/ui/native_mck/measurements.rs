//! Translate genuine host snapshots and actual protocol replies into MCK DATA.
use morphir_common::config::observation::{FileReadWitness, ReadClass, ReadSnapshot};
use morphir_mck::workbench::model_originals::native::{NativeAdapterError, data};
use serde_json::Value;

use super::super::model_originals::{
    ModelCaptureUsage,
    observation::{HostCall, HostSourceSnapshot, WorkerSnapshot},
};

#[derive(Clone, Copy)]
pub(super) enum SnapshotPhase {
    Open,
    Sealed,
}

pub(super) fn text<'a>(value: &'a Value, key: &str) -> Result<&'a str, NativeAdapterError> {
    value
        .get(key)
        .and_then(Value::as_str)
        .ok_or(NativeAdapterError::Exchange)
}
pub(super) fn number(value: &Value, key: &str) -> Result<u64, NativeAdapterError> {
    value
        .get(key)
        .and_then(Value::as_u64)
        .ok_or(NativeAdapterError::Exchange)
}
pub(super) fn data_error(_: data::DataValueError) -> NativeAdapterError {
    NativeAdapterError::ObservationIncomplete
}
pub(super) fn alias(value: &str) -> Result<data::FixtureAlias, NativeAdapterError> {
    data::FixtureAlias::new(value).map_err(|_| NativeAdapterError::Selection)
}
pub(super) fn digest(value: &str) -> Result<data::ContentSha256, NativeAdapterError> {
    if value.len() != 64 {
        return Err(NativeAdapterError::Exchange);
    }
    let mut bytes = [0; 32];
    for (target, pair) in bytes.iter_mut().zip(value.as_bytes().as_chunks::<2>().0) {
        let part = std::str::from_utf8(pair).map_err(|_| NativeAdapterError::Exchange)?;
        *target = u8::from_str_radix(part, 16).map_err(|_| NativeAdapterError::Exchange)?;
    }
    Ok(data::ContentSha256::new(bytes))
}
pub(super) fn root(value: &Value) -> Result<data::Root, NativeAdapterError> {
    let path = data::SourcePath::new(text(value, "path")?).map_err(data_error)?;
    match text(value, "kind")? {
        "file" => Ok(data::Root::File { path }),
        "directory" => Ok(data::Root::Directory { path }),
        _ => Err(NativeAdapterError::Exchange),
    }
}
pub(super) fn declaration_root(value: &Value) -> Result<data::DeclarationRoot, NativeAdapterError> {
    let path = data::SourcePath::new(text(value, "path")?).map_err(data_error)?;
    match text(value, "kind")? {
        "file" => Ok(data::DeclarationRoot::File { path }),
        "directory" => Ok(data::DeclarationRoot::Directory { path }),
        _ => Err(NativeAdapterError::Exchange),
    }
}
pub(super) fn capture(
    value: &Value,
    alias: &data::FixtureAlias,
) -> Result<data::CapturedEvidence, NativeAdapterError> {
    if text(value, "status")? != "ready" {
        return Err(NativeAdapterError::Exchange);
    }
    let coverage = match text(&value["coverage"], "kind")? {
        "primary" => data::CaptureCoverage::Primary {},
        "complete" if text(&value["coverage"], "declaration")? == "0.1.0-draft.1" => {
            data::CaptureCoverage::Complete {
                declaration: data::CaptureCoverageCompleteDeclaration,
            }
        }
        _ => return Err(NativeAdapterError::Exchange),
    };
    let summary = &value["inventory"];
    let projection = match text(&value["projection"], "status")? {
        "not-requested" => data::ProjectionWitness::NotRequested {},
        _ => return Err(NativeAdapterError::UnsupportedAction),
    };
    let header = match text(&value["sourceFormatVersion"], "status")? {
        "not-reported" => data::SourceHeader::NotReported {},
        "reported" => data::SourceHeader::Reported {
            release: data::Text::new(text(&value["sourceFormatVersion"], "release")?)
                .map_err(data_error)?,
        },
        _ => return Err(NativeAdapterError::Exchange),
    };
    let companions = value["companions"]
        .as_array()
        .ok_or(NativeAdapterError::Exchange)?
        .iter()
        .map(root)
        .collect::<Result<Vec<_>, _>>()?;
    Ok(data::CapturedEvidence {
        capture: alias.clone(),
        coverage,
        projection,
        inventory: data::InventoryEvidence {
            directory_count: data::Natural::new(number(summary, "directoryCount")?)
                .map_err(data_error)?,
            entry_count: data::Natural::new(number(summary, "entryCount")?).map_err(data_error)?,
            file_count: data::Natural::new(number(summary, "fileCount")?).map_err(data_error)?,
            source_byte_length: data::Natural::new(number(summary, "sourceByteLength")?)
                .map_err(data_error)?,
            sha256: digest(text(summary, "sha256")?)?,
        },
        source: data::SourceRoles {
            primary_root: root(&value["primary"])?,
            companion_roots: data::Items::new(companions).map_err(data_error)?,
            source_format_version: header,
        },
    })
}
fn read_counts(value: morphir_common::config::observation::ReadCounts) -> data::ReadCounts {
    data::ReadCounts {
        attempts: data::ObservedCount(value.content_attempts()),
        read_calls: data::ObservedCount(value.read_calls()),
        returned_bytes: data::ObservedCount(value.returned_bytes()),
    }
}
pub(super) fn prefix(value: &ReadSnapshot) -> data::ReadPrefix {
    data::ReadPrefix {
        total: read_counts(value.total_counts()),
        workspace: read_counts(value.counts(ReadClass::WorkspaceContent)),
        ambient: read_counts(value.counts(ReadClass::AmbientContent)),
    }
}
pub(super) fn workers(
    value: WorkerSnapshot,
    phase: SnapshotPhase,
) -> Result<data::WorkerMeasurements, NativeAdapterError> {
    let counts = data::WorkerCounts {
        scheduled: data::ObservedCount(value.scheduled()),
        started: data::ObservedCount(value.started()),
        returned_ok: data::ObservedCount(value.returned_ok()),
        returned_error: data::ObservedCount(value.returned_error()),
        panicked: data::ObservedCount(value.panicked()),
        joined_ok: data::ObservedCount(value.joined_ok()),
        joined_panicked: data::ObservedCount(value.joined_panicked()),
        joined_cancelled: data::ObservedCount(value.joined_cancelled()),
        owned_handles: data::ObservedCount(value.owned_handles()),
        dropped_unjoined: data::ObservedCount(value.dropped_unjoined()),
    };
    match phase {
        SnapshotPhase::Sealed => {
            value
                .require_joined_cleanup()
                .map_err(|_| NativeAdapterError::Cleanup)?;
            Ok(data::WorkerMeasurements::JoinedCleanup { counts })
        }
        SnapshotPhase::Open => Ok(data::WorkerMeasurements::ObservedPrefix { counts }),
    }
}
pub(super) struct Witnesses {
    pub record: (String, FileReadWitness),
    pub primary: (String, FileReadWitness),
    pub sentinel: (String, FileReadWitness),
}
impl Witnesses {
    pub fn source(
        &self,
        snapshot: &HostSourceSnapshot,
        phase: SnapshotPhase,
    ) -> Result<data::SourceMeasurements, NativeAdapterError> {
        let counts = prefix(snapshot.reads());
        if matches!(phase, SnapshotPhase::Open) {
            return Ok(data::SourceMeasurements::OpenPrefix { counts });
        }
        snapshot
            .require_source_complete()
            .map_err(|_| NativeAdapterError::ObservationIncomplete)?;
        let files = [
            (&self.record, data::FileRole::CompileRecord),
            (&self.primary, data::FileRole::OriginalPrimary),
            (&self.sentinel, data::FileRole::UndeclaredSentinel),
        ]
        .into_iter()
        .map(|((path, witness), role)| {
            Ok(data::FileCounts {
                role,
                path: data::SourcePath::new(path).map_err(data_error)?,
                reads: read_counts(
                    snapshot
                        .reads()
                        .counts_for(witness)
                        .map_err(|_| NativeAdapterError::ObservationIncomplete)?,
                ),
            })
        })
        .collect::<Result<Vec<_>, NativeAdapterError>>()?;
        Ok(data::SourceMeasurements::SealedComplete {
            counts,
            files: data::Items::new(files).map_err(data_error)?,
        })
    }
}
pub(super) fn resources(
    usage: ModelCaptureUsage,
    record_bytes: usize,
) -> Result<data::ResourceEvidence, NativeAdapterError> {
    Ok(data::ResourceEvidence {
        active_workers: data::Natural::new(usage.active_workers() as u64).map_err(data_error)?,
        metadata_bytes: data::Natural::new(usage.metadata_bytes() as u64).map_err(data_error)?,
        // The actual selected route is OriginalsOnly/SemanticRequest::None.
        projection_bytes: data::Natural::new(0).map_err(data_error)?,
        record_bytes: data::Natural::new(record_bytes as u64).map_err(data_error)?,
        slots: data::Natural::new(usage.captures() as u64).map_err(data_error)?,
        source_bytes: data::Natural::new(usage.source_bytes() as u64).map_err(data_error)?,
    })
}
pub(super) fn entries(snapshot: &HostSourceSnapshot) -> data::EntryCoverage {
    data::EntryCoverage::Complete {
        compile_calls: data::ObservedCount(snapshot.calls(HostCall::Compile)),
        legacy_model_open_calls: data::ObservedCount(snapshot.calls(HostCall::LegacyModelOpen)),
    }
}
