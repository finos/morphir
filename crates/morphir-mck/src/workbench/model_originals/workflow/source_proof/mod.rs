//! Correspondence to the parent-selected reviewed source bytes only.
//!
//! This does not verify semantic expectation leaves, complete 175-role coverage,
//! producer authority, filesystem grants, readiness or any runtime observation.
use super::ingress::{BoundCase, CorpusCaseId, IngressError};
use super::pairing::{PairError, PairedRun, PairedWorkflow};
use super::reviewed_sources::{FileView, ReviewedSources, SourceSet};
use super::{
    ContentSha256, Decode, DecodeError, DecodeUsage, Decoder, Natural, Text, UniqueKey, input,
    string,
};
use crate::json::strict::Document;
use sha2::{Digest, Sha256};

const ACCEPTANCE_SHA: &str = "d25d47fb7a75c4212b7055d5acbf6afd43f1499e6d54febc85bc1746c1ee2482";
const PAIRED_SHA: &str = "dcbdaf9e76f99be9e537dad40ac930fa1455742bdfbb3e684c5aa7158888c034";
const MANIFEST_SHA: &str = "c9d550c9e4b4833f8c52880ae6f836b5cf7239444d307f31ea9f78f65afe0e17";

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(super) enum ReviewedAnchor {
    Acceptance,
    PairedReceipt,
    Manifest,
}
#[derive(Debug)]
pub(super) enum SourceError {
    Inventory,
    Decode(DecodeError),
    Pair(PairError),
    Ingress(IngressError),
    Anchor(ReviewedAnchor),
    PacketDigest,
    MissingOriginalCase,
    ManifestCase,
    ManifestRole,
    MissingManifestCase,
    DuplicateManifestCase,
    SourceFileDigest,
    InputToken,
    ExpectedToken,
    UnreviewedPacket,
    MissingFile,
    Utf8,
    SizeOverflow,
    Shape(&'static str),
}
impl From<DecodeError> for SourceError {
    fn from(error: DecodeError) -> Self {
        Self::Decode(error)
    }
}
fn pairing_error(error: IngressError) -> SourceError {
    match error {
        IngressError::Decode(error) => SourceError::Decode(error),
        IngressError::Pair(error) => SourceError::Pair(error),
        error => SourceError::Ingress(error),
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(super) enum LineageStatus {
    Unproven,
}

struct OriginalPacket {
    key: input::PacketRefPacket,
    digest: ContentSha256,
    cases: Vec<OriginalCaseId>,
}
/// Exactly the existing PacketRef.id boundary policy, without the IR kit's
/// unrelated topic-and-number grammar or a new source string restriction.
struct OriginalCaseId(Text<0, 256>);
impl OriginalCaseId {
    fn as_str(&self) -> &str {
        &self.0.0
    }
    fn decode(document: &Document, owner: &mut Decoder) -> Result<Self, SourceError> {
        copy_credit(document, owner)?;
        Ok(Self(Text::<0, 256>::decode(document, owner)?))
    }
}

#[derive(Clone, Copy, PartialEq, Eq)]
enum WorkflowRole {
    Server,
    Client,
}
impl WorkflowRole {
    fn decode(document: &Document, owner: &mut Decoder) -> Result<Self, SourceError> {
        match text(document, owner)? {
            "model-originals-server" => Ok(Self::Server),
            "model-originals-client" => Ok(Self::Client),
            _ => Err(SourceError::Shape("existing workflow role")),
        }
    }
    fn of(run: PairedRun<'_>) -> Self {
        match run {
            PairedRun::Server { .. } => Self::Server,
            PairedRun::Client { .. } => Self::Client,
        }
    }
}

/// This is an authenticated declaration plus a real issued byte view. Its
/// bytes are deliberately not hash-verified until the bind reaches this role.
struct DeclaredOperandFile<'sources> {
    view: FileView<'sources>,
    digest: ContentSha256,
    byte_length: Natural<0, { u64::MAX }>,
}
struct VerifiedOperandToken<'sources> {
    raw: &'sources str,
}
struct ManifestCase<'sources> {
    id: CorpusCaseId,
    origin: input::PacketRef,
    run_index: Natural<0, 1>,
    role: WorkflowRole,
    input: DeclaredOperandFile<'sources>,
    expected: DeclaredOperandFile<'sources>,
    native_witnesses: Option<super::native_original::WitnessMetadata>,
}
pub(super) struct MatchedNativeSourceCase<'case, 'sources, 'raw, 'supplied> {
    case: &'case BoundCase<'raw>,
    _sources: &'sources ReviewedSources<'supplied>,
    input: &'case super::native_original::OriginalScenario,
    expected: &'case super::native_original::NativeDeclarationExpectation,
    run: super::native_original::ValidatedRunIndex,
    witnesses: super::native_original::WitnessMetadata,
}
impl<'case, 'raw> MatchedNativeSourceCase<'case, '_, 'raw, '_> {
    pub(super) fn case(&self) -> &'case BoundCase<'raw> {
        self.case
    }
    pub(super) fn input(&self) -> &'case super::native_original::OriginalScenario {
        self.input
    }
    pub(super) fn expected(&self) -> &'case super::native_original::NativeDeclarationExpectation {
        self.expected
    }
    pub(super) fn run(&self) -> super::native_original::ValidatedRunIndex {
        self.run
    }
    pub(super) fn witnesses(&self) -> super::native_original::WitnessMetadata {
        self.witnesses
    }
}
pub(super) struct SourceVerifier<'owner, 'sources, 'supplied> {
    owner: &'owner mut Decoder,
    sources: &'sources ReviewedSources<'supplied>,
    packets: Vec<OriginalPacket>,
    original_cases: usize,
    manifest: Vec<ManifestCase<'sources>>,
}

/// Only this module can issue a match. Keep both immutable owners borrowed.
pub(super) struct MatchedSourceCase<'case, 'sources, 'raw, 'supplied> {
    case: &'case BoundCase<'raw>,
    _sources: &'sources ReviewedSources<'supplied>,
    paired: PairedWorkflow<'case>,
}
impl<'case, 'raw> MatchedSourceCase<'case, '_, 'raw, '_> {
    pub(super) fn case(&self) -> &'case BoundCase<'raw> {
        self.case
    }
    pub(super) fn lineage(&self) -> LineageStatus {
        LineageStatus::Unproven
    }
    pub(super) fn paired(&self) -> &PairedWorkflow<'case> {
        &self.paired
    }
}

fn same(left: &str, right: &str, owner: &mut Decoder) -> Result<bool, SourceError> {
    owner.bytes(left.len().saturating_add(right.len()))?;
    Ok(left == right)
}
fn member<'doc>(
    document: &'doc Document,
    name: &str,
    owner: &mut Decoder,
) -> Result<&'doc Document, SourceError> {
    owner.ready()?;
    let Document::Object(fields) = document else {
        return Err(SourceError::Shape("source object"));
    };
    for (key, value) in fields {
        if same(key, name, owner)? {
            return Ok(value);
        }
    }
    Err(SourceError::Shape("required source field"))
}
fn optional_member<'doc>(
    document: &'doc Document,
    name: &str,
    owner: &mut Decoder,
) -> Result<Option<&'doc Document>, SourceError> {
    let Document::Object(fields) = document else {
        return Err(SourceError::Shape("source object"));
    };
    for (key, value) in fields {
        if same(key, name, owner)? {
            return Ok(Some(value));
        }
    }
    Ok(None)
}
fn items<'doc>(
    document: &'doc Document,
    owner: &mut Decoder,
) -> Result<&'doc [Document], SourceError> {
    owner.ready()?;
    match document {
        Document::Array(items) => Ok(items),
        _ => Err(SourceError::Shape("source array")),
    }
}
fn text<'doc>(document: &'doc Document, owner: &mut Decoder) -> Result<&'doc str, SourceError> {
    string(document, owner).map_err(SourceError::Decode)
}
fn copy_credit(document: &Document, owner: &mut Decoder) -> Result<(), SourceError> {
    owner.ready()?;
    let Document::String(text) = document else {
        return Err(SourceError::Shape("owned source text"));
    };
    owner.bytes(text.len())?;
    Ok(())
}
fn decoded_digest(document: &Document, owner: &mut Decoder) -> Result<ContentSha256, SourceError> {
    copy_credit(document, owner)?;
    ContentSha256::decode(document, owner).map_err(SourceError::Decode)
}
fn source_text<'source>(
    bytes: &'source [u8],
    owner: &mut Decoder,
) -> Result<&'source str, SourceError> {
    owner.bytes(bytes.len())?;
    std::str::from_utf8(bytes).map_err(|_| SourceError::Utf8)
}
fn hash_matches(bytes: &[u8], expected: &str, owner: &mut Decoder) -> Result<bool, SourceError> {
    // Hash input reads and the fixed 64-byte hexadecimal result are protected
    // before the genuine existing helper. This is logical work, not RSS.
    let visits = bytes
        .len()
        .checked_add(64)
        .ok_or(SourceError::SizeOverflow)?;
    owner.bytes(visits)?;
    owner.slots(1)?;
    let actual = crate::kit::hash::sha256_hex(bytes);
    same(&actual, expected, owner)
}
fn anchor(
    bytes: &[u8],
    expected: &str,
    kind: ReviewedAnchor,
    owner: &mut Decoder,
) -> Result<(), SourceError> {
    if hash_matches(bytes, expected, owner)? {
        Ok(())
    } else {
        Err(SourceError::Anchor(kind))
    }
}
fn source_document(bytes: &[u8], owner: &mut Decoder) -> Result<Document, SourceError> {
    let raw = source_text(bytes, owner)?;
    let (document, _) = owner.literal_with_raw(raw)?;
    Ok(document)
}
fn file<'sources, 'supplied>(
    sources: &'sources ReviewedSources<'supplied>,
    path: &str,
    owner: &mut Decoder,
) -> Result<FileView<'sources>, SourceError> {
    owner.ready()?;
    for view in sources.files() {
        if same(view.path(), path, owner)? {
            return Ok(view);
        }
    }
    Err(SourceError::MissingFile)
}

/// Existing wire packet names map only to the actual receipt's originalFile
/// names. Source paths, digests, counts and all case data come from that receipt.
fn original_file(key: &input::PacketRefPacket) -> Option<&'static str> {
    match key {
        input::PacketRefPacket::Original60 => Some("acceptance-scenarios.json"),
        input::PacketRefPacket::Inventory35 => Some("acceptance-additions-2026-10-18.json"),
        input::PacketRefPacket::Wire49 => Some("wire-cases-2026-10-18.json"),
        input::PacketRefPacket::Discovery7 => Some("discovery-seven.json"),
        input::PacketRefPacket::Additive => None,
    }
}
fn receipt_entry<'doc>(
    receipt: &'doc Document,
    key: &input::PacketRefPacket,
    owner: &mut Decoder,
) -> Result<&'doc Document, SourceError> {
    let wanted = original_file(key).ok_or(SourceError::UnreviewedPacket)?;
    let rows = items(member(receipt, "files", owner)?, owner)?;
    let mut found = None;
    for row in rows {
        let original = text(member(row, "originalFile", owner)?, owner)?;
        if same(original, wanted, owner)? {
            if found.is_some() {
                return Err(SourceError::Shape("unique original receipt entry"));
            }
            found = Some(row);
        }
    }
    found.ok_or(SourceError::UnreviewedPacket)
}
fn case_id<'doc>(document: &'doc Document, owner: &mut Decoder) -> Result<&'doc str, SourceError> {
    text(member(document, "id", owner)?, owner)
}
fn decode_original_cases(
    document: &Document,
    owner: &mut Decoder,
) -> Result<Vec<OriginalCaseId>, SourceError> {
    let rows = items(member(document, "cases", owner)?, owner)?;
    owner.slots(rows.len())?;
    let mut result: Vec<OriginalCaseId> = Vec::new();
    result
        .try_reserve_exact(rows.len())
        .map_err(|_| DecodeError::Allocation)?;
    for row in rows {
        let id = OriginalCaseId::decode(member(row, "id", owner)?, owner)?;
        for previous in &result {
            if same(id.as_str(), previous.as_str(), owner)? {
                return Err(SourceError::Shape("unique original case id"));
            }
        }
        result.push(id);
    }
    Ok(result)
}
fn decoded_manifest<'sources, 'supplied>(
    document: &Document,
    sources: &'sources ReviewedSources<'supplied>,
    owner: &mut Decoder,
) -> Result<Vec<ManifestCase<'sources>>, SourceError> {
    let rows = items(document, owner)?;
    owner.slots(rows.len())?;
    let mut result: Vec<ManifestCase<'sources>> = Vec::new();
    result
        .try_reserve_exact(rows.len())
        .map_err(|_| DecodeError::Allocation)?;
    for row in rows {
        let source = member(row, "source", owner)?;
        let id = CorpusCaseId::parse(case_id(source, owner)?, owner).map_err(pairing_error)?;
        for previous in &result {
            if same(id.as_str(), previous.id.as_str(), owner)? {
                return Err(SourceError::DuplicateManifestCase);
            }
        }
        let origin_document = member(row, "origin", owner)?;
        copy_credit(member(origin_document, "id", owner)?, owner)?;
        copy_credit(member(origin_document, "sha256", owner)?, owner)?;
        let origin = input::PacketRef::decode(origin_document, owner)?;
        let run_index = Natural::<0, 1>::decode(member(row, "runIndex", owner)?, owner)?;
        let role = WorkflowRole::decode(member(row, "role", owner)?, owner)?;
        let input = DeclaredOperandFile::decode(
            sources,
            row,
            source,
            "inputPath",
            "inputSHA256",
            "inputBytes",
            owner,
        )?;
        let expected = DeclaredOperandFile::decode(
            sources,
            row,
            source,
            "expectedPath",
            "expectedSHA256",
            "expectedBytes",
            owner,
        )?;
        let native_witnesses = match optional_member(row, "dialect", owner)? {
            None => None,
            Some(dialect) => {
                if !same(text(dialect, owner)?, "original-native-declaration", owner)? {
                    return Err(SourceError::Shape("closed source dialect"));
                }
                let run = usize::try_from(run_index.0).map_err(|_| SourceError::SizeOverflow)?;
                let metadata = super::native_original::first_witness_metadata(&origin, run)
                    .ok_or(SourceError::ManifestCase)?;
                let fields = member(row, "witnessMetadata", owner)?;
                for (key, expected) in [
                    ("grant", "workspace"),
                    ("outputPrefix", metadata.output_prefix),
                    ("compileRecord", metadata.record),
                    ("primary", metadata.primary),
                    ("sentinel", metadata.sentinel),
                ] {
                    if !same(text(member(fields, key, owner)?, owner)?, expected, owner)? {
                        return Err(SourceError::ManifestCase);
                    }
                }
                Some(metadata)
            }
        };
        result.push(ManifestCase {
            id,
            origin,
            run_index,
            role,
            input,
            expected,
            native_witnesses,
        });
    }
    Ok(result)
}
fn contains_original(
    cases: &[OriginalCaseId],
    id: &str,
    owner: &mut Decoder,
) -> Result<bool, SourceError> {
    for case in cases {
        if same(case.as_str(), id, owner)? {
            return Ok(true);
        }
    }
    Ok(false)
}
fn manifest_case<'case, 'sources>(
    cases: &'case [ManifestCase<'sources>],
    id: &str,
    owner: &mut Decoder,
) -> Result<&'case ManifestCase<'sources>, SourceError> {
    for row in cases {
        if same(row.id.as_str(), id, owner)? {
            return Ok(row);
        }
    }
    Err(SourceError::MissingManifestCase)
}

impl<'owner, 'sources, 'supplied> SourceVerifier<'owner, 'sources, 'supplied> {
    pub(super) fn new(
        sources: &'sources ReviewedSources<'supplied>,
        owner: &'owner mut Decoder,
    ) -> Result<Self, SourceError> {
        owner.ready()?;
        // The closed parent-issued view selects only fixed reviewed anchors.
        // Caller/replacement bytes never supply an expected digest.
        let (paired_sha, manifest_sha) = match sources.source_set() {
            SourceSet::Legacy => (PAIRED_SHA, MANIFEST_SHA),
            SourceSet::IdentityController => (
                "ff6a905d4c25c590190353d119fd34ca774e2b7cbb258448df902f6f1bb3815c",
                "79056ac33aac8aec8191790250e7d60bc9934bff97ed09b11e06ce7b2368c602",
            ),
            SourceSet::NativeFirst => (
                "e3d3ca84be11068fa75da61c8e295bccd3eae927e3e6cb820e3347302db7f96e",
                "949be1c5e3551ccfb977e03d0dee6769bae0db6c17a4e5296b71dfa1934ab62b",
            ),
        };
        anchor(
            sources.acceptance_receipt(),
            ACCEPTANCE_SHA,
            ReviewedAnchor::Acceptance,
            owner,
        )?;
        anchor(
            sources.paired_receipt(),
            paired_sha,
            ReviewedAnchor::PairedReceipt,
            owner,
        )?;
        anchor(
            sources.manifest(),
            manifest_sha,
            ReviewedAnchor::Manifest,
            owner,
        )?;
        let receipt = source_document(sources.acceptance_receipt(), owner)?;
        let paired = source_document(sources.paired_receipt(), owner)?;
        if !same(
            text(member(&paired, "sourceManifestSHA256", owner)?, owner)?,
            manifest_sha,
            owner,
        )? {
            return Err(SourceError::Anchor(ReviewedAnchor::Manifest));
        }
        let manifest_document = source_document(sources.manifest(), owner)?;
        let manifest = decoded_manifest(&manifest_document, sources, owner)?;
        owner.slots(4)?;
        let mut packets = Vec::new();
        packets
            .try_reserve_exact(4)
            .map_err(|_| DecodeError::Allocation)?;
        let mut original_cases = 0usize;
        for key in [
            input::PacketRefPacket::Original60,
            input::PacketRefPacket::Inventory35,
            input::PacketRefPacket::Wire49,
            input::PacketRefPacket::Discovery7,
        ] {
            let entry = receipt_entry(&receipt, &key, owner)?;
            let path = text(member(entry, "path", owner)?, owner)?;
            let expected_hash = text(member(entry, "sha256", owner)?, owner)?;
            let view = file(sources, path, owner)?;
            let bytes = view.bytes();
            if !hash_matches(bytes, expected_hash, owner)? {
                return Err(SourceError::PacketDigest);
            }
            let digest = decoded_digest(member(entry, "sha256", owner)?, owner)?;
            let document = source_document(bytes, owner)?;
            let cases = decode_original_cases(&document, owner)?;
            let actual = cases.len();
            let declared =
                Natural::<0, { u64::MAX }>::decode(member(entry, "cases", owner)?, owner)?.0;
            if u64::try_from(actual).map_err(|_| SourceError::SizeOverflow)? != declared {
                return Err(SourceError::Shape("original case count"));
            }
            original_cases = original_cases
                .checked_add(actual)
                .ok_or(SourceError::SizeOverflow)?;
            packets.push(OriginalPacket { key, digest, cases });
        }
        Ok(Self {
            owner,
            sources,
            packets,
            original_cases,
            manifest,
        })
    }
    /// Ordered manifest metadata only. Each bind still verifies genuine source
    /// input/expected bytes, original packet, role and selected run separately.
    pub(super) fn require_inventory(&mut self, cases: &[BoundCase<'_>]) -> Result<(), SourceError> {
        self.owner.ready()?;
        if cases.len() != self.manifest.len() {
            return Err(SourceError::Inventory);
        }
        for (case, row) in cases.iter().zip(&self.manifest) {
            if !same(case.id(), row.id.as_str(), self.owner)? {
                return Err(SourceError::Inventory);
            }
        }
        Ok(())
    }
    pub(super) fn packet_count(&self) -> usize {
        self.packets.len()
    }
    pub(super) fn original_case_count(&self) -> usize {
        self.original_cases
    }
    pub(super) fn ready(&self) -> Result<(), DecodeError> {
        self.owner.ready()
    }
    pub(super) fn usage(&self) -> DecodeUsage {
        self.owner.usage()
    }
    pub(super) fn bind<'case, 'raw>(
        &mut self,
        case: &'case BoundCase<'raw>,
    ) -> Result<MatchedSourceCase<'case, 'sources, 'raw, 'supplied>, SourceError> {
        self.owner.ready()?;
        let paired = case.paired_with_work(self.owner).map_err(pairing_error)?;
        let origin = &paired.scenario().origin;
        let row = self.bind_tokens(
            case,
            origin,
            paired.run_index(),
            WorkflowRole::of(paired.run()),
        )?;
        if row.native_witnesses.is_some() {
            return Err(SourceError::ManifestRole);
        }
        Ok(MatchedSourceCase {
            case,
            _sources: self.sources,
            paired,
        })
    }
    /// Both dialects use this one actual source/packet/token authority check.
    fn bind_tokens(
        &mut self,
        case: &BoundCase<'_>,
        origin: &input::PacketRef,
        run_index: usize,
        role: WorkflowRole,
    ) -> Result<&ManifestCase<'sources>, SourceError> {
        let packet = self
            .packets
            .iter()
            .find(|packet| packet.key == origin.packet)
            .ok_or(SourceError::UnreviewedPacket)?;
        self.owner.bytes(64)?;
        if packet.digest != origin.sha256 {
            return Err(SourceError::PacketDigest);
        }
        if !contains_original(&packet.cases, &origin.id.0, self.owner)? {
            return Err(SourceError::MissingOriginalCase);
        }
        let row = manifest_case(&self.manifest, case.id(), self.owner)?;
        let source_origin = &row.origin;
        let same_packet = same(source_origin.packet.key(), origin.packet.key(), self.owner)?;
        let same_id = same(&source_origin.id.0, &origin.id.0, self.owner)?;
        self.owner.bytes(64)?;
        if !same_packet || !same_id || source_origin.sha256 != origin.sha256 {
            return Err(SourceError::ManifestCase);
        }
        let run = row.run_index.0;
        if usize::try_from(run).map_err(|_| SourceError::SizeOverflow)? != run_index {
            return Err(SourceError::ManifestCase);
        }
        if row.role != role {
            return Err(SourceError::ManifestRole);
        }
        let input = row.input.verify(self.owner)?;
        if !same(input.raw, case.input_token(), self.owner)? {
            return Err(SourceError::InputToken);
        }
        let expected = row.expected.verify(self.owner)?;
        if !same(expected.raw, case.expected_token(), self.owner)? {
            return Err(SourceError::ExpectedToken);
        }
        Ok(row)
    }
    pub(super) fn bind_native<'case, 'raw>(
        &mut self,
        case: &'case BoundCase<'raw>,
    ) -> Result<MatchedNativeSourceCase<'case, 'sources, 'raw, 'supplied>, SourceError> {
        self.owner.ready()?;
        let (input, expected) = case.native_operands().ok_or(SourceError::ManifestRole)?;
        if !same(
            input.origin.packet.key(),
            expected.origin.packet.key(),
            self.owner,
        )? {
            return Err(SourceError::Pair(PairError::Packet));
        }
        self.owner.bytes(64)?;
        if input.origin.sha256 != expected.origin.sha256 {
            return Err(SourceError::Pair(PairError::Digest));
        }
        if !same(&input.origin.id.0, &expected.origin.id.0, self.owner)? {
            return Err(SourceError::Pair(PairError::Case));
        }
        let row = manifest_case(&self.manifest, case.id(), self.owner)?;
        let index = usize::try_from(row.run_index.0).map_err(|_| SourceError::SizeOverflow)?;
        let row = self.bind_tokens(case, &input.origin, index, WorkflowRole::Server)?;
        let witnesses = row.native_witnesses.ok_or(SourceError::ManifestRole)?;
        let run = super::native_original::ValidatedRunIndex::for_original(input, index)
            .map_err(|_| SourceError::Pair(PairError::RunIndex))?;
        Ok(MatchedNativeSourceCase {
            case,
            _sources: self.sources,
            input,
            expected,
            run,
            witnesses,
        })
    }
}

impl<'sources> DeclaredOperandFile<'sources> {
    fn decode<'supplied>(
        sources: &'sources ReviewedSources<'supplied>,
        row: &Document,
        source: &Document,
        path_field: &str,
        hash_field: &str,
        length_field: &str,
        owner: &mut Decoder,
    ) -> Result<Self, SourceError> {
        let path = text(member(source, path_field, owner)?, owner)?;
        let view = file(sources, path, owner)?;
        let digest = decoded_digest(member(source, hash_field, owner)?, owner)?;
        let byte_length =
            Natural::<0, { u64::MAX }>::decode(member(row, length_field, owner)?, owner)?;
        Ok(Self {
            view,
            digest,
            byte_length,
        })
    }

    fn verify(&self, owner: &mut Decoder) -> Result<VerifiedOperandToken<'sources>, SourceError> {
        owner.ready()?;
        let bytes = self.view.bytes();
        if u64::try_from(bytes.len()).map_err(|_| SourceError::SizeOverflow)? != self.byte_length.0
        {
            return Err(SourceError::SourceFileDigest);
        }
        // Typed digest avoids retaining a second hexadecimal string or running
        // a text hash codec during bind. Use the same existing SHA-256 engine;
        // protect its input and fixed 32-byte result before the real call.
        owner.bytes(
            bytes
                .len()
                .checked_add(32)
                .ok_or(SourceError::SizeOverflow)?,
        )?;
        let actual = ContentSha256(Sha256::digest(bytes).into());
        owner.bytes(64)?;
        if actual != self.digest {
            return Err(SourceError::SourceFileDigest);
        }
        // Full standalone-file identity precedes exact token derivation.
        let raw = source_text(bytes, owner)?;
        let (_, token) = owner.literal_with_raw(raw)?;
        Ok(VerifiedOperandToken { raw: token.get() })
    }
}

#[cfg(test)]
mod tests;

#[cfg(test)]
mod precedence_tests;
