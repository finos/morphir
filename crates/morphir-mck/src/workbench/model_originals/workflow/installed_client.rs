//! Reviewed compiler DATA only. No process, filesystem or runtime grants.
use super::compile::CompileError;
use super::expansion::ExpansionOwner;
use super::pairing::PairedWorkflow;
use super::source_compile::CompilationError;
use super::source_proof::SourceError;
use super::work::{ClosureError, ClosureOwner, Resource};
use super::*;
use crate::json::strict::Document;

pub(super) const CASE: &str = "single-file-explicit-companion-preserves-opaque-bytes";
pub(super) const PATH: &str = "installed-client-first-v1/materialization.json";
pub(super) const SHA: &str = "92e2711ac430a12bd5a2e98e8ea22fcf48e28f090c3cd1837f5729c513509009";

literal! { MaterializationKind => "installed-client-action-materialization" }
literal! { ClientRole => "model-originals-client" }
literal! { Unobserved => "unobserved" }
words! { PublicationObservation { PostExitSnapshotsOnly => "post-exit-snapshots-only" } }
words! { OriginalPointer {
    FirstFile => "/expected/modelOriginalFiles/0",
    SecondFile => "/expected/modelOriginalFiles/1",
    CompanionPath => "/expected/companion/path",
    CompanionLength => "/expected/companion/byteLength",
    CompanionDigest => "/expected/companion/sha256",
    Unrelated => "/expected/unrelatedIncluded",
} }
words! { Command { Connect => "connect", List => "list", Publish => "publish" } }
tagged! { Action("kind") {
    Prepare => "prepare-reviewed-fixture" {},
    Host => "start-observed-native-host" {},
    Run => "run-installed-command" {
        command: Command => "command",
        arguments: Items<Text<0, {usize::MAX}>, 0, {usize::MAX}> => "arguments",
    },
    Checkpoint => "checkpoint" { name: Text<1, {usize::MAX}> => "name" },
    Source => "write-source-selection" {},
    Project => "write-project-selection" {},
    Stop => "stop-and-join-owned-resources" {},
} }
impl Action {
    pub(super) fn tag(&self) -> &'static str {
        match self {
            Self::Prepare {} => "prepare-reviewed-fixture",
            Self::Host {} => "start-observed-native-host",
            Self::Run { .. } => "run-installed-command",
            Self::Checkpoint { .. } => "checkpoint",
            Self::Source {} => "write-source-selection",
            Self::Project {} => "write-project-selection",
            Self::Stop {} => "stop-and-join-owned-resources",
        }
    }
    pub(super) fn checkpoint_name(&self) -> Option<&str> {
        match self {
            Self::Checkpoint { name } => Some(name.as_str()),
            _ => None,
        }
    }
}
tagged! { FixtureNode("kind") {
    Literal => "literal" { path: SourcePath => "path", bytes: input::Bytes => "bytes" },
    ByteSource => "byte-source" { path: SourcePath => "path", source: FixtureAlias => "source" },
} }
record! { Fixture {
    module: SourcePath => "module",
    primary: FixtureAlias => "primaryByteSource",
    opaque: FixtureAlias => "opaqueByteSource",
    record: FixtureAlias => "recordByteSource",
    nodes: Items<FixtureNode, 0, {usize::MAX}> => "nodes",
} }
record! { Draft {
    kind: MaterializationKind => "kind",
    origin: input::PacketRef => "origin",
    role: ClientRole => "role",
    run: Natural<0, 0> => "runIndex",
    input_path: SourcePath => "inputPath",
    input_sha: ContentSha256 => "inputSHA256",
    expected_path: SourcePath => "expectedPath",
    expected_sha: ContentSha256 => "expectedSHA256",
    pointers: Items<OriginalPointer, 6, 6> => "originalLeafPointers",
    fixture: Fixture => "fixture",
    actions: Items<Action, 12, 12> => "actions",
    publication: PublicationObservation => "publicationObservation",
    commit: Unobserved => "dynamicCommitObservation",
    cleanup: Unobserved => "dynamicScratchCleanupObservation",
    release: Unobserved => "releaseAcceptanceObservation",
} }
record! { OriginalCompanion {
    path: SourcePath => "path",
    length: Natural<0, {u64::MAX}> => "byteLength",
    sha: ContentSha256 => "sha256",
} }
record! { OriginalExpectation {
    files: Items<SourcePath, 0, {usize::MAX}> => "modelOriginalFiles",
    companion: OriginalCompanion => "companion",
    unrelated: JsonBool => "unrelatedIncluded",
} }

/// Credit retained strings before the existing Decode implementations copy.
/// Document is temporary at this boundary, never the retained domain model.
pub(super) fn copy_credit(doc: &Document, owner: &mut Decoder) -> Result<(), DecodeError> {
    owner.ready()?;
    match doc {
        Document::String(value) => owner.bytes(value.len()),
        Document::Array(values) => {
            for value in values {
                copy_credit(value, owner)?;
            }
            Ok(())
        }
        Document::Object(fields) => {
            for (_, value) in fields {
                copy_credit(value, owner)?;
            }
            Ok(())
        }
        _ => Ok(()),
    }
}

/// One authenticated sidecar plus values decoded from the authenticated
/// ORIGINAL packet. Sidecar has pointer roles, never expected scalar values.
pub(super) struct ReviewedMaterialization {
    // Sole constructor establishes exactly one; no public mutation/constructor.
    payload: Vec<MaterializationPayload>,
}
struct MaterializationPayload {
    draft: Draft,
    original: OriginalExpectation,
}
impl ReviewedMaterialization {
    fn payload(&self) -> &MaterializationPayload {
        &self.payload[0]
    }
    pub(super) fn decode(
        draft: &Document,
        original: OriginalExpectation,
        owner: &mut Decoder,
    ) -> Result<Self, SourceError> {
        copy_credit(draft, owner)?;
        let draft = Draft::decode(draft, owner)?;
        let wanted = [
            OriginalPointer::FirstFile,
            OriginalPointer::SecondFile,
            OriginalPointer::CompanionPath,
            OriginalPointer::CompanionLength,
            OriginalPointer::CompanionDigest,
            OriginalPointer::Unrelated,
        ];
        for (actual, wanted) in draft.pointers.0.iter().zip(wanted) {
            owner.bytes(actual.key().len().saturating_add(wanted.key().len()))?;
            if actual != &wanted {
                return Err(SourceError::Shape("original pointer role/order"));
            }
        }
        // The six reviewed roles include first/second paths, but retain the
        // ENTIRE original container for later exact set/cardinality comparison.
        if original.files.0.len() < 2 {
            return Err(SourceError::Shape("original file pointer"));
        }
        owner.slots(1)?;
        let mut payload = Vec::new();
        payload
            .try_reserve_exact(1)
            .map_err(|_| DecodeError::Allocation)?;
        payload.push(MaterializationPayload { draft, original });
        Ok(Self { payload })
    }
    pub(super) fn bind(
        &self,
        origin: &input::PacketRef,
        input_sha: ContentSha256,
        expected_sha: ContentSha256,
        input_path: &str,
        expected_path: &str,
        owner: &mut Decoder,
    ) -> Result<(), SourceError> {
        let draft = &self.payload().draft;
        for (a, b) in [
            (draft.origin.packet.key(), origin.packet.key()),
            (draft.origin.id.0.as_str(), origin.id.0.as_str()),
            (draft.input_path.as_str(), input_path),
            (draft.expected_path.as_str(), expected_path),
        ] {
            owner.bytes(a.len().saturating_add(b.len()))?;
            if a != b {
                return Err(SourceError::ManifestCase);
            }
        }
        owner.bytes(192)?;
        if draft.origin.sha256 != origin.sha256
            || draft.input_sha != input_sha
            || draft.expected_sha != expected_sha
        {
            return Err(SourceError::ManifestCase);
        }
        Ok(())
    }
}

pub(super) enum OriginalClientLeafValue<'a> {
    Path(&'a SourcePath),
    ByteLength(u64),
    Sha256(ContentSha256),
    Included(bool),
}
pub(super) struct OriginalClientLeafBinding<'a> {
    pointer: &'static str,
    value: OriginalClientLeafValue<'a>,
}
impl OriginalClientLeafBinding<'_> {
    pub(super) fn source_pointer(&self) -> &'static str {
        self.pointer
    }
    pub(super) fn value(&self) -> OriginalClientLeafValue<'_> {
        match self.value {
            OriginalClientLeafValue::Path(v) => OriginalClientLeafValue::Path(v),
            OriginalClientLeafValue::ByteLength(v) => OriginalClientLeafValue::ByteLength(v),
            OriginalClientLeafValue::Sha256(v) => OriginalClientLeafValue::Sha256(v),
            OriginalClientLeafValue::Included(v) => OriginalClientLeafValue::Included(v),
        }
    }
}
pub(super) struct InstalledClientPlan<'a> {
    reviewed: ReviewedMaterialization,
    // Real old expected byte-source operands, not copied/decoded substitutes.
    byte_sources: Vec<&'a domain::ExpectedByteSource>,
    file_sources: Vec<&'a domain::ExpectedByteSource>,
}
fn closure(error: ClosureError) -> CompilationError {
    CompilationError::Closure(CompileError::Owner(error))
}
impl<'a> InstalledClientPlan<'a> {
    pub(super) fn compile(
        reviewed: ReviewedMaterialization,
        paired: &PairedWorkflow<'a>,
        owner: &mut ClosureOwner,
        expansion: &mut ExpansionOwner,
    ) -> Result<Self, CompilationError> {
        owner.ready().map_err(closure)?;
        expansion.ready().map_err(CompilationError::Expansion)?;
        let domain::ExpectedWorkflow::ModelOriginalsClient { byte_sources, .. } = paired.expected()
        else {
            return Err(CompilationError::Source(SourceError::ManifestRole));
        };
        let mut resolved = Vec::new();
        let draft = &reviewed.payload().draft;
        let wanted = [
            &draft.fixture.primary,
            &draft.fixture.opaque,
            &draft.fixture.record,
        ];
        for alias in wanted
            .into_iter()
            .chain(draft.fixture.nodes.0.iter().filter_map(|node| match node {
                FixtureNode::ByteSource { source, .. } => Some(source),
                _ => None,
            }))
        {
            owner.charge(Resource::References, 1).map_err(closure)?;
            let mut found = None;
            for candidate in &byte_sources.0 {
                if owner.same_alias(alias, &candidate.alias).map_err(closure)? {
                    if found.is_some() {
                        return Err(closure(ClosureError::Ambiguous));
                    }
                    found = Some(candidate);
                }
            }
            let candidate = found.ok_or_else(|| closure(ClosureError::Missing))?;
            owner.reserve(&mut resolved).map_err(closure)?;
            resolved.push(candidate);
        }
        for node in &draft.fixture.nodes.0 {
            owner
                .charge(Resource::StructuralVisits, 1)
                .map_err(closure)?;
            if let FixtureNode::Literal { bytes, .. } = node {
                expansion
                    .measure_materialization_bytes(bytes)
                    .map_err(CompilationError::Expansion)?;
            }
        }
        for action in &draft.actions.0 {
            owner
                .charge(Resource::StructuralVisits, 1)
                .map_err(closure)?;
            if let Action::Run { arguments, .. } = action {
                for argument in &arguments.0 {
                    owner
                        .charge(Resource::StructuralVisits, 1)
                        .map_err(closure)?;
                    owner
                        .charge(Resource::LookupBytes, argument.0.len())
                        .map_err(closure)?;
                }
            }
        }
        let mut file_sources = Vec::new();
        for path in &reviewed.payload().original.files.0 {
            let mut found = None;
            for node in &draft.fixture.nodes.0 {
                owner
                    .charge(Resource::StructuralVisits, 1)
                    .map_err(closure)?;
                if let FixtureNode::ByteSource {
                    path: physical,
                    source,
                } = node
                {
                    owner
                        .charge(
                            Resource::LookupBytes,
                            physical.as_str().len().saturating_add(path.as_str().len()),
                        )
                        .map_err(closure)?;
                    if physical
                        .as_str()
                        .split_once("/compile.dest/")
                        .map(|(_, suffix)| suffix)
                        == Some(path.as_str())
                    {
                        if found.is_some() {
                            return Err(closure(ClosureError::Ambiguous));
                        }
                        for candidate in &resolved {
                            if owner
                                .same_alias(source, &candidate.alias)
                                .map_err(closure)?
                            {
                                found = Some(*candidate);
                                break;
                            }
                        }
                    }
                }
            }
            let source = found.ok_or_else(|| closure(ClosureError::Missing))?;
            owner.reserve(&mut file_sources).map_err(closure)?;
            file_sources.push(source);
        }
        Ok(Self {
            reviewed,
            byte_sources: resolved,
            file_sources,
        })
    }
    pub(super) fn actions(&self) -> impl Iterator<Item = &Action> {
        self.reviewed.payload().draft.actions.0.iter()
    }
    pub(super) fn files(&self) -> impl ExactSizeIterator<Item = (&SourcePath, &domain::Bytes)> {
        self.reviewed
            .payload()
            .original
            .files
            .0
            .iter()
            .zip(&self.file_sources)
            .map(|(path, source)| (path, &source.bytes))
    }
    pub(super) fn record_bytes(&self) -> &domain::Bytes {
        &self.byte_sources[2].bytes
    }
    pub(super) fn companion(&self) -> &OriginalCompanion {
        &self.reviewed.payload().original.companion
    }
    pub(super) fn module(&self) -> &str {
        self.reviewed.payload().draft.fixture.module.as_str()
    }
    pub(super) fn publication(&self) -> PublicationObservation {
        match self.reviewed.payload().draft.publication {
            PublicationObservation::PostExitSnapshotsOnly => {
                PublicationObservation::PostExitSnapshotsOnly
            }
        }
    }
    pub(super) fn leaves(&self) -> impl Iterator<Item = OriginalClientLeafBinding<'_>> {
        let original = &self.reviewed.payload().original;
        [
            OriginalClientLeafBinding {
                pointer: "/expected/modelOriginalFiles/0",
                value: OriginalClientLeafValue::Path(&original.files.0[0]),
            },
            OriginalClientLeafBinding {
                pointer: "/expected/modelOriginalFiles/1",
                value: OriginalClientLeafValue::Path(&original.files.0[1]),
            },
            OriginalClientLeafBinding {
                pointer: "/expected/companion/path",
                value: OriginalClientLeafValue::Path(&original.companion.path),
            },
            OriginalClientLeafBinding {
                pointer: "/expected/companion/byteLength",
                value: OriginalClientLeafValue::ByteLength(original.companion.length.0),
            },
            OriginalClientLeafBinding {
                pointer: "/expected/companion/sha256",
                value: OriginalClientLeafValue::Sha256(original.companion.sha),
            },
            OriginalClientLeafBinding {
                pointer: "/expected/unrelatedIncluded",
                value: OriginalClientLeafValue::Included(original.unrelated.0),
            },
        ]
        .into_iter()
    }
}
