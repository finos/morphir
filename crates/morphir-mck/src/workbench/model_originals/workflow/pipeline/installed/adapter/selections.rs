//! Serialize only the actual cached stdout fields, under the same owners.
use super::*;
use crate::json::strict::Document;
use crate::workbench::model_originals::workflow::{
    DecodeError, Decoder, installed_measurements as data,
};
#[derive(serde::Serialize)]
struct Source<'a> {
    #[serde(rename = "providerId")]
    provider: &'a str,
    locator: &'a str,
}
#[derive(serde::Serialize)]
struct Selection<'a> {
    source: Source<'a>,
    #[serde(rename = "projectId", skip_serializing_if = "Option::is_none")]
    project: Option<&'a str>,
}
fn text(value: Option<&Document>) -> Result<&str, DecodeError> {
    value
        .and_then(data::text)
        .ok_or(DecodeError::Shape("actual installed selection"))
}
pub(super) fn runtime_selection(
    live: &data::LiveMeasurements,
    owner: &mut Decoder,
    receiver: &mut InstalledObservationOwner,
) -> Result<data::SelectedRuntimeData, DecodeError> {
    let selected = fields(live, owner, true)?;
    let session = text(live.claim(0, &["sessionId"], owner)?)?;
    let project = selected
        .project
        .ok_or(DecodeError::Shape("actual installed project"))?;
    for raw in [
        session,
        selected.source.provider,
        selected.source.locator,
        project,
    ] {
        owner.bytes(raw.len().checked_mul(2).ok_or(DecodeError::Limits)?)?;
        receiver
            .reserve_span(InstalledObservationResource::RetainedBytes, raw.len())
            .map_err(|_| DecodeError::Allocation)?;
        receiver
            .reserve_span(
                InstalledObservationResource::ByteVisits,
                raw.len().checked_mul(2).ok_or(DecodeError::Limits)?,
            )
            .map_err(|_| DecodeError::Allocation)?;
    }
    use crate::workbench::model_originals as protocol;
    Ok(data::SelectedRuntimeData {
        session_id: protocol::SessionId::new(session)
            .map_err(|_| DecodeError::Shape("actual session"))?,
        source: protocol::SourceIdentity {
            provider: protocol::ProviderId::new(selected.source.provider)
                .map_err(|_| DecodeError::Shape("actual provider"))?,
            locator: protocol::SourceLocator::new(selected.source.locator)
                .map_err(|_| DecodeError::Shape("actual locator"))?,
        },
        project_id: protocol::ProjectId::new(project)
            .map_err(|_| DecodeError::Shape("actual project"))?,
    })
}
fn fields<'a>(
    live: &'a data::LiveMeasurements,
    owner: &mut Decoder,
    project: bool,
) -> Result<Selection<'a>, DecodeError> {
    let Some(Document::Array(sources)) = live.claim(0, &["sources"], owner)? else {
        return Err(DecodeError::Shape("actual installed sources"));
    };
    let first = sources
        .first()
        .ok_or(DecodeError::Shape("actual installed source"))?;
    let provider = text(data::member(first, "providerId", owner)?)?;
    let locator = text(data::member(first, "locator", owner)?)?;
    let project = if project {
        let Some(Document::Array(projects)) = live.claim(1, &["projects"], owner)? else {
            return Err(DecodeError::Shape("actual installed projects"));
        };
        let first = projects
            .first()
            .ok_or(DecodeError::Shape("actual installed project"))?;
        Some(text(data::member(first, "projectId", owner)?)?)
    } else {
        None
    };
    Ok(Selection {
        source: Source { provider, locator },
        project,
    })
}
fn encoded(
    receiver: &mut InstalledObservationOwner,
    decode: &mut Decoder,
    value: &Selection<'_>,
) -> Result<RetainedObservationText, InstalledObservationError> {
    let raw = value
        .source
        .provider
        .len()
        .checked_add(value.source.locator.len())
        .and_then(|n| n.checked_add(value.project.map_or(0, str::len)))
        .ok_or(InstalledObservationError::SizeOverflow)?;
    let visits = raw
        .checked_mul(6)
        .and_then(|n| n.checked_add(64))
        .ok_or(InstalledObservationError::SizeOverflow)?;
    receiver.reserve_span(InstalledObservationResource::ByteVisits, visits)?;
    decode
        .bytes(visits)
        .map_err(|_| InstalledObservationError::PriorFault)?;
    let length =
        crate::workbench::contract::encoded_size(value, crate::workbench::MAX_REPORT_BYTES)
            .map_err(|_| InstalledObservationError::SizeOverflow)?;
    receiver.reserve_span(InstalledObservationResource::RetainedBytes, length)?;
    receiver.reserve_span(InstalledObservationResource::ByteVisits, length)?;
    let mut bytes = Vec::new();
    bytes
        .try_reserve_exact(length)
        .map_err(|_| InstalledObservationError::Allocation)?;
    receiver.reserve_span(
        InstalledObservationResource::RetainedBytes,
        bytes
            .capacity()
            .checked_sub(length)
            .ok_or(InstalledObservationError::LayoutMismatch)?,
    )?;
    serde_json::to_writer(&mut bytes, value)
        .map_err(|_| InstalledObservationError::LayoutMismatch)?;
    if bytes.len() != length {
        return Err(InstalledObservationError::LayoutMismatch);
    }
    receiver.reserve_span(InstalledObservationResource::ByteVisits, length)?;
    decode
        .bytes(length)
        .map_err(|_| InstalledObservationError::PriorFault)?;
    let text = String::from_utf8(bytes).map_err(|_| InstalledObservationError::LayoutMismatch)?;
    Ok(RetainedObservationText::from_owned(text))
}
impl InstalledClientRun<'_> {
    fn selection_json(
        &mut self,
        project: bool,
    ) -> Result<RetainedObservationText, InstalledAdapterError> {
        self.work_ready()?;
        let value = fields(&self.collected, self.decode, project).map_err(|error| {
            self.attempt.fail(RunFault::Decode(error));
            InstalledAdapterError::ObservationIncomplete
        })?;
        let result = encoded(self.receiving, self.decode, &value);
        if let Err(error) = self.decode.ready() {
            self.attempt.fail(RunFault::Decode(error));
        }
        result.map_err(|error| self.observation_failure(error))
    }
    pub fn source_selection_json(
        &mut self,
    ) -> Result<RetainedObservationText, InstalledAdapterError> {
        self.selection_json(false)
    }
    pub fn project_selection_json(
        &mut self,
    ) -> Result<RetainedObservationText, InstalledAdapterError> {
        self.selection_json(true)
    }
    pub fn copy_published_path(
        &mut self,
    ) -> Result<RetainedObservationText, InstalledAdapterError> {
        self.work_ready()?;
        let Some(Document::Array(paths)) = self
            .collected
            .claim(2, &["published"], self.decode)
            .map_err(|error| {
                self.attempt.fail(RunFault::Decode(error));
                InstalledAdapterError::ObservationIncomplete
            })?
        else {
            self.attempt.fail(RunFault::Installed(
                InstalledAdapterError::ObservationIncomplete,
            ));
            return Err(InstalledAdapterError::ObservationIncomplete);
        };
        let value = paths
            .first()
            .and_then(data::text)
            .ok_or(InstalledAdapterError::ObservationIncomplete)?;
        super::super::observation::prepare_text_copy(
            self.receiving,
            self.comparison,
            ObservationBufferRole::CensusMetadata,
            value,
        )
        .and_then(|ticket| ticket.retain_text())
        .map_err(|_| InstalledAdapterError::ObservationIncomplete)
    }
}
