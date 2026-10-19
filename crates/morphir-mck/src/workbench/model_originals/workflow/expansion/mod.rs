//! Input recipes and real read-run planning before materialization or effects.
//! These explicit compiler limits are independent of scenario claims and host
//! authority. Read-plan work uses the genuine peer-read formula. Observed host
//! work, paths and alias closure remain separate compilation obligations.
//! No physical RSS or complete CPU claim.
use super::{Presence, input};
use crate::workbench::model_originals::fixture_bytes;
mod reads;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(super) enum ExpansionResource {
    RecipeBytes,
    FrameBytes,
    LiteralStorageBytes,
    Entries,
    Visits,
    ReadRows,
    ReadWindowBytes,
    ReadWireBytes,
    ReadObserverBytes,
}
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(super) enum ExpansionError {
    Resource(ExpansionResource),
    Arithmetic(ExpansionResource),
    Hex,
    ReadPlan(crate::workbench::model_originals::PeerReadError),
    ReadSourceMissing,
    ReadSourceAmbiguous,
}
#[derive(Clone, Copy)]
enum Storage {
    LiteralDestination,
    CompactPattern,
}
/// Exact aggregate recipe output, frame output, conservative literal destination
/// bytes, generated entries, and structural visits. Pattern sources stay compact.
/// This is not a mapping of the scenario's unfinished aggregate metric contract.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub(super) struct ExpansionUsage {
    recipe_bytes: u64,
    frame_bytes: u64,
    literal_storage_bytes: u64,
    entries: u64,
    visits: u64,
    read_rows: u64,
    read_window_bytes: u64,
    read_wire_bytes: u64,
    read_observer_bytes: u64,
}
impl ExpansionUsage {
    pub(super) fn amount(self, resource: ExpansionResource) -> u64 {
        match resource {
            ExpansionResource::RecipeBytes => self.recipe_bytes,
            ExpansionResource::FrameBytes => self.frame_bytes,
            ExpansionResource::LiteralStorageBytes => self.literal_storage_bytes,
            ExpansionResource::Entries => self.entries,
            ExpansionResource::Visits => self.visits,
            ExpansionResource::ReadRows => self.read_rows,
            ExpansionResource::ReadWindowBytes => self.read_window_bytes,
            ExpansionResource::ReadWireBytes => self.read_wire_bytes,
            ExpansionResource::ReadObserverBytes => self.read_observer_bytes,
        }
    }
    fn slot(&mut self, resource: ExpansionResource) -> &mut u64 {
        match resource {
            ExpansionResource::RecipeBytes => &mut self.recipe_bytes,
            ExpansionResource::FrameBytes => &mut self.frame_bytes,
            ExpansionResource::LiteralStorageBytes => &mut self.literal_storage_bytes,
            ExpansionResource::Entries => &mut self.entries,
            ExpansionResource::Visits => &mut self.visits,
            ExpansionResource::ReadRows => &mut self.read_rows,
            ExpansionResource::ReadWindowBytes => &mut self.read_window_bytes,
            ExpansionResource::ReadWireBytes => &mut self.read_wire_bytes,
            ExpansionResource::ReadObserverBytes => &mut self.read_observer_bytes,
        }
    }
    fn since(self, earlier: Self) -> Self {
        Self {
            recipe_bytes: self.recipe_bytes - earlier.recipe_bytes,
            frame_bytes: self.frame_bytes - earlier.frame_bytes,
            literal_storage_bytes: self.literal_storage_bytes - earlier.literal_storage_bytes,
            entries: self.entries - earlier.entries,
            visits: self.visits - earlier.visits,
            read_rows: self.read_rows - earlier.read_rows,
            read_window_bytes: self.read_window_bytes - earlier.read_window_bytes,
            read_wire_bytes: self.read_wire_bytes - earlier.read_wire_bytes,
            read_observer_bytes: self.read_observer_bytes - earlier.read_observer_bytes,
        }
    }
}
pub(super) struct ExpansionLimits(ExpansionUsage);
pub(super) struct ReadExpansionLimits {
    rows: u64,
    window_bytes: u64,
    wire_bytes: u64,
    observer_bytes: u64,
}
impl ReadExpansionLimits {
    pub(super) fn new(rows: u64, window_bytes: u64, wire_bytes: u64, observer_bytes: u64) -> Self {
        Self {
            rows,
            window_bytes,
            wire_bytes,
            observer_bytes,
        }
    }
}
impl ExpansionLimits {
    /// Explicit static boundary policy. Zero refuses any use of that resource.
    /// All read-run work is denied until with_reads supplies its own policy.
    pub(super) fn new(
        recipe_bytes: u64,
        frame_bytes: u64,
        literal_storage_bytes: u64,
        entries: u64,
        visits: u64,
    ) -> Self {
        Self(ExpansionUsage {
            recipe_bytes,
            frame_bytes,
            literal_storage_bytes,
            entries,
            visits,
            ..ExpansionUsage::default()
        })
    }
    pub(super) fn with_reads(mut self, limits: ReadExpansionLimits) -> Self {
        self.0.read_rows = limits.rows;
        self.0.read_window_bytes = limits.window_bytes;
        self.0.read_wire_bytes = limits.wire_bytes;
        self.0.read_observer_bytes = limits.observer_bytes;
        self
    }
}
/// One cumulative, non-clone owner. Never reset between runs or nested recipes.
pub(super) struct ExpansionOwner {
    limits: ExpansionLimits,
    used: ExpansionUsage,
    fault: Option<ExpansionError>,
}
impl ExpansionOwner {
    pub(super) fn new(limits: ExpansionLimits) -> Self {
        Self {
            limits,
            used: ExpansionUsage::default(),
            fault: None,
        }
    }
    pub(super) fn usage(&self) -> ExpansionUsage {
        self.used
    }
    pub(super) fn ready(&self) -> Result<(), ExpansionError> {
        self.fault.map_or(Ok(()), Err)
    }
    fn refuse<T>(&mut self, fault: ExpansionError) -> Result<T, ExpansionError> {
        let first = *self.fault.get_or_insert(fault);
        Err(first)
    }
    fn charge(&mut self, resource: ExpansionResource, amount: u64) -> Result<(), ExpansionError> {
        self.ready()?;
        let Some(next) = self.used.amount(resource).checked_add(amount) else {
            return self.refuse(ExpansionError::Arithmetic(resource));
        };
        if next > self.limits.0.amount(resource) {
            return self.refuse(ExpansionError::Resource(resource));
        }
        *self.used.slot(resource) = next;
        Ok(())
    }
    fn scaled(
        &mut self,
        resource: ExpansionResource,
        amount: u64,
        copies: u64,
    ) -> Result<(), ExpansionError> {
        self.ready()?;
        let Some(total) = amount.checked_mul(copies) else {
            return self.refuse(ExpansionError::Arithmetic(resource));
        };
        self.charge(resource, total)
    }
    fn visit(&mut self) -> Result<(), ExpansionError> {
        self.charge(ExpansionResource::Visits, 1)
    }
    fn payload(&mut self, bytes: u64, copies: u64, storage: Storage) -> Result<(), ExpansionError> {
        self.scaled(ExpansionResource::RecipeBytes, bytes, copies)?;
        match storage {
            Storage::LiteralDestination => {
                self.scaled(ExpansionResource::LiteralStorageBytes, bytes, copies)?
            }
            Storage::CompactPattern => {}
        }
        Ok(())
    }
    fn hex(&mut self, text: &str, copies: u64) -> Result<(), ExpansionError> {
        // The AST has already established lowercase even hex. Reuse the real
        // fixture parser's exact validator, without constructing a byte buffer.
        let length = match fixture_bytes::hex_byte_length(text) {
            Ok(length) => length,
            Err(_) => return self.refuse(ExpansionError::Hex),
        };
        self.payload(length as u64, copies, Storage::LiteralDestination)
    }
    fn atomic(&mut self, recipe: &input::AtomicBytes, copies: u64) -> Result<(), ExpansionError> {
        self.visit()?;
        match recipe {
            input::AtomicBytes::Hex { hex } => self.hex(hex.as_str(), copies),
            input::AtomicBytes::Utf8 { text } => {
                self.payload(text.0.len() as u64, copies, Storage::LiteralDestination)
            }
            input::AtomicBytes::RepeatU8 { length, .. }
            | input::AtomicBytes::CycleU8 { length, .. }
            | input::AtomicBytes::ChunkIndexedU8 { length, .. } => {
                self.payload(length.0, copies, Storage::CompactPattern)
            }
        }
    }
    fn bytes(&mut self, recipe: &input::Bytes) -> Result<(), ExpansionError> {
        self.visit()?;
        match recipe {
            input::Bytes::Hex { hex } => self.hex(hex.as_str(), 1),
            input::Bytes::Utf8 { text } => {
                self.payload(text.0.len() as u64, 1, Storage::LiteralDestination)
            }
            input::Bytes::RepeatU8 { length, .. }
            | input::Bytes::CycleU8 { length, .. }
            | input::Bytes::ChunkIndexedU8 { length, .. } => {
                self.payload(length.0, 1, Storage::CompactPattern)
            }
            input::Bytes::Concat { parts } => {
                for part in &parts.0 {
                    self.atomic(part, 1)?;
                }
                Ok(())
            }
        }
    }
    fn frame_piece(&mut self, text: &str, copies: u64) -> Result<(), ExpansionError> {
        self.payload(text.len() as u64, copies, Storage::LiteralDestination)?;
        self.scaled(ExpansionResource::FrameBytes, text.len() as u64, copies)
    }
    fn frame(&mut self, frame: &input::Frame) -> Result<(), ExpansionError> {
        self.visit()?;
        match frame {
            input::Frame::Literal { text } => self.frame_piece(&text.0, 1),
            input::Frame::Segments { parts } => {
                for part in &parts.0 {
                    self.visit()?;
                    match part {
                        input::FramePart::Literal { text } => self.frame_piece(&text.0, 1)?,
                        input::FramePart::Repeat { count, text } => {
                            self.frame_piece(&text.0, count.0)?
                        }
                    }
                }
                Ok(())
            }
        }
    }
    fn raw(&mut self, raw: &input::RawJsonSource) -> Result<(), ExpansionError> {
        self.visit()?;
        match raw {
            input::RawJsonSource::String(raw) => {
                self.payload(raw.0.len() as u64, 1, Storage::LiteralDestination)
            }
            input::RawJsonSource::Object(frame) => self.frame(frame),
        }
    }
    fn entry(&mut self, entry: &input::Entry) -> Result<(), ExpansionError> {
        self.visit()?;
        self.charge(ExpansionResource::Entries, 1)?;
        match entry {
            input::Entry::File { bytes, .. } => self.bytes(bytes),
            input::Entry::Directory { .. } => Ok(()),
        }
    }
    fn node(&mut self, node: &input::HostNode) -> Result<(), ExpansionError> {
        self.visit()?;
        match node {
            input::HostNode::File { bytes, .. } => {
                self.charge(ExpansionResource::Entries, 1)?;
                self.bytes(bytes)
            }
            input::HostNode::RawNameFile {
                bytes, name_bytes, ..
            } => {
                self.charge(ExpansionResource::Entries, 1)?;
                self.bytes(name_bytes)?;
                self.bytes(bytes)
            }
            input::HostNode::EntrySeries { count, entry, .. } => {
                self.charge(ExpansionResource::Entries, count.0)?;
                match entry {
                    input::HostNodeEntrySeriesEntry::File { bytes } => self.atomic(bytes, count.0),
                    input::HostNodeEntrySeriesEntry::Directory {} => Ok(()),
                }
            }
            input::HostNode::Directory { .. }
            | input::HostNode::Symlink { .. }
            | input::HostNode::Fifo { .. }
            | input::HostNode::Socket { .. } => self.charge(ExpansionResource::Entries, 1),
        }
    }
    fn host(
        &mut self,
        fixture: &input::HostFixture,
        actions: &[input::HostAction],
    ) -> Result<(), ExpansionError> {
        for grant in &fixture.grants.0 {
            self.visit()?;
            for node in &grant.nodes.0 {
                self.node(node)?;
            }
        }
        for record in &fixture.records.0 {
            self.visit()?;
            self.frame(&record.raw)?;
        }
        for guest in &fixture.guests.0 {
            self.visit()?;
            self.raw(&guest.initialize)?;
            self.raw(&guest.answers)?;
        }
        for action in actions {
            self.visit()?;
            match action {
                input::HostAction::Send { frame, .. }
                | input::HostAction::ProducerMessageBoundary { frame, .. } => self.frame(frame)?,
                input::HostAction::StartCooperatingCompile {
                    next_entries,
                    next_record,
                    ..
                } => {
                    for entry in &next_entries.0 {
                        self.entry(entry)?;
                    }
                    self.frame(next_record)?;
                }
                input::HostAction::UncooperativeWrite { entry, .. } => self.entry(entry)?,
                input::HostAction::Connect { .. }
                | input::HostAction::Discover { .. }
                | input::HostAction::CaptureSelected { .. }
                | input::HostAction::Inventory { .. }
                | input::HostAction::ReadSelected { .. }
                | input::HostAction::Release { .. }
                | input::HostAction::Hold { .. }
                | input::HostAction::Continue { .. }
                | input::HostAction::Disconnect { .. }
                | input::HostAction::AdvanceDeadline { .. }
                | input::HostAction::RemoveProvider { .. }
                | input::HostAction::ReofferSameLabels { .. }
                | input::HostAction::ReplaceProject { .. }
                | input::HostAction::ReplaceOutput { .. }
                | input::HostAction::AwaitCooperatingCompile { .. }
                | input::HostAction::Checkpoint { .. }
                | input::HostAction::BeginCaptureSelected { .. }
                | input::HostAction::AwaitCapture { .. }
                | input::HostAction::HoldCooperatingCompile { .. }
                | input::HostAction::ContinueCooperatingCompile { .. }
                | input::HostAction::OpenLegacySelected { .. }
                | input::HostAction::AwaitBoundary(_) => {}
            }
        }
        Ok(())
    }
    fn client(
        &mut self,
        fixture: &input::ClientFixture,
        actions: &[input::ClientAction],
    ) -> Result<(), ExpansionError> {
        for file in &fixture.files.0 {
            self.visit()?;
            self.charge(ExpansionResource::Entries, 1)?;
            self.bytes(&file.bytes)?;
        }
        for peer in &fixture.literal_peers.0 {
            self.visit()?;
            for frame in &peer.frames.0 {
                self.frame(frame)?;
            }
            if let Presence::Present(requests) = &peer.requests {
                for frame in &requests.0 {
                    self.frame(frame)?;
                }
            }
        }
        if let input::ClientFixtureMode::Runtime { runtime } = &fixture.mode {
            self.visit()?;
            match runtime {
                input::ClientRuntime::ControlledModelOriginalsHttpV1 { manifest, .. } => {
                    self.frame(&manifest.body)?
                }
                input::ClientRuntime::ControlledHttpExecutions { .. }
                | input::ClientRuntime::ControlledNativeWorkspaceV1 { .. } => {}
            }
        }
        if let input::ClientFixtureMode::IdentityController { controller } = &fixture.mode {
            self.visit()?;
            for _source in &controller.initial_sources.0 {
                self.visit()?;
            }
            for peer in &controller.providers.0 {
                self.visit()?;
                for replies in [&peer.inspections.0, &peer.workspaces.0] {
                    for reply in replies {
                        self.visit()?;
                        // Same static literal destination role as existing raw replies.
                        // This does not claim actual UI parse/copy/watch work coverage.
                        self.payload(reply.reply.0.len() as u64, 1, Storage::LiteralDestination)?;
                    }
                }
            }
        }
        for action in actions {
            self.visit()?;
            match action {
                input::ClientAction::Deliver { reply, .. } => match reply {
                    input::DeliveredReply::Frame { value } => self.frame(value)?,
                    input::DeliveredReply::Bytes { value } => self.bytes(value)?,
                    input::DeliveredReply::Json { source, .. }
                    | input::DeliveredReply::Text { source, .. } => self.raw(source)?,
                    input::DeliveredReply::Sha256 { .. }
                    | input::DeliveredReply::FileSelection { .. }
                    | input::DeliveredReply::PickerCancelled {}
                    | input::DeliveredReply::Void { .. } => {}
                },
                input::ClientAction::MutateCaller { replacement, .. } => {
                    self.payload(
                        replacement.project_id.0.len() as u64,
                        1,
                        Storage::LiteralDestination,
                    )?;
                    self.payload(
                        replacement.source.0.len() as u64,
                        1,
                        Storage::LiteralDestination,
                    )?;
                }
                input::ClientAction::SubmitExecution { arguments, .. } => self.raw(arguments)?,
                input::ClientAction::BeginLocalEvaluation { arguments, .. } => {
                    self.payload(arguments.0.len() as u64, 1, Storage::LiteralDestination)?
                }
                input::ClientAction::ReadRun {
                    source,
                    first_ordinal,
                    window,
                    reply_parts,
                    effect_kind,
                    expected_request,
                    ..
                } => reads::measure(
                    self,
                    fixture,
                    reads::ReadRunInput {
                        source,
                        first_ordinal: first_ordinal.0,
                        window,
                        parts: &reply_parts.0,
                        effect_kind,
                        expected: expected_request,
                    },
                )?,
                // No byte/frame recipe here. Actual UI snapshot/key/result work
                // remains a separate producer/observer precharge obligation.
                input::ClientAction::ObserveIdentity { .. }
                | input::ClientAction::InitializeExecutionRuntime { .. }
                | input::ClientAction::StartImport { .. }
                | input::ClientAction::StartConnected { .. }
                | input::ClientAction::BindModelOwner { .. }
                | input::ClientAction::ExecutePendingCore { .. }
                | input::ClientAction::PreparePendingCore { .. }
                | input::ClientAction::SettlePreparedCore { .. }
                | input::ClientAction::Reject { .. }
                | input::ClientAction::SignalPicker { .. }
                | input::ClientAction::CancelOpening { .. }
                | input::ClientAction::Inspect { .. }
                | input::ClientAction::Search { .. }
                | input::ClientAction::ConceptualSpecification { .. }
                | input::ClientAction::DownloadOriginal { .. }
                | input::ClientAction::DownloadArchive { .. }
                | input::ClientAction::CloseModel { .. }
                | input::ClientAction::CloseCurrentModel {}
                | input::ClientAction::ReplaceModel { .. }
                | input::ClientAction::ReleaseExecution { .. }
                | input::ClientAction::Checkpoint { .. }
                | input::ClientAction::SelectCurrentDeclaration { .. }
                | input::ClientAction::SearchCurrent { .. }
                | input::ClientAction::AwaitLocalEvaluation { .. }
                | input::ClientAction::BeginNativeInitialize { .. }
                | input::ClientAction::BeginNativeChoose { .. }
                | input::ClientAction::AwaitNativeBoundary { .. }
                | input::ClientAction::BindNativeProject { .. }
                | input::ClientAction::BeginNativeOpenProject { .. }
                | input::ClientAction::DisposeNativeRuntime { .. }
                | input::ClientAction::AwaitNativeDisposal { .. }
                | input::ClientAction::BeginConnectedOpening { .. }
                | input::ClientAction::AwaitConnectedBoundary { .. }
                | input::ClientAction::DisposeConnectedOpening { .. }
                | input::ClientAction::AwaitConnectedDisposal { .. } => {}
            }
        }
        Ok(())
    }
}
/// Static recipes in every run passed this owner's explicit limits. No runtime
/// handle, trusted provenance, path confinement or effect authority is implied.
pub(super) struct ScenarioExpansion<'a> {
    scenario: &'a input::Scenario,
    usage: ExpansionUsage,
}
impl<'a> ScenarioExpansion<'a> {
    pub(super) fn measure(
        scenario: &'a input::Scenario,
        owner: &mut ExpansionOwner,
    ) -> Result<Self, ExpansionError> {
        owner.ready()?;
        let before = owner.usage();
        for run in &scenario.runs.0 {
            owner.visit()?;
            match run {
                input::Run::ModelOriginalsServer { fixture, actions } => {
                    owner.host(fixture, &actions.0)?
                }
                input::Run::ModelOriginalsClient { fixture, actions } => {
                    owner.client(fixture, &actions.0)?
                }
            }
        }
        Ok(Self {
            scenario,
            usage: owner.usage().since(before),
        })
    }
    pub(super) fn usage(&self) -> ExpansionUsage {
        self.usage
    }
    pub(super) fn scenario(&self) -> &'a input::Scenario {
        self.scenario
    }
}
#[cfg(test)]
mod tests;
