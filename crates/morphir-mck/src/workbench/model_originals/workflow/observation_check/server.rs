//! Factual comparison of the original declaration role. Serialized DATA does
//! not establish a live source owner or native-host completion.
use super::super::native_original::*;
use super::super::{FixtureAlias, domain, input, observed};
use super::{CompareOwner, CompareResource, ObservationError};
use crate::workbench::model_originals as protocol;
use protocol::fixture_bytes::RecipePart;
use sha2::{Digest, Sha256};
use std::borrow::Cow;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(in crate::workbench::model_originals::workflow) enum NativeFault {
    UnsupportedSource,
    Selection,
    SourceRecipe,
    Capture,
    Transcript,
    PrivateRecord,
    Checkpoints,
    SourceCoverage,
    SourceWitness,
    WorkerCoverage,
    EntryCoverage,
    FinalResources,
    Outcome,
    Teardown,
    Allocation,
}
/// A pure factual result. No constructor of a live run/qualified report uses
/// this value without the separately retained actual adapter invocation.
pub(in crate::workbench::model_originals::workflow) struct ComparedNativeFacts {
    checked: usize,
}
impl ComparedNativeFacts {
    pub(in crate::workbench::model_originals::workflow) fn checked_predicates(&self) -> usize {
        self.checked
    }
}
type Result<T> = std::result::Result<T, ObservationError>;
fn require(owner: &mut CompareOwner, condition: bool, kind: NativeFault) -> Result<()> {
    owner.charge(CompareResource::Checks, 1)?;
    if condition {
        Ok(())
    } else {
        owner.refuse(ObservationError::NativeDeclaration(kind))
    }
}
fn bytes(owner: &mut CompareOwner, amount: usize) -> Result<()> {
    owner.charge(CompareResource::ComparisonBytes, amount)
}
fn text(owner: &mut CompareOwner, a: &str, b: &str, kind: NativeFault) -> Result<()> {
    let equal = owner.same_text(a, b)?;
    require(owner, equal, kind)
}
fn alias(owner: &mut CompareOwner, a: &FixtureAlias, b: &FixtureAlias) -> Result<()> {
    let equal = owner.same(a, b)?;
    require(owner, equal, NativeFault::Selection)
}
fn sum(owner: &mut CompareOwner, a: usize, b: usize) -> Result<usize> {
    a.checked_add(b)
        .ok_or_else(|| *owner.fault.get_or_insert(ObservationError::SizeOverflow))
}
fn allocation<T>(owner: &mut CompareOwner) -> Result<T> {
    owner.refuse(ObservationError::NativeDeclaration(NativeFault::Allocation))
}
fn recipe_part<'a>(part: &'a input::AtomicBytes) -> RecipePart<'a> {
    match part {
        input::AtomicBytes::Utf8 { text } => RecipePart::Utf8(&text.0),
        input::AtomicBytes::Hex { hex } => RecipePart::Hex(hex.as_str()),
        input::AtomicBytes::RepeatU8 { byte, length } => RecipePart::Repeat {
            byte: byte.0 as u8,
            length: length.0 as usize,
        },
        input::AtomicBytes::CycleU8 { seed, length } => RecipePart::Cycle {
            seed: seed.0 as u8,
            length: length.0 as usize,
        },
        input::AtomicBytes::ChunkIndexedU8 { seed, length } => RecipePart::ChunkIndexed {
            seed: seed.0 as u8,
            length: length.0 as usize,
        },
    }
}
fn part_length(part: RecipePart<'_>) -> usize {
    match part {
        RecipePart::Utf8(text) => text.len(),
        RecipePart::Hex(text) => text.len() / 2,
        RecipePart::Repeat { length, .. }
        | RecipePart::Cycle { length, .. }
        | RecipePart::ChunkIndexed { length, .. } => length,
    }
}
pub(in crate::workbench::model_originals::workflow) fn recipe(
    value: &input::Bytes,
    owner: &mut CompareOwner,
) -> Result<protocol::FixtureBytes> {
    owner.visit()?;
    let count = match value {
        input::Bytes::Concat { parts } => parts.0.len(),
        _ => 1,
    };
    let mut parts = Vec::new();
    if parts.try_reserve_exact(count).is_err() {
        return allocation(owner);
    }
    match value {
        input::Bytes::Utf8 { text } => parts.push(RecipePart::Utf8(&text.0)),
        input::Bytes::Hex { hex } => parts.push(RecipePart::Hex(hex.as_str())),
        input::Bytes::RepeatU8 { byte, length } => parts.push(RecipePart::Repeat {
            byte: byte.0 as u8,
            length: length.0 as usize,
        }),
        input::Bytes::CycleU8 { seed, length } => parts.push(RecipePart::Cycle {
            seed: seed.0 as u8,
            length: length.0 as usize,
        }),
        input::Bytes::ChunkIndexedU8 { seed, length } => parts.push(RecipePart::ChunkIndexed {
            seed: seed.0 as u8,
            length: length.0 as usize,
        }),
        input::Bytes::Concat { parts: source } => {
            for part in &source.0 {
                owner.visit()?;
                parts.push(recipe_part(part));
            }
        }
    }
    let mut length = 0;
    for part in &parts {
        length = sum(owner, length, part_length(*part))?;
    }
    // Actual typed recipe validation/copy is charged before its destination.
    bytes(owner, length)?;
    protocol::FixtureBytes::from_typed_parts(&parts, protocol::evidence::MAX_SOURCE_BYTES).map_err(
        |_| {
            *owner
                .fault
                .get_or_insert(ObservationError::NativeDeclaration(
                    NativeFault::SourceRecipe,
                ))
        },
    )
}
fn expanded_frame<'a>(frame: &'a input::Frame, owner: &mut CompareOwner) -> Result<Cow<'a, str>> {
    owner.visit()?;
    match frame {
        input::Frame::Literal { text } => Ok(Cow::Borrowed(&text.0)),
        input::Frame::Segments { parts } => {
            let mut length = 0;
            for part in &parts.0 {
                owner.visit()?;
                let span = match part {
                    input::FramePart::Literal { text } => text.0.len(),
                    input::FramePart::Repeat { text, count } => text
                        .0
                        .len()
                        .checked_mul(
                            usize::try_from(count.0).map_err(|_| ObservationError::SizeOverflow)?,
                        )
                        .ok_or(ObservationError::SizeOverflow)?,
                };
                length = sum(owner, length, span)?;
            }
            bytes(owner, length)?;
            let mut output = String::new();
            if output.try_reserve_exact(length).is_err() {
                return allocation(owner);
            }
            for part in &parts.0 {
                match part {
                    input::FramePart::Literal { text } => output.push_str(&text.0),
                    input::FramePart::Repeat { text, count } => {
                        if !text.0.is_empty() {
                            for _ in 0..count.0 {
                                output.push_str(&text.0);
                            }
                        }
                    }
                }
            }
            Ok(Cow::Owned(output))
        }
    }
}
fn materialize(value: &protocol::FixtureBytes, owner: &mut CompareOwner) -> Result<Vec<u8>> {
    bytes(owner, value.byte_length())?;
    let mut output = Vec::new();
    if output.try_reserve_exact(value.byte_length()).is_err() {
        return allocation(owner);
    }
    output.resize(value.byte_length(), 0);
    value
        .fill_window(0, &mut output)
        .map_err(|_| ObservationError::NativeDeclaration(NativeFault::SourceRecipe))?;
    Ok(output)
}
fn same_recipe(a: &input::Bytes, b: &input::Bytes, owner: &mut CompareOwner) -> Result<()> {
    // Recipe discriminators are authorship facts. In particular UTF8 cannot be
    // silently replaced by a semantically equal hex fixture in the source.
    let same_kind = matches!(
        (a, b),
        (input::Bytes::Utf8 { .. }, input::Bytes::Utf8 { .. })
            | (input::Bytes::Hex { .. }, input::Bytes::Hex { .. })
            | (input::Bytes::RepeatU8 { .. }, input::Bytes::RepeatU8 { .. })
            | (input::Bytes::CycleU8 { .. }, input::Bytes::CycleU8 { .. })
            | (
                input::Bytes::ChunkIndexedU8 { .. },
                input::Bytes::ChunkIndexedU8 { .. }
            )
            | (input::Bytes::Concat { .. }, input::Bytes::Concat { .. })
    );
    require(owner, same_kind, NativeFault::SourceRecipe)?;
    let a = recipe(a, owner)?;
    let b = recipe(b, owner)?;
    let a = materialize(&a, owner)?;
    let b = materialize(&b, owner)?;
    let compared = sum(owner, a.len(), b.len())?;
    bytes(owner, compared)?;
    require(owner, a == b, NativeFault::SourceRecipe)
}

fn root(value: &domain::Root) -> std::result::Result<protocol::Root, protocol::InvalidFrame> {
    match value {
        domain::Root::File { path } => protocol::Root::file(path.0.as_str()),
        domain::Root::Directory { path } => protocol::Root::directory(path.0.as_str()),
    }
}
fn root_pair(
    expected: &domain::Root,
    actual: &observed::Root,
    owner: &mut CompareOwner,
) -> Result<()> {
    let (a, b) = match (expected, actual) {
        (domain::Root::File { path: a }, observed::Root::File { path: b })
        | (domain::Root::Directory { path: a }, observed::Root::Directory { path: b }) => {
            (a.0.as_str(), b.0.as_str())
        }
        _ => return owner.refuse(ObservationError::NativeDeclaration(NativeFault::Capture)),
    };
    text(owner, a, b, NativeFault::Capture)
}
fn header(
    expected: &domain::SourceHeader,
    actual: &observed::SourceHeader,
    owner: &mut CompareOwner,
) -> Result<()> {
    match (expected, actual) {
        (domain::SourceHeader::NotReported {}, observed::SourceHeader::NotReported {}) => Ok(()),
        (
            domain::SourceHeader::Reported { release: a },
            observed::SourceHeader::Reported { release: b },
        ) => text(owner, &a.0, &b.0, NativeFault::Capture),
        _ => owner.refuse(ObservationError::NativeDeclaration(NativeFault::Capture)),
    }
}
fn coverage(
    expected: &domain::CaptureCoverage,
    actual: &observed::CaptureCoverage,
    owner: &mut CompareOwner,
) -> Result<()> {
    require(
        owner,
        matches!(
            (expected, actual),
            (
                domain::CaptureCoverage::Complete { .. },
                observed::CaptureCoverage::Complete { .. }
            ) | (
                domain::CaptureCoverage::Primary {},
                observed::CaptureCoverage::Primary {}
            )
        ),
        NativeFault::Capture,
    )
}

pub(in crate::workbench::model_originals::workflow) fn compare_declaration_data(
    plan: &NativeComparisonPlan<'_>,
    actual: &NativeDeclarationObservation,
    owner: &mut CompareOwner,
) -> Result<ComparedNativeFacts> {
    owner.ready()?;
    match compare_inner(plan, actual, owner) {
        Ok(value) => Ok(value),
        Err(error) => owner.refuse(error),
    }
}
fn compare_inner(
    plan: &NativeComparisonPlan<'_>,
    actual: &NativeDeclarationObservation,
    owner: &mut CompareOwner,
) -> Result<ComparedNativeFacts> {
    owner.visit()?;
    let before = owner.usage.checks;
    let (fixture, actions) = plan.selected();
    let expected = plan.expected;
    let selection = &actual.resolved_selection;
    let metadata = plan
        .witness_metadata()
        .ok_or(ObservationError::NativeDeclaration(
            NativeFault::UnsupportedSource,
        ))?;
    let provider = fixture
        .providers
        .0
        .iter()
        .find(|provider| match provider {
            OriginalProvider::Native { alias, .. } => alias == &selection.provider,
        })
        .ok_or(ObservationError::NativeDeclaration(NativeFault::Selection))?;
    let OriginalProvider::Native {
        grant,
        locator,
        projects,
        ..
    } = provider;
    text(
        owner,
        &locator.0,
        selection.source.locator.as_str(),
        NativeFault::Selection,
    )?;
    let _project = projects
        .0
        .iter()
        .find(|project| project.alias == selection.project)
        .ok_or(ObservationError::NativeDeclaration(NativeFault::Selection))?;
    let grant = fixture
        .grants
        .0
        .iter()
        .find(|candidate| candidate.alias == *grant)
        .ok_or(ObservationError::NativeDeclaration(NativeFault::Selection))?;
    let OriginalCapture::Ready {
        coverage: expected_coverage,
        file_sha256,
        inventory_request_id,
        originals,
        projection,
        read_request_id,
        release_request_id,
        request_id,
        source,
        source_byte_length,
    } = &expected.capture;
    require(owner, actual.captures.0.len() == 1, NativeFault::Capture)?;
    let capture = &actual.captures.0[0];
    alias(owner, &capture.capture, &selection.capture)?;
    coverage(expected_coverage, &capture.coverage, owner)?;
    root_pair(&source.primary_root, &capture.source.primary_root, owner)?;
    require(
        owner,
        source.companion_roots.0.len() == capture.source.companion_roots.0.len(),
        NativeFault::Capture,
    )?;
    for (a, b) in source
        .companion_roots
        .0
        .iter()
        .zip(&capture.source.companion_roots.0)
    {
        root_pair(a, b, owner)?;
    }
    header(
        &source.source_format_version,
        &capture.source.source_format_version,
        owner,
    )?;
    require(
        owner,
        matches!(
            (projection, &capture.projection),
            (
                domain::ExpectedProjection::NotRequested {},
                observed::ProjectionWitness::NotRequested {}
            )
        ),
        NativeFault::Capture,
    )?;
    require(
        owner,
        source_byte_length.0 == capture.inventory.source_byte_length.0,
        NativeFault::Capture,
    )?;

    let mut recipes = Vec::new();
    if recipes.try_reserve_exact(originals.0.len()).is_err() {
        return allocation(owner);
    }
    for entry in &originals.0 {
        owner.visit()?;
        if let input::Entry::File {
            bytes: expected_bytes,
            path,
        } = entry
        {
            let source_bytes = grant
                .nodes
                .0
                .iter()
                .find_map(|node| match node {
                    input::HostNode::File {
                        bytes,
                        path: source_path,
                    } if source_path.0.as_str().strip_prefix(metadata.output_prefix)
                        == Some(path.0.as_str()) =>
                    {
                        Some(bytes)
                    }
                    _ => None,
                })
                .ok_or(ObservationError::NativeDeclaration(
                    NativeFault::SourceRecipe,
                ))?;
            same_recipe(source_bytes, expected_bytes, owner)?;
            recipes.push(Some(recipe(expected_bytes, owner)?));
        } else {
            recipes.push(None);
        }
    }
    let mut entries = Vec::new();
    if entries.try_reserve_exact(originals.0.len()).is_err() {
        return allocation(owner);
    }
    for (entry, recipe) in originals.0.iter().zip(&recipes) {
        let entry = match (entry, recipe) {
            (input::Entry::Directory { path }, None) => {
                protocol::ExpectedOriginalEntry::directory(path.0.as_str())
            }
            (input::Entry::File { path, .. }, Some(recipe)) => {
                protocol::ExpectedOriginalEntry::file(
                    path.0.as_str(),
                    recipe.expected().map_err(|_| {
                        ObservationError::NativeDeclaration(NativeFault::SourceRecipe)
                    })?,
                )
            }
            _ => {
                return owner.refuse(ObservationError::NativeDeclaration(
                    NativeFault::SourceRecipe,
                ));
            }
        }
        .map_err(|_| ObservationError::NativeDeclaration(NativeFault::SourceRecipe))?;
        entries.push(entry);
    }
    let primary = root(&source.primary_root)
        .map_err(|_| ObservationError::NativeDeclaration(NativeFault::Capture))?;
    let mut companions = Vec::new();
    if companions
        .try_reserve_exact(source.companion_roots.0.len())
        .is_err()
    {
        return allocation(owner);
    }
    for value in &source.companion_roots.0 {
        companions.push(
            root(value).map_err(|_| ObservationError::NativeDeclaration(NativeFault::Capture))?,
        );
    }
    let format = match &source.source_format_version {
        domain::SourceHeader::NotReported {} => protocol::SourceFormatVersion::NotReported,
        domain::SourceHeader::Reported { release } => protocol::SourceFormatVersion::Reported(
            protocol::ModelRelease::parse(&release.0)
                .map_err(|_| ObservationError::NativeDeclaration(NativeFault::Capture))?,
        ),
    };
    let source_roles = protocol::ExpectedSource::new(primary, companions, format)
        .map_err(|_| ObservationError::NativeDeclaration(NativeFault::Capture))?;
    let originals = protocol::ExpectedOriginals::new(entries, source_roles)
        .map_err(|_| ObservationError::NativeDeclaration(NativeFault::Capture))?;
    compare_transcript(plan, actual, &originals, owner)?;
    bytes(owner, 64)?;
    // The first original fixes one primary file digest independently of the
    // observed inventory digest and private record digest.
    let primary = recipes
        .iter()
        .flatten()
        .next()
        .ok_or(ObservationError::NativeDeclaration(
            NativeFault::SourceRecipe,
        ))?;
    let primary_bytes = materialize(primary, owner)?;
    bytes(owner, primary_bytes.len())?;
    require(
        owner,
        <[u8; 32]>::from(Sha256::digest(&primary_bytes)) == file_sha256.0,
        NativeFault::Capture,
    )?;
    compare_record(plan, actual, owner)?;
    compare_checkpoints(plan, actual, owner)?;
    let _ = (
        inventory_request_id,
        read_request_id,
        release_request_id,
        request_id,
        actions,
    );
    Ok(ComparedNativeFacts {
        checked: owner.usage.checks - before,
    })
}

fn compare_transcript(
    plan: &NativeComparisonPlan<'_>,
    actual: &NativeDeclarationObservation,
    originals: &protocol::ExpectedOriginals<'_>,
    owner: &mut CompareOwner,
) -> Result<()> {
    let (_, actions) = plan.selected();
    let selection = &actual.resolved_selection;
    let expected = &plan.expected.capture;
    let OriginalCapture::Ready {
        request_id,
        inventory_request_id,
        read_request_id,
        release_request_id,
        ..
    } = expected;
    let mut frames = Vec::new();
    if frames
        .try_reserve_exact(actual.transcript.exchanges.0.len())
        .is_err()
    {
        return allocation(owner);
    }
    let mut aggregate = 0;
    for exchange in &actual.transcript.exchanges.0 {
        let request = expanded_frame(&exchange.request, owner)?;
        let reply = expanded_frame(&exchange.reply, owner)?;
        require(
            owner,
            request.len() <= protocol::MAX_REQUEST_BYTES
                && reply.len() <= protocol::transcript::MAX_REPLY_BYTES,
            NativeFault::Transcript,
        )?;
        aggregate = sum(owner, aggregate, request.len())?;
        aggregate = sum(owner, aggregate, reply.len())?;
        // Parse/copy/verification all use existing protocol code. This named
        // full-span debit precedes those effects on the same comparison owner.
        let span = sum(owner, request.len(), reply.len())?;
        bytes(owner, span)?;
        frames.push((request, reply));
    }
    require(owner, frames.len() == 4, NativeFault::Transcript)?;
    let mut requests = Vec::new();
    if requests.try_reserve_exact(frames.len()).is_err() {
        return allocation(owner);
    }
    for (request, _) in &frames {
        requests.push(
            protocol::Request::parse(request)
                .map_err(|_| ObservationError::NativeDeclaration(NativeFault::Transcript))?,
        );
    }
    let mut next = 0;
    for action in actions {
        owner.visit()?;
        match action {
            input::HostAction::CaptureSelected {
                connection,
                provider,
                project,
                capture,
                request_id: source_id,
                scope,
                semantic,
                ..
            } => {
                alias(owner, connection, &selection.connection)?;
                alias(owner, provider, &selection.provider)?;
                alias(owner, project, &selection.project)?;
                alias(owner, capture, &selection.capture)?;
                require(
                    owner,
                    matches!(scope, input::HostActionCaptureSelectedScope::Complete)
                        && matches!(semantic, input::HostActionCaptureSelectedSemantic::None),
                    NativeFault::Selection,
                )?;
                let request = requests
                    .get(next)
                    .ok_or(ObservationError::NativeDeclaration(NativeFault::Transcript))?;
                require(
                    owner,
                    request.id() == source_id.0 && request.id() == request_id.0,
                    NativeFault::Transcript,
                )?;
                require(
                    owner,
                    matches!(request.parameters(),protocol::Parameters::Capture {source,project,scope:protocol::CaptureScope::Complete,semantic:protocol::SemanticRequest::None} if source==&selection.source && project==&selection.project_id),
                    NativeFault::Selection,
                )?;
                next += 1;
            }
            input::HostAction::Inventory {
                connection,
                capture,
                request_id,
                start_index,
                max_entries,
            } => {
                alias(owner, connection, &selection.connection)?;
                alias(owner, capture, &selection.capture)?;
                let request = requests
                    .get(next)
                    .ok_or(ObservationError::NativeDeclaration(NativeFault::Transcript))?;
                require(
                    owner,
                    request.id() == request_id.0 && request.id() == inventory_request_id.0,
                    NativeFault::Transcript,
                )?;
                require(
                    owner,
                    matches!(request.parameters(),protocol::Parameters::Inventory {capture,start,maximum} if capture==&selection.capture_id && start.get() as u64==start_index.0 && maximum.get() as u64==max_entries.0),
                    NativeFault::Transcript,
                )?;
                next += 1;
            }
            input::HostAction::ReadSelected {
                connection,
                capture,
                request_id,
                target,
                offset,
                max_bytes,
            } => {
                alias(owner, connection, &selection.connection)?;
                alias(owner, capture, &selection.capture)?;
                let request = requests
                    .get(next)
                    .ok_or(ObservationError::NativeDeclaration(NativeFault::Transcript))?;
                require(
                    owner,
                    request.id() == request_id.0 && request.id() == read_request_id.0,
                    NativeFault::Transcript,
                )?;
                // Existing transcript verification resolves the actual entry
                // ID to the independently expected path/full file bytes.
                let metadata =
                    plan.witness_metadata()
                        .ok_or(ObservationError::NativeDeclaration(
                            NativeFault::UnsupportedSource,
                        ))?;
                require(
                    owner,
                    matches!(target,input::HostActionReadSelectedTarget::OriginalEntry {path} if Some(path.0.as_str())==metadata.primary.strip_prefix(metadata.output_prefix)),
                    NativeFault::Transcript,
                )?;
                require(
                    owner,
                    matches!(request.parameters(),protocol::Parameters::Read {capture,target:protocol::ReadTarget::Original {..},offset:actual_offset,maximum} if capture==&selection.capture_id && actual_offset.get() as u64==offset.0 && maximum.get() as u64==max_bytes.0),
                    NativeFault::Transcript,
                )?;
                next += 1;
            }
            input::HostAction::Release {
                connection,
                capture,
                request_id,
            } => {
                alias(owner, connection, &selection.connection)?;
                alias(owner, capture, &selection.capture)?;
                let request = requests
                    .get(next)
                    .ok_or(ObservationError::NativeDeclaration(NativeFault::Transcript))?;
                require(
                    owner,
                    request.id() == request_id.0 && request.id() == release_request_id.0,
                    NativeFault::Transcript,
                )?;
                require(
                    owner,
                    matches!(request.parameters(),protocol::Parameters::Release {capture} if capture==&selection.capture_id),
                    NativeFault::Transcript,
                )?;
                next += 1;
            }
            input::HostAction::Connect { connection, .. }
            | input::HostAction::Disconnect { connection } => {
                alias(owner, connection, &selection.connection)?;
            }
            input::HostAction::Discover {
                connection,
                provider,
            } => {
                alias(owner, connection, &selection.connection)?;
                alias(owner, provider, &selection.provider)?;
            }
            input::HostAction::Checkpoint { .. } => {}
            _ => {
                return owner.refuse(ObservationError::NativeDeclaration(
                    NativeFault::UnsupportedSource,
                ));
            }
        }
    }
    require(owner, next == frames.len(), NativeFault::Transcript)?;
    let mut borrowed = Vec::new();
    if borrowed.try_reserve_exact(frames.len()).is_err() {
        return allocation(owner);
    }
    for (request, reply) in &frames {
        borrowed.push((request.as_ref(), reply.as_ref()));
    }
    // The aggregate is an exact effect size authorized above, not a source-
    // supplied production grant or a reset of the cumulative caller owner.
    let limits = protocol::TranscriptLimits::new(aggregate, aggregate, frames.len())
        .map_err(|_| ObservationError::NativeDeclaration(NativeFault::Transcript))?;
    let transcript = protocol::Transcript::from_literal_frames(&borrowed, limits)
        .map_err(|_| ObservationError::NativeDeclaration(NativeFault::Transcript))?;
    let expectation = protocol::ConnectedCaptureExpectation::new(
        &selection.session_id,
        &requests[0],
        originals,
        protocol::ExpectedProjectionState::NotRequested,
        protocol::CaptureCompletion::Released,
    )
    .map_err(|_| ObservationError::NativeDeclaration(NativeFault::Transcript))?;
    let checked = transcript
        .verify(&expectation)
        .map_err(|_| ObservationError::NativeDeclaration(NativeFault::Transcript))?;
    let inventory = checked.originals().inventory();
    let claim = &actual.captures.0[0].inventory;
    bytes(owner, 64)?;
    require(
        owner,
        inventory.digest().0 == claim.sha256.0,
        NativeFault::Capture,
    )?;
    require(
        owner,
        inventory.entries().len() as u64 == claim.entry_count.0,
        NativeFault::Capture,
    )?;
    let files = inventory
        .entries()
        .iter()
        .filter(|entry| entry.kind() == protocol::RootKind::File)
        .count();
    require(
        owner,
        files as u64 == claim.file_count.0
            && (inventory.entries().len() - files) as u64 == claim.directory_count.0,
        NativeFault::Capture,
    )?;
    require(
        owner,
        inventory.source_byte_length() as u64 == claim.source_byte_length.0,
        NativeFault::Capture,
    )
}

fn compare_record(
    plan: &NativeComparisonPlan<'_>,
    actual: &NativeDeclarationObservation,
    owner: &mut CompareOwner,
) -> Result<()> {
    let metadata = plan
        .witness_metadata()
        .ok_or(ObservationError::NativeDeclaration(
            NativeFault::UnsupportedSource,
        ))?;
    let (fixture, _) = plan.selected();
    let record = fixture
        .grants
        .0
        .iter()
        .flat_map(|grant| &grant.nodes.0)
        .find_map(|node| match node {
            input::HostNode::File { bytes, path } if path.0.as_str() == metadata.record => {
                Some(bytes)
            }
            _ => None,
        })
        .ok_or(ObservationError::NativeDeclaration(
            NativeFault::PrivateRecord,
        ))?;
    same_recipe(record, &actual.private_record.bytes, owner)?;
    let record = recipe(record, owner)?;
    let raw = materialize(&record, owner)?;
    bytes(owner, raw.len())?;
    let digest: [u8; 32] = Sha256::digest(&raw).into();
    bytes(owner, 128)?;
    require(
        owner,
        digest == plan.expected.raw_record.sha256.0 && digest == actual.private_record.sha256.0,
        NativeFault::PrivateRecord,
    )?;
    require(
        owner,
        raw.len() as u64 == plan.expected.raw_record.byte_length.0
            && raw.len() as u64 == actual.private_record.byte_length.0,
        NativeFault::PrivateRecord,
    )?;
    let FrozenDeclaration::Declared { companions, .. } = &actual.private_record.declaration else {
        return owner.refuse(ObservationError::NativeDeclaration(
            NativeFault::PrivateRecord,
        ));
    };
    // The reserved declaration parser is the SAME protocol private-record
    // parser used by the existing independent capture expectation.
    let raw = std::str::from_utf8(&raw)
        .map_err(|_| ObservationError::NativeDeclaration(NativeFault::PrivateRecord))?;
    let declaration = protocol::Declaration::from_compile_record(raw)
        .map_err(|_| ObservationError::NativeDeclaration(NativeFault::PrivateRecord))?;
    require(
        owner,
        declaration.companions().len() == companions.0.len()
            && companions.0.len() == plan.expected.original_expected.companions.0.len(),
        NativeFault::PrivateRecord,
    )?;
    for ((wire, claim), expected) in declaration
        .companions()
        .iter()
        .zip(&companions.0)
        .zip(&plan.expected.original_expected.companions.0)
    {
        require(
            owner,
            wire == &root(claim)
                .map_err(|_| ObservationError::NativeDeclaration(NativeFault::PrivateRecord))?,
            NativeFault::PrivateRecord,
        )?;
        let claim = root(claim)
            .map_err(|_| ObservationError::NativeDeclaration(NativeFault::PrivateRecord))?;
        require(
            owner,
            claim
                == root(expected)
                    .map_err(|_| ObservationError::NativeDeclaration(NativeFault::PrivateRecord))?,
            NativeFault::PrivateRecord,
        )?;
    }
    coverage(
        &plan.expected.original_expected.coverage,
        &actual.captures.0[0].coverage,
        owner,
    )
}

fn read_counts(counts: &ReadCounts) -> [u64; 3] {
    [
        counts.attempts.0,
        counts.read_calls.0,
        counts.returned_bytes.0,
    ]
}
fn valid_read_prefix(prefix: &ReadPrefix, owner: &mut CompareOwner) -> Result<()> {
    for ((total, workspace), ambient) in read_counts(&prefix.total)
        .into_iter()
        .zip(read_counts(&prefix.workspace))
        .zip(read_counts(&prefix.ambient))
    {
        require(
            owner,
            workspace.checked_add(ambient) == Some(total),
            NativeFault::SourceCoverage,
        )?;
    }
    Ok(())
}
fn worker_counts(value: &WorkerCounts, owner: &mut CompareOwner) -> Result<()> {
    let normal = value.returned_ok.0.checked_add(value.returned_error.0);
    let bodies = normal.and_then(|n| n.checked_add(value.panicked.0));
    require(
        owner,
        value.scheduled.0 != 0
            && value.owned_handles.0 == 0
            && value.dropped_unjoined.0 == 0
            && normal == Some(value.joined_ok.0)
            && value.panicked.0 == value.joined_panicked.0
            && bodies == Some(value.started.0)
            && value.started.0.checked_add(value.joined_cancelled.0) == Some(value.scheduled.0),
        NativeFault::WorkerCoverage,
    )
}
fn compare_checkpoints(
    plan: &NativeComparisonPlan<'_>,
    actual: &NativeDeclarationObservation,
    owner: &mut CompareOwner,
) -> Result<()> {
    let (_, actions) = plan.selected();
    let selection = &actual.resolved_selection;
    let metadata = plan
        .witness_metadata()
        .ok_or(ObservationError::NativeDeclaration(
            NativeFault::UnsupportedSource,
        ))?;
    let mut index = 0;
    let mut previous = [0; 3];
    for action in actions {
        owner.visit()?;
        let input::HostAction::Checkpoint { name } = action else {
            continue;
        };
        let checkpoint =
            actual
                .checkpoints
                .0
                .get(index)
                .ok_or(ObservationError::NativeDeclaration(
                    NativeFault::Checkpoints,
                ))?;
        alias(owner, name, &checkpoint.name)?;
        alias(owner, &selection.connection, &checkpoint.connection)?;
        let observed::OfferEvidence::Held {
            provider,
            registration,
        } = &checkpoint.offer
        else {
            return owner.refuse(ObservationError::NativeDeclaration(NativeFault::Selection));
        };
        alias(owner, &selection.provider, provider)?;
        alias(owner, &selection.registration, registration)?;
        let valid = match (&checkpoint.state, index) {
            (
                observed::CaptureState::Ready {
                    capture,
                    connection,
                },
                0,
            ) => {
                owner.same(capture, &selection.capture)?
                    && owner.same(connection, &selection.connection)?
            }
            (
                observed::CaptureState::Released {
                    connection,
                    last_capture,
                },
                1,
            ) => {
                owner.same(last_capture, &selection.capture)?
                    && owner.same(connection, &selection.connection)?
            }
            (
                observed::CaptureState::Closed {
                    cleanup: observed::CaptureStateClosedCleanup::None {},
                },
                2,
            ) => true,
            _ => false,
        };
        require(owner, valid, NativeFault::Checkpoints)?;
        let counts = match &checkpoint.source {
            SourceMeasurements::OpenPrefix { counts } if index < 2 => counts,
            SourceMeasurements::SealedComplete { counts, .. } => counts,
            _ => {
                return owner.refuse(ObservationError::NativeDeclaration(
                    NativeFault::SourceCoverage,
                ));
            }
        };
        valid_read_prefix(counts, owner)?;
        let total = read_counts(&counts.total);
        for (before, now) in previous.into_iter().zip(total) {
            require(owner, now >= before, NativeFault::SourceCoverage)?;
        }
        previous = total;
        // The actual owner-side JoinedCleanup method also checks private
        // in-flight issuance. These DATA equations never substitute for it.
        let workers = match &checkpoint.workers {
            WorkerMeasurements::ObservedPrefix { counts } if index < 2 => counts,
            WorkerMeasurements::JoinedCleanup { counts } => counts,
            _ => {
                return owner.refuse(ObservationError::NativeDeclaration(
                    NativeFault::WorkerCoverage,
                ));
            }
        };
        worker_counts(workers, owner)?;
        let EntryCoverage::Complete {
            compile_calls,
            legacy_model_open_calls,
        } = &checkpoint.entries
        else {
            return owner.refuse(ObservationError::NativeDeclaration(
                NativeFault::EntryCoverage,
            ));
        };
        require(
            owner,
            compile_calls.0 == plan.expected.source_access.compile_calls.0
                && legacy_model_open_calls.0 == plan.expected.source_access.v1_open_calls.0,
            NativeFault::EntryCoverage,
        )?;
        index += 1;
    }
    require(
        owner,
        index == 3 && index == actual.checkpoints.0.len(),
        NativeFault::Checkpoints,
    )?;
    let final_checkpoint = &actual.checkpoints.0[index - 1];
    let SourceMeasurements::SealedComplete { counts, files } = &final_checkpoint.source else {
        return owner.refuse(ObservationError::NativeDeclaration(
            NativeFault::SourceCoverage,
        ));
    };
    require(
        owner,
        counts.ambient.attempts.0 == plan.expected.source_access.ambient_reads.0,
        NativeFault::SourceCoverage,
    )?;
    require(owner, files.0.len() == 3, NativeFault::SourceWitness)?;
    let mut witnessed = [0u64; 3];
    for (index, file) in files.0.iter().enumerate() {
        owner.visit()?;
        require(
            owner,
            !files.0[..index]
                .iter()
                .any(|previous| previous.role == file.role),
            NativeFault::SourceWitness,
        )?;
        let path = match file.role {
            FileRole::CompileRecord => metadata.record,
            FileRole::OriginalPrimary => metadata.primary,
            FileRole::UndeclaredSentinel => metadata.sentinel,
        };
        text(
            owner,
            file.path.0.as_str(),
            path,
            NativeFault::SourceWitness,
        )?;
        let reads = read_counts(&file.reads);
        for ((aggregate, file), total) in witnessed
            .iter_mut()
            .zip(reads)
            .zip(read_counts(&counts.total))
        {
            *aggregate = aggregate
                .checked_add(file)
                .ok_or(ObservationError::SizeOverflow)?;
            require(owner, *aggregate <= total, NativeFault::SourceWitness)?;
        }
        match file.role {
            FileRole::UndeclaredSentinel => {
                require(
                    owner,
                    file.reads.attempts.0
                        == plan.expected.source_access.undeclared_sentinel_reads.0
                        && file.reads.read_calls.0 == 0
                        && file.reads.returned_bytes.0 == 0,
                    NativeFault::SourceWitness,
                )?;
            }
            FileRole::CompileRecord => require(
                owner,
                file.reads.attempts.0 > 0
                    && file.reads.read_calls.0 > 0
                    && file.reads.returned_bytes.0 >= actual.private_record.byte_length.0,
                NativeFault::SourceWitness,
            )?,
            FileRole::OriginalPrimary => {
                let OriginalCapture::Ready {
                    source_byte_length, ..
                } = &plan.expected.capture;
                require(
                    owner,
                    file.reads.attempts.0 > 0
                        && file.reads.read_calls.0 > 0
                        && file.reads.returned_bytes.0 >= source_byte_length.0,
                    NativeFault::SourceWitness,
                )?;
            }
        }
    }
    let final_expected = &plan.expected.final_state;
    let resources = &final_checkpoint.resources;
    for (a, b) in [
        (resources.active_workers.0, final_expected.active_workers.0),
        (resources.metadata_bytes.0, final_expected.metadata_bytes.0),
        (
            resources.projection_bytes.0,
            final_expected.projection_bytes.0,
        ),
        (resources.record_bytes.0, final_expected.record_bytes.0),
        (resources.slots.0, final_expected.slots.0),
        (resources.source_bytes.0, final_expected.source_bytes.0),
    ] {
        require(owner, a == b, NativeFault::FinalResources)?;
    }
    let WorkerMeasurements::JoinedCleanup { counts } = &final_checkpoint.workers else {
        return owner.refuse(ObservationError::NativeDeclaration(
            NativeFault::WorkerCoverage,
        ));
    };
    require(
        owner,
        counts.owned_handles.0 == final_expected.worker_handles.0,
        NativeFault::FinalResources,
    )?;
    require(
        owner,
        matches!(
            &final_checkpoint.state,
            observed::CaptureState::Closed {
                cleanup: observed::CaptureStateClosedCleanup::None {}
            } | observed::CaptureState::Released { .. }
        ),
        NativeFault::FinalResources,
    )?;
    let observed::ScenarioOutcome::Clean {
        final_checkpoint: name,
    } = &actual.outcome
    else {
        return owner.refuse(ObservationError::NativeDeclaration(NativeFault::Outcome));
    };
    alias(owner, name, &final_checkpoint.name)?;
    let observed::HarnessTeardown::Confirmed {
        disposed_transports,
        workers_exited,
        workers_started,
        ..
    } = &actual.teardown
    else {
        return owner.refuse(ObservationError::NativeDeclaration(NativeFault::Teardown));
    };
    let connections = actions
        .iter()
        .filter(|action| matches!(action, input::HostAction::Connect { .. }))
        .count() as u64;
    require(
        owner,
        disposed_transports.0 == connections
            && workers_started.0 == counts.started.0
            && workers_exited.0
                == counts
                    .returned_ok
                    .0
                    .checked_add(counts.returned_error.0)
                    .and_then(|n| n.checked_add(counts.panicked.0))
                    .ok_or(ObservationError::SizeOverflow)?,
        NativeFault::Teardown,
    )
}
