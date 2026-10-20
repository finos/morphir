//! Borrowed engine-issued invocation and native producer DATA. The CLI owns
//! filesystem/host effects. This module neither links SDK nor grants access.
use super::{UniqueKey, input, native_original, source_compile::CompiledNativeSourceCase};
pub use crate::workbench::configuration::{NativeObservationLimits, RecordRetentionLimits};
pub(super) mod record_retention;
pub use crate::workbench::model_originals::{CaptureScope, FixtureAlias, SemanticRequest};
pub use native_original::NativeDeclarationObservation as NativeOriginalMeasurements;
pub use record_retention::{PrivateRecordAdoption, PrivateRecordError, RecordRetentionUsage};

/// Exact shared DATA definitions. Constructors validate values only; none can
/// create a live invocation, source match, SDK snapshot or cleanup proof.
pub mod data {
    pub use super::super::decode::{DataValueError, Items, Natural, SourcePath, Text, U64Token};
    pub use super::super::domain::Root as DeclarationRoot;
    pub use super::super::input::{
        AtomicBytes, AtomicBytesHexHex, Bytes, BytesHexHex, Count, Frame, FramePart,
    };
    pub use super::super::native_original::{
        DeclaredVersion, EntryCoverage, FileCounts, FileRole, FrozenDeclaration,
        FrozenPrivateRecord, MeasurementProfile, MeasurementVersion, NativeCheckpoint,
        ObservedCount, OriginalRole, ReadCounts, ReadPrefix, ResolvedSelectionData,
        SourceIncomplete, SourceMeasurements, WorkerCounts, WorkerMeasurements,
    };
    pub use super::super::observed::{
        CaptureCoverage, CaptureCoverageCompleteDeclaration, CaptureState,
        CaptureStateClosedCleanup, CapturedEvidence, HarnessTeardown,
        HarnessTeardownConfirmedHeldCoreResults, HarnessTeardownConfirmedPendingEffects,
        HarnessTeardownConfirmedProductReleaseInferred, HarnessTeardownConfirmedStillOwnedWorkers,
        HarnessTeardownFailedProductReleaseInferred, HarnessTeardownFailedReason,
        InventoryEvidence, MeasuredTranscript, MeasuredTranscriptExchangesItem, OfferEvidence,
        ProjectionWitness, ProjectionWitnessUnavailableReason, ResourceEvidence, Root,
        ScenarioOutcome, ScenarioOutcomeIntentionallyRetainedUncertainCleanupReason,
        ScenarioOutcomeIntentionallyRetainedUncertainPhase, SourceHeader, SourceRoles,
    };
    pub use crate::workbench::model_originals::inventory::ContentSha256;
    pub use crate::workbench::model_originals::{
        CaptureId, FixtureAlias, ProjectId, ProviderId, SessionId, SourceIdentity, SourceLocator,
    };
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum NativeAdapterError {
    Startup,
    Fixture,
    Authentication,
    Discovery,
    Selection,
    Exchange,
    ObservationIncomplete,
    Cleanup,
    Cancelled,
    UnsupportedAction,
}
pub trait NativeOriginalAdapter {
    fn observe(
        &mut self,
        run: NativeOriginalRun<'_>,
    ) -> Result<NativeOriginalMeasurements, NativeAdapterError>;
}
/// No public constructor/Clone/Deserialize/Deref. The source compiler's actual
/// match and plan stay borrowed for the entire synchronous callback.
pub struct NativeOriginalRun<'a> {
    compiled: &'a CompiledNativeSourceCase<'a, 'a, 'a, 'a>,
    limits: &'a NativeObservationLimits,
    comparison: &'a mut super::observation_check::CompareOwner,
    records: &'a mut record_retention::RecordRetentionOwner,
}
impl<'a> NativeOriginalRun<'a> {
    pub(super) fn from_compiled(
        compiled: &'a CompiledNativeSourceCase<'a, 'a, 'a, 'a>,
        limits: &'a NativeObservationLimits,
        comparison: &'a mut super::observation_check::CompareOwner,
        records: &'a mut record_retention::RecordRetentionOwner,
    ) -> Self {
        Self {
            compiled,
            limits,
            comparison,
            records,
        }
    }
    pub fn source(&self) -> NativeOriginalSource<'_> {
        NativeOriginalSource {
            compiled: self.compiled,
        }
    }
    pub fn fixture(&self) -> NativeOriginalFixture<'a> {
        NativeOriginalFixture(self.compiled.plan().selected().0)
    }
    pub fn actions(&self) -> impl ExactSizeIterator<Item = NativeOriginalAction<'a>> + use<'a> {
        self.compiled.plan().selected().1.iter().map(action)
    }
    pub fn observation_limits(&self) -> &NativeObservationLimits {
        self.limits
    }
    pub fn private_record_retention_usage(&self) -> RecordRetentionUsage {
        self.records.usage()
    }
    pub fn prepare_private_record_adoption<'ticket>(
        &'ticket mut self,
        actual: &Vec<u8>,
    ) -> Result<PrivateRecordAdoption<'ticket>, &'ticket PrivateRecordError> {
        record_retention::prepare(self.records, self.comparison, actual)
    }
    /// Reuse the same validated Plan/Atom expansion as the factual checker.
    /// The real cumulative comparison owner pays visit and expanded-byte
    /// credits before recipe allocation/copy. This DATA creates no file grant.
    /// The caller owns its destination window and actual filesystem effects.
    pub fn materialize_fixture_bytes(
        &mut self,
        recipe: &data::Bytes,
    ) -> Result<crate::workbench::model_originals::FixtureBytes, NativeAdapterError> {
        self.records
            .ready()
            .map_err(|_| NativeAdapterError::ObservationIncomplete)?;
        super::observation_check::server::recipe(recipe, self.comparison)
            .map_err(|_| NativeAdapterError::Fixture)
    }
}
pub struct NativeOriginalSource<'a> {
    compiled: &'a CompiledNativeSourceCase<'a, 'a, 'a, 'a>,
}
impl NativeOriginalSource<'_> {
    pub fn case_id(&self) -> &str {
        self.compiled.source().case().id()
    }
    pub fn original_packet(&self) -> &str {
        self.compiled.source().input().origin.packet.key()
    }
    pub fn original_id(&self) -> &str {
        &self.compiled.source().input().origin.id.0
    }
    pub fn packet_sha256(&self) -> [u8; 32] {
        self.compiled.source().input().origin.sha256.0
    }
    pub fn run_index(&self) -> usize {
        self.compiled.source().run().get()
    }
    pub fn operation(&self) -> crate::workbench::Operation {
        crate::workbench::Operation::ModelOriginalsServer
    }
    pub fn witnesses(&self) -> NativeOriginalWitnesses {
        NativeOriginalWitnesses(self.compiled.source().witnesses())
    }
}
/// Paths came from the actual verified immutable source manifest, not DATA
/// supplied by the observation or saved report. These paths are not OS grants.
pub struct NativeOriginalWitnesses(native_original::WitnessMetadata);
impl NativeOriginalWitnesses {
    pub fn compile_record(&self) -> &str {
        self.0.record
    }
    pub fn original_primary(&self) -> &str {
        self.0.primary
    }
    pub fn undeclared_sentinel(&self) -> &str {
        self.0.sentinel
    }
    pub fn output_prefix(&self) -> &str {
        self.0.output_prefix
    }
}
pub struct NativeOriginalFixture<'a>(&'a native_original::OriginalHostFixture);
impl NativeOriginalFixture<'_> {
    pub fn grants(&self) -> impl ExactSizeIterator<Item = NativeOriginalGrant<'_>> {
        self.0.grants.0.iter().map(NativeOriginalGrant)
    }
    pub fn providers(&self) -> impl ExactSizeIterator<Item = NativeOriginalProvider<'_>> {
        self.0.providers.0.iter().map(NativeOriginalProvider)
    }
    pub fn records(&self) -> impl ExactSizeIterator<Item = NativeOriginalRecord<'_>> {
        self.0.records.0.iter().map(NativeOriginalRecord)
    }
    pub fn startup(&self) -> NativeOriginalStartup<'_> {
        NativeOriginalStartup(&self.0.startup)
    }
    pub fn guests(&self) -> impl ExactSizeIterator<Item = NativeOriginalGuest<'_>> {
        self.0.guests.0.iter().map(NativeOriginalGuest)
    }
}
pub struct NativeOriginalGrant<'a>(&'a input::HostFixtureGrantsItem);
impl NativeOriginalGrant<'_> {
    pub fn alias(&self) -> &FixtureAlias {
        &self.0.alias
    }
    pub fn nodes(&self) -> impl ExactSizeIterator<Item = NativeOriginalNode<'_>> {
        self.0.nodes.0.iter().map(node)
    }
}
pub enum NativeSeriesEntry<'a> {
    Directory,
    File { bytes: &'a data::AtomicBytes },
}
pub enum NativeOriginalNode<'a> {
    File {
        path: &'a data::SourcePath,
        bytes: &'a data::Bytes,
    },
    Directory {
        path: &'a data::SourcePath,
    },
    Symlink {
        path: &'a data::SourcePath,
        target: &'a str,
    },
    Fifo {
        path: &'a data::SourcePath,
    },
    Socket {
        path: &'a data::SourcePath,
    },
    RawNameFile {
        parent: &'a str,
        name_bytes: &'a data::Bytes,
        bytes: &'a data::Bytes,
    },
    EntrySeries {
        parent: &'a str,
        prefix: &'a str,
        suffix: &'a str,
        first: u64,
        count: u64,
        decimal_width: u64,
        entry: NativeSeriesEntry<'a>,
    },
}
fn node(value: &input::HostNode) -> NativeOriginalNode<'_> {
    match value {
        input::HostNode::File { bytes, path } => NativeOriginalNode::File { path, bytes },
        input::HostNode::Directory { path } => NativeOriginalNode::Directory { path },
        input::HostNode::Symlink { path, target } => NativeOriginalNode::Symlink {
            path,
            target: &target.0,
        },
        input::HostNode::Fifo { path } => NativeOriginalNode::Fifo { path },
        input::HostNode::Socket { path } => NativeOriginalNode::Socket { path },
        input::HostNode::RawNameFile {
            bytes,
            name_bytes,
            parent,
        } => NativeOriginalNode::RawNameFile {
            parent: &parent.0,
            name_bytes,
            bytes,
        },
        input::HostNode::EntrySeries {
            count,
            decimal_width,
            entry,
            first,
            parent,
            prefix,
            suffix,
        } => NativeOriginalNode::EntrySeries {
            parent: &parent.0,
            prefix: &prefix.0,
            suffix: &suffix.0,
            first: first.0,
            count: count.0,
            decimal_width: decimal_width.0,
            entry: match entry {
                input::HostNodeEntrySeriesEntry::Directory {} => NativeSeriesEntry::Directory,
                input::HostNodeEntrySeriesEntry::File { bytes } => {
                    NativeSeriesEntry::File { bytes }
                }
            },
        },
    }
}
pub struct NativeOriginalProvider<'a>(&'a native_original::OriginalProvider);
impl NativeOriginalProvider<'_> {
    pub fn alias(&self) -> &FixtureAlias {
        let native_original::OriginalProvider::Native { alias, .. } = self.0;
        alias
    }
    pub fn grant(&self) -> &FixtureAlias {
        let native_original::OriginalProvider::Native { grant, .. } = self.0;
        grant
    }
    pub fn locator(&self) -> &str {
        let native_original::OriginalProvider::Native { locator, .. } = self.0;
        &locator.0
    }
    pub fn projects(&self) -> impl ExactSizeIterator<Item = NativeOriginalProject<'_>> {
        let native_original::OriginalProvider::Native { projects, .. } = self.0;
        projects.0.iter().map(NativeOriginalProject)
    }
}
pub struct NativeOriginalProject<'a>(&'a input::ProjectBinding);
impl NativeOriginalProject<'_> {
    pub fn alias(&self) -> &FixtureAlias {
        &self.0.alias
    }
    pub fn module(&self) -> &str {
        &self.0.module.0
    }
}
pub struct NativeOriginalRecord<'a>(&'a input::HostFixtureRecordsItem);
impl NativeOriginalRecord<'_> {
    pub fn grant(&self) -> &FixtureAlias {
        &self.0.grant
    }
    pub fn module(&self) -> &str {
        &self.0.module.0
    }
    pub fn raw(&self) -> &data::Frame {
        &self.0.raw
    }
}
pub enum NativeOutputOverride<'a> {
    None,
    Explicit { grant: &'a FixtureAlias },
}
pub struct NativeOriginalStartup<'a>(&'a input::HostFixtureStartup);
impl NativeOriginalStartup<'_> {
    pub fn cwd(&self) -> &FixtureAlias {
        &self.0.cwd
    }
    pub fn output_override(&self) -> NativeOutputOverride<'_> {
        match &self.0.output_override {
            input::HostFixtureStartupOutputOverride::None {} => NativeOutputOverride::None,
            input::HostFixtureStartupOutputOverride::Explicit { grant } => {
                NativeOutputOverride::Explicit { grant }
            }
        }
    }
}
pub enum NativeGuestFrame<'a> {
    Literal(&'a str),
    Frame(&'a data::Frame),
}
fn guest_frame(value: &input::RawJsonSource) -> NativeGuestFrame<'_> {
    match value {
        input::RawJsonSource::String(value) => NativeGuestFrame::Literal(&value.0),
        input::RawJsonSource::Object(value) => NativeGuestFrame::Frame(value),
    }
}
pub struct NativeOriginalGuest<'a>(&'a input::Guest);
impl NativeOriginalGuest<'_> {
    pub fn alias(&self) -> &FixtureAlias {
        &self.0.alias
    }
    pub fn initialize(&self) -> NativeGuestFrame<'_> {
        guest_frame(&self.0.initialize)
    }
    pub fn answers(&self) -> NativeGuestFrame<'_> {
        guest_frame(&self.0.answers)
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum NativeAuthentication {
    Valid,
    Missing,
    WrongToken,
    ForeignOrigin,
    ForeignHost,
}
pub enum NativeReadTarget<'a> {
    OriginalEntry { path: &'a data::SourcePath },
    SemanticProjection,
}
pub enum NativeOriginalAction<'a> {
    Connect {
        authentication: NativeAuthentication,
        connection: &'a FixtureAlias,
    },
    Discover {
        connection: &'a FixtureAlias,
        provider: &'a FixtureAlias,
    },
    CaptureSelected {
        attempt: &'a FixtureAlias,
        capture: &'a FixtureAlias,
        connection: &'a FixtureAlias,
        project: &'a FixtureAlias,
        provider: &'a FixtureAlias,
        request_id: u64,
        scope: CaptureScope,
        semantic: SemanticRequest,
    },
    Checkpoint {
        name: &'a FixtureAlias,
    },
    Inventory {
        capture: &'a FixtureAlias,
        connection: &'a FixtureAlias,
        request_id: u64,
        start_index: u64,
        max_entries: u64,
    },
    ReadSelected {
        capture: &'a FixtureAlias,
        connection: &'a FixtureAlias,
        request_id: u64,
        target: NativeReadTarget<'a>,
        offset: u64,
        max_bytes: u64,
    },
    Release {
        capture: &'a FixtureAlias,
        connection: &'a FixtureAlias,
        request_id: u64,
    },
    Disconnect {
        connection: &'a FixtureAlias,
    },
    Unsupported(NativeUnsupportedAction<'a>),
}
pub struct NativeUnsupportedAction<'a>(&'a input::HostAction);
impl NativeUnsupportedAction<'_> {
    pub fn kind(&self) -> NativeUnsupportedKind {
        unsupported_kind(self.0)
    }
}
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum NativeUnsupportedKind {
    Send,
    Hold,
    Continue,
    AdvanceDeadline,
    RemoveProvider,
    ReofferSameLabels,
    ReplaceProject,
    ReplaceOutput,
    StartCooperatingCompile,
    AwaitCooperatingCompile,
    UncooperativeWrite,
    BeginCaptureSelected,
    AwaitCapture,
    HoldCooperatingCompile,
    ContinueCooperatingCompile,
    OpenLegacySelected,
    ProducerMessageBoundary,
    AwaitBoundary,
}
fn unsupported_kind(value: &input::HostAction) -> NativeUnsupportedKind {
    match value {
        input::HostAction::Send { .. } => NativeUnsupportedKind::Send,
        input::HostAction::Hold { .. } => NativeUnsupportedKind::Hold,
        input::HostAction::Continue { .. } => NativeUnsupportedKind::Continue,
        input::HostAction::AdvanceDeadline { .. } => NativeUnsupportedKind::AdvanceDeadline,
        input::HostAction::RemoveProvider { .. } => NativeUnsupportedKind::RemoveProvider,
        input::HostAction::ReofferSameLabels { .. } => NativeUnsupportedKind::ReofferSameLabels,
        input::HostAction::ReplaceProject { .. } => NativeUnsupportedKind::ReplaceProject,
        input::HostAction::ReplaceOutput { .. } => NativeUnsupportedKind::ReplaceOutput,
        input::HostAction::StartCooperatingCompile { .. } => {
            NativeUnsupportedKind::StartCooperatingCompile
        }
        input::HostAction::AwaitCooperatingCompile { .. } => {
            NativeUnsupportedKind::AwaitCooperatingCompile
        }
        input::HostAction::UncooperativeWrite { .. } => NativeUnsupportedKind::UncooperativeWrite,
        input::HostAction::BeginCaptureSelected { .. } => {
            NativeUnsupportedKind::BeginCaptureSelected
        }
        input::HostAction::AwaitCapture { .. } => NativeUnsupportedKind::AwaitCapture,
        input::HostAction::HoldCooperatingCompile { .. } => {
            NativeUnsupportedKind::HoldCooperatingCompile
        }
        input::HostAction::ContinueCooperatingCompile { .. } => {
            NativeUnsupportedKind::ContinueCooperatingCompile
        }
        input::HostAction::OpenLegacySelected { .. } => NativeUnsupportedKind::OpenLegacySelected,
        input::HostAction::ProducerMessageBoundary { .. } => {
            NativeUnsupportedKind::ProducerMessageBoundary
        }
        input::HostAction::AwaitBoundary(_) => NativeUnsupportedKind::AwaitBoundary,
        // This function is reached only by the closed unsupported match below.
        input::HostAction::Connect { .. }
        | input::HostAction::Discover { .. }
        | input::HostAction::CaptureSelected { .. }
        | input::HostAction::Checkpoint { .. }
        | input::HostAction::Inventory { .. }
        | input::HostAction::ReadSelected { .. }
        | input::HostAction::Release { .. }
        | input::HostAction::Disconnect { .. } => {
            unreachable!("supported action is never wrapped as unsupported")
        }
    }
}
fn action(value: &input::HostAction) -> NativeOriginalAction<'_> {
    match value {
        input::HostAction::Connect {
            authentication,
            connection,
        } => NativeOriginalAction::Connect {
            authentication: match authentication {
                input::HostActionConnectAuthentication::Valid => NativeAuthentication::Valid,
                input::HostActionConnectAuthentication::Missing => NativeAuthentication::Missing,
                input::HostActionConnectAuthentication::WrongToken => {
                    NativeAuthentication::WrongToken
                }
                input::HostActionConnectAuthentication::ForeignOrigin => {
                    NativeAuthentication::ForeignOrigin
                }
                input::HostActionConnectAuthentication::ForeignHost => {
                    NativeAuthentication::ForeignHost
                }
            },
            connection,
        },
        input::HostAction::Discover {
            connection,
            provider,
        } => NativeOriginalAction::Discover {
            connection,
            provider,
        },
        input::HostAction::CaptureSelected {
            attempt,
            capture,
            connection,
            project,
            provider,
            request_id,
            scope,
            semantic,
        } => NativeOriginalAction::CaptureSelected {
            attempt,
            capture,
            connection,
            project,
            provider,
            request_id: request_id.0.get(),
            scope: match scope {
                input::HostActionCaptureSelectedScope::Complete => CaptureScope::Complete,
                input::HostActionCaptureSelectedScope::Primary => CaptureScope::Primary,
            },
            semantic: match semantic {
                input::HostActionCaptureSelectedSemantic::None => SemanticRequest::None,
                input::HostActionCaptureSelectedSemantic::Projection => SemanticRequest::Projection,
            },
        },
        input::HostAction::Checkpoint { name } => NativeOriginalAction::Checkpoint { name },
        input::HostAction::Inventory {
            capture,
            connection,
            max_entries,
            request_id,
            start_index,
        } => NativeOriginalAction::Inventory {
            capture,
            connection,
            max_entries: max_entries.0,
            request_id: request_id.0.get(),
            start_index: start_index.0,
        },
        input::HostAction::ReadSelected {
            capture,
            connection,
            max_bytes,
            offset,
            request_id,
            target,
        } => NativeOriginalAction::ReadSelected {
            capture,
            connection,
            max_bytes: max_bytes.0,
            offset: offset.0,
            request_id: request_id.0.get(),
            target: match target {
                input::HostActionReadSelectedTarget::OriginalEntry { path } => {
                    NativeReadTarget::OriginalEntry { path }
                }
                input::HostActionReadSelectedTarget::SemanticProjection {} => {
                    NativeReadTarget::SemanticProjection
                }
            },
        },
        input::HostAction::Release {
            capture,
            connection,
            request_id,
        } => NativeOriginalAction::Release {
            capture,
            connection,
            request_id: request_id.0.get(),
        },
        input::HostAction::Disconnect { connection } => {
            NativeOriginalAction::Disconnect { connection }
        }
        other => NativeOriginalAction::Unsupported(NativeUnsupportedAction(other)),
    }
}

#[cfg(test)]
#[path = "native_record_retention_metadata_controls.rs"]
mod retention_metadata_tests;
