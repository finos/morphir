//! Paid, source-selected client stimulus. Literal malformed/status/refusal
//! inputs stay literal; these bytes are not a SessionManifest or observations.
use super::{
    adapter::{BrowserScope, BrowserSemantic, BrowserSourceIdentity},
    inputs::{
        BrowserActionKind, BrowserClientInput, BrowserInputFault, BrowserOwnerLoans,
        BrowserRuntimeInput,
    },
    source_scope::{BrowserSourceBinding, BrowserSourceScope, ScopeFault, ScopeIssueFault},
};
use crate::workbench::model_originals::workflow::{
    input::{self, Frame, FramePart},
    pipeline::installed::observation::{InstalledObservationFault, InstalledObservationResource},
    work::ClosureError,
};
use std::alloc::Layout;

/// Owned prepaid stimulus deliveries only. Taking these values attests no
/// HTTP/WebSocket send, client acceptance, capture, result or physical cleanup.
pub struct ControlledHostDelivery {
    manifest: DeliverySlot<ControlledManifestDelivery>,
    peer: DeliverySlot<ControlledPeerDelivery>,
}
enum DeliverySlot<T> {
    Ready(T),
    Taken,
}
pub struct ControlledManifestDelivery {
    status: u64,
    body: String,
}
pub struct ControlledPeerDelivery {
    frames: Vec<String>,
    requests: Option<Vec<String>>,
}
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ControlledDeliveryFault {
    Taken,
}
impl ControlledHostDelivery {
    pub fn take_manifest(&mut self) -> Result<ControlledManifestDelivery, ControlledDeliveryFault> {
        match std::mem::replace(&mut self.manifest, DeliverySlot::Taken) {
            DeliverySlot::Ready(value) => Ok(value),
            DeliverySlot::Taken => Err(ControlledDeliveryFault::Taken),
        }
    }
    pub fn take_peer(&mut self) -> Result<ControlledPeerDelivery, ControlledDeliveryFault> {
        match std::mem::replace(&mut self.peer, DeliverySlot::Taken) {
            DeliverySlot::Ready(value) => Ok(value),
            DeliverySlot::Taken => Err(ControlledDeliveryFault::Taken),
        }
    }
}
impl ControlledManifestDelivery {
    pub fn into_http_input(self) -> (u64, String) {
        (self.status, self.body)
    }
}
impl ControlledPeerDelivery {
    pub fn into_script_input(self) -> (Vec<String>, Option<Vec<String>>) {
        (self.frames, self.requests)
    }
}

pub struct ControlledHostStimulus {
    manifest_status: u64,
    manifest_byte_limit: u64,
    manifest_body: String,
    peer_alias: String,
    frames: Vec<String>,
    requests: Option<Vec<String>>,
    provider_id: String,
    locator: String,
    project: String,
    attempt: String,
    scope: BrowserScope,
    semantic: BrowserSemantic,
    action: usize,
    opening: ControlledOpening,
    binding: BrowserSourceBinding,
}
pub enum ControlledOpening {
    StartConnected,
    BeginConnectedOpening {
        pending: String,
        inventory_max_entries: u64,
        read_max_bytes: u64,
    },
}
enum OpeningInput<'a> {
    StartConnected,
    BeginConnectedOpening {
        pending: &'a str,
        inventory_max_entries: u64,
        read_max_bytes: u64,
    },
}
impl ControlledHostStimulus {
    pub(super) fn copy_delivery(
        &self,
        loans: &mut BrowserOwnerLoans<'_>,
    ) -> Result<ControlledHostDelivery, BrowserInputFault> {
        loans.ready()?;
        let visits = self.requests.as_ref().map_or(0, Vec::len);
        loans.visits(visits)?;
        let mut comparison = 0usize;
        if let Some(requests) = &self.requests {
            for request in requests {
                comparison = comparison
                    .checked_add(request.len().checked_mul(2).ok_or_else(|| {
                        Self::failure(loans, InstalledObservationFault::SizeOverflow)
                    })?)
                    .ok_or_else(|| Self::failure(loans, InstalledObservationFault::SizeOverflow))?;
            }
        }
        let (_, _, owner) = loans.physical_owners()?;
        use crate::workbench::model_originals::workflow::observation_check::CompareResource;
        owner
            .charge(CompareResource::StructuralVisits, visits)
            .map_err(BrowserInputFault::Comparison)?;
        owner
            .charge(CompareResource::ComparisonBytes, comparison)
            .map_err(BrowserInputFault::Comparison)?;
        Self::storage(loans, std::mem::size_of::<ControlledHostDelivery>(), 1)?;
        let manifest = ControlledManifestDelivery {
            status: self.manifest_status,
            body: Self::copy_text(&self.manifest_body, loans)?,
        };
        fn copy_texts(
            texts: &[String],
            loans: &mut BrowserOwnerLoans<'_>,
        ) -> Result<Vec<String>, BrowserInputFault> {
            loans.ready()?;
            let layout = Layout::array::<String>(texts.len()).map_err(|_| {
                ControlledHostStimulus::failure(loans, InstalledObservationFault::SizeOverflow)
            })?;
            let bytes = layout
                .size()
                .checked_add(std::mem::size_of::<Vec<String>>())
                .ok_or_else(|| {
                    ControlledHostStimulus::failure(loans, InstalledObservationFault::SizeOverflow)
                })?;
            ControlledHostStimulus::storage(loans, bytes, texts.len())?;
            loans.visits(texts.len())?;
            let mut result = Vec::new();
            result.try_reserve_exact(texts.len()).map_err(|_| {
                ControlledHostStimulus::failure(loans, InstalledObservationFault::Allocation)
            })?;
            let excess = result
                .capacity()
                .checked_sub(texts.len())
                .and_then(|count| count.checked_mul(std::mem::size_of::<String>()))
                .ok_or_else(|| {
                    ControlledHostStimulus::failure(
                        loans,
                        InstalledObservationFault::LayoutMismatch,
                    )
                })?;
            ControlledHostStimulus::storage(loans, excess, 0)?;
            for text in texts {
                result.push(ControlledHostStimulus::copy_text(text, loans)?);
            }
            Ok(result)
        }
        let peer = ControlledPeerDelivery {
            frames: copy_texts(&self.frames, loans)?,
            requests: self
                .requests
                .as_ref()
                .map(|requests| copy_texts(requests, loans))
                .transpose()?,
        };
        Ok(ControlledHostDelivery {
            manifest: DeliverySlot::Ready(manifest),
            peer: DeliverySlot::Ready(peer),
        })
    }
    pub(super) fn validate_scope(&self, scope: &BrowserSourceScope) -> Result<(), ScopeFault> {
        self.binding.validate_scope(scope)
    }
    pub(super) fn prepare(
        client: &BrowserClientInput<'_, '_, '_, '_, '_>,
        loans: &mut BrowserOwnerLoans<'_>,
        source_scope: &BrowserSourceScope,
        action_position: usize,
    ) -> Result<Self, BrowserInputFault> {
        loans.ready()?;
        source_scope.ready().map_err(BrowserInputFault::Source)?;
        let opening = client.actions(loans)?.nth(action_position);
        let Some(opening) = opening else {
            return loans.refuse_selection(ClosureError::Missing);
        };
        let (attempt, project_id, scope, semantic, source, opening) = match opening.kind() {
            BrowserActionKind::StartConnected {
                attempt,
                project_id,
                scope,
                semantic,
                source,
            } => (
                attempt,
                project_id,
                match scope {
                    input::ClientActionStartConnectedScope::Primary => BrowserScope::Primary,
                    input::ClientActionStartConnectedScope::Complete => BrowserScope::Complete,
                },
                match semantic {
                    input::ClientActionStartConnectedSemantic::None => BrowserSemantic::None,
                    input::ClientActionStartConnectedSemantic::Projection => {
                        BrowserSemantic::Projection
                    }
                },
                source,
                OpeningInput::StartConnected,
            ),
            BrowserActionKind::BeginConnectedOpening {
                attempt,
                pending,
                project_id,
                scope,
                semantic,
                source,
                transfer_limits,
            } => (
                attempt,
                project_id,
                match scope {
                    input::ClientActionBeginConnectedOpeningScope::Primary => BrowserScope::Primary,
                    input::ClientActionBeginConnectedOpeningScope::Complete => {
                        BrowserScope::Complete
                    }
                },
                match semantic {
                    input::ClientActionBeginConnectedOpeningSemantic::None => BrowserSemantic::None,
                    input::ClientActionBeginConnectedOpeningSemantic::Projection => {
                        BrowserSemantic::Projection
                    }
                },
                source,
                OpeningInput::BeginConnectedOpening {
                    pending: pending.as_str(),
                    inventory_max_entries: transfer_limits.inventory_max_entries.0,
                    read_max_bytes: transfer_limits.read_max_bytes.0,
                },
            ),
            _ => return loans.refuse_selection(ClosureError::Semantic),
        };
        let fixture = client.fixture();
        let BrowserRuntimeInput::ControlledModelOriginalsHttpV1 {
            manifest,
            manifest_byte_limit,
            peer,
        } = fixture.runtime(loans)?
        else {
            return loans.refuse_selection(ClosureError::Semantic);
        };
        let mut selected = None;
        for candidate in fixture.peers(loans)? {
            if loans.same_alias(candidate.alias(), peer)? && selected.replace(candidate).is_some() {
                return loans.refuse_selection(ClosureError::Ambiguous);
            }
        }
        let Some(selected) = selected else {
            return loans.refuse_selection(ClosureError::Missing);
        };
        Self::storage(loans, std::mem::size_of::<Self>(), 1)?;
        let opening = match opening {
            OpeningInput::StartConnected => ControlledOpening::StartConnected,
            OpeningInput::BeginConnectedOpening {
                pending,
                inventory_max_entries,
                read_max_bytes,
            } => ControlledOpening::BeginConnectedOpening {
                pending: Self::copy_text(pending, loans)?,
                inventory_max_entries,
                read_max_bytes,
            },
        };
        let manifest_body = Self::copy_frame(&manifest.body, loans)?;
        let peer_alias = Self::copy_text(peer.as_str(), loans)?;
        let frames = Self::copy_frames(selected.frames(), loans)?;
        let requests = selected
            .requests()
            .map(|requests| Self::copy_frames(requests, loans))
            .transpose()?;
        let provider_id = Self::copy_text(source.provider_id.as_str(), loans)?;
        let locator = Self::copy_text(source.locator.as_str(), loans)?;
        let project = Self::copy_text(project_id.as_str(), loans)?;
        let attempt = Self::copy_text(attempt.as_str(), loans)?;
        // No fallible copy/allocation follows actual debt issuance.
        let binding = source_scope.bind(loans).map_err(|fault| match fault {
            ScopeIssueFault::Input(fault) => fault,
            ScopeIssueFault::Scope(fault) => BrowserInputFault::Source(fault),
        })?;
        Ok(Self {
            manifest_status: manifest.status.0,
            manifest_byte_limit: manifest_byte_limit.0,
            manifest_body,
            peer_alias,
            frames,
            requests,
            provider_id,
            locator,
            project,
            attempt,
            scope,
            semantic,
            opening,
            action: action_position,
            binding,
        })
    }
    fn failure(
        loans: &mut BrowserOwnerLoans<'_>,
        fault: InstalledObservationFault,
    ) -> BrowserInputFault {
        // Callers have checked earliest owner readiness before arithmetic or
        // allocation. The existing receiving owner keeps its first cause.
        match loans.physical_owners() {
            Ok((_, receiving, _)) => BrowserInputFault::Receiving(*receiving.fail(fault)),
            Err(first) => first,
        }
    }
    fn storage(
        loans: &mut BrowserOwnerLoans<'_>,
        bytes: usize,
        slots: usize,
    ) -> Result<(), BrowserInputFault> {
        let (decode, receiving, _) = loans.physical_owners()?;
        decode.slots(slots).map_err(BrowserInputFault::Decode)?;
        receiving
            .reserve_span(InstalledObservationResource::RetainedBytes, bytes)
            .map_err(BrowserInputFault::Receiving)
    }
    fn copy_text(
        text: &str,
        loans: &mut BrowserOwnerLoans<'_>,
    ) -> Result<String, BrowserInputFault> {
        loans.ready()?;
        let requested = std::mem::size_of::<String>()
            .checked_add(text.len())
            .ok_or_else(|| Self::failure(loans, InstalledObservationFault::SizeOverflow))?;
        Self::storage(loans, requested, 1)?;
        let (decode, receiving, _) = loans.physical_owners()?;
        decode
            .bytes(text.len())
            .map_err(BrowserInputFault::Decode)?;
        receiving
            .reserve_span(InstalledObservationResource::ByteVisits, text.len())
            .map_err(BrowserInputFault::Receiving)?;
        let mut result = String::new();
        result
            .try_reserve_exact(text.len())
            .map_err(|_| Self::failure(loans, InstalledObservationFault::Allocation))?;
        let excess = result
            .capacity()
            .checked_sub(text.len())
            .ok_or_else(|| Self::failure(loans, InstalledObservationFault::LayoutMismatch))?;
        Self::storage(loans, excess, 0)?;
        result.push_str(text);
        Ok(result)
    }
    fn copy_frames(
        frames: &[Frame],
        loans: &mut BrowserOwnerLoans<'_>,
    ) -> Result<Vec<String>, BrowserInputFault> {
        loans.ready()?;
        let layout = Layout::array::<String>(frames.len())
            .map_err(|_| Self::failure(loans, InstalledObservationFault::SizeOverflow))?;
        let bytes = std::mem::size_of::<Vec<String>>()
            .checked_add(layout.size())
            .ok_or_else(|| Self::failure(loans, InstalledObservationFault::SizeOverflow))?;
        Self::storage(loans, bytes, frames.len())?;
        loans.visits(frames.len())?;
        let mut result = Vec::new();
        result
            .try_reserve_exact(frames.len())
            .map_err(|_| Self::failure(loans, InstalledObservationFault::Allocation))?;
        let excess = result
            .capacity()
            .checked_sub(frames.len())
            .and_then(|count| count.checked_mul(std::mem::size_of::<String>()))
            .ok_or_else(|| Self::failure(loans, InstalledObservationFault::LayoutMismatch))?;
        Self::storage(loans, excess, 0)?;
        for frame in frames {
            result.push(Self::copy_frame(frame, loans)?);
        }
        Ok(result)
    }
    pub(super) fn copy_frame(
        frame: &Frame,
        loans: &mut BrowserOwnerLoans<'_>,
    ) -> Result<String, BrowserInputFault> {
        loans.ready()?;
        match frame {
            Frame::Literal { text } => Self::copy_text(text.as_str(), loans),
            Frame::Segments { parts } => {
                let visits =
                    parts.0.len().checked_mul(2).ok_or_else(|| {
                        Self::failure(loans, InstalledObservationFault::SizeOverflow)
                    })?;
                loans.visits(visits)?;
                let mut length = 0usize;
                for part in &parts.0 {
                    let (text, count) = match part {
                        FramePart::Literal { text } => (text.as_str(), 1),
                        FramePart::Repeat { text, count } => (
                            text.as_str(),
                            usize::try_from(count.0).map_err(|_| {
                                Self::failure(loans, InstalledObservationFault::SizeOverflow)
                            })?,
                        ),
                    };
                    let bytes = text.len().checked_mul(count).ok_or_else(|| {
                        Self::failure(loans, InstalledObservationFault::SizeOverflow)
                    })?;
                    length = length.checked_add(bytes).ok_or_else(|| {
                        Self::failure(loans, InstalledObservationFault::SizeOverflow)
                    })?;
                    if !text.is_empty() {
                        loans.visits(count)?;
                    }
                }
                let requested = std::mem::size_of::<String>()
                    .checked_add(length)
                    .ok_or_else(|| Self::failure(loans, InstalledObservationFault::SizeOverflow))?;
                Self::storage(loans, requested, 1)?;
                let (decode, receiving, _) = loans.physical_owners()?;
                decode.bytes(length).map_err(BrowserInputFault::Decode)?;
                receiving
                    .reserve_span(InstalledObservationResource::ByteVisits, length)
                    .map_err(BrowserInputFault::Receiving)?;
                let mut result = String::new();
                result
                    .try_reserve_exact(length)
                    .map_err(|_| Self::failure(loans, InstalledObservationFault::Allocation))?;
                let excess = result.capacity().checked_sub(length).ok_or_else(|| {
                    Self::failure(loans, InstalledObservationFault::LayoutMismatch)
                })?;
                Self::storage(loans, excess, 0)?;
                for part in &parts.0 {
                    match part {
                        FramePart::Literal { text } => result.push_str(text.as_str()),
                        FramePart::Repeat { text, count } if !text.as_str().is_empty() => {
                            for _ in 0..count.0 {
                                result.push_str(text.as_str());
                            }
                        }
                        FramePart::Repeat { .. } => {}
                    }
                }
                Ok(result)
            }
        }
    }
    pub fn manifest_status(&self) -> u64 {
        self.manifest_status
    }
    pub fn manifest_byte_limit(&self) -> u64 {
        self.manifest_byte_limit
    }
    pub fn manifest_body(&self) -> &str {
        &self.manifest_body
    }
    pub fn peer_alias(&self) -> &str {
        &self.peer_alias
    }
    pub fn frames(&self) -> &[String] {
        &self.frames
    }
    pub fn requests(&self) -> Option<&[String]> {
        self.requests.as_deref()
    }
    pub fn selected_source(&self) -> BrowserSourceIdentity<'_> {
        BrowserSourceIdentity {
            provider_id: &self.provider_id,
            locator: &self.locator,
        }
    }
    pub fn selected_project(&self) -> &str {
        &self.project
    }
    pub fn opening_attempt(&self) -> &str {
        &self.attempt
    }
    pub fn opening_action(&self) -> usize {
        self.action
    }
    pub fn opening(&self) -> &ControlledOpening {
        &self.opening
    }
    pub fn scope(&self) -> BrowserScope {
        self.scope
    }
    pub fn semantic(&self) -> BrowserSemantic {
        self.semantic
    }
    /// Admission check only, not proof of a send, physical closure or join.
    pub fn admit(&self) -> Result<(), ScopeFault> {
        self.binding.while_active(|| ())
    }
    /// Only synchronous source-lifetime admission. A returned unpolled future
    /// does not attest scheduling or a send. No guard may survive an await.
    pub fn while_source_active<R>(&self, action: impl FnOnce() -> R) -> Result<R, ScopeFault> {
        self.binding.while_active(action)
    }
}
