//! Internal fixture correspondence only. These indices issue no file grant.
use super::*;
use crate::workbench::model_originals as protocol;
use protocol::fixture_bytes::RecipePart;
use std::borrow::Cow;

type Result<T> = std::result::Result<T, CompilationError>;

pub(in crate::workbench::model_originals::workflow) struct SourceWitnessRoles {
    // Compile record, primary, excluded sentinel. Only validated here.
    nodes: [usize; 3],
}
impl SourceWitnessRoles {
    pub(super) fn paths<'a>(
        &self,
        fixture: &'a Fixture,
    ) -> impl ExactSizeIterator<Item = (super::super::native::data::FileRole, &'a SourcePath)> + use<'a>
    {
        use super::super::native::data::FileRole;
        [
            FileRole::CompileRecord,
            FileRole::OriginalPrimary,
            FileRole::UndeclaredSentinel,
        ]
        .into_iter()
        .zip(self.nodes)
        .map(move |(role, index)| (role, node_path(&fixture.nodes.0[index])))
    }
}
fn node_path(node: &FixtureNode) -> &SourcePath {
    match node {
        FixtureNode::Literal { path, .. } | FixtureNode::ByteSource { path, .. } => path,
    }
}
fn decode(error: DecodeError) -> CompilationError {
    CompilationError::Source(SourceError::Decode(error))
}
fn bad<T>(owner: &mut ClosureOwner, error: ClosureError) -> Result<T> {
    owner.refuse(error).map_err(super::closure)
}
fn checked_add(a: usize, b: usize) -> Result<usize> {
    a.checked_add(b)
        .ok_or(CompilationError::Source(SourceError::SizeOverflow))
}
fn same(a: &str, b: &str, owner: &mut ClosureOwner) -> Result<bool> {
    owner.same_text(a, b).map_err(super::closure)
}
fn visit(owner: &mut ClosureOwner) -> Result<()> {
    owner
        .charge(Resource::StructuralVisits, 1)
        .map_err(super::closure)
}
fn member<'a>(doc: &'a Document, key: &str, owner: &mut Decoder) -> Result<&'a Document> {
    let Document::Object(fields) = doc else {
        return Err(decode(DecodeError::Shape("witness object")));
    };
    for (name, value) in fields {
        owner
            .bytes(checked_add(name.len(), key.len())?)
            .map_err(decode)?;
        if name == key {
            return Ok(value);
        }
    }
    Err(decode(DecodeError::Shape("witness member")))
}
fn text(doc: &Document) -> Result<&str> {
    match doc {
        Document::String(value) => Ok(value),
        _ => Err(decode(DecodeError::Shape("witness string"))),
    }
}
fn literal(raw: &str, owner: &mut Decoder) -> Result<Document> {
    // The strict parser consumes SAME cumulative ReadWork. ByteVisits also
    // covers the concrete raw pass before any embedded JSON traversal.
    owner.bytes(raw.len()).map_err(decode)?;
    owner
        .literal_with_raw(raw)
        .map(|(doc, _)| doc)
        .map_err(decode)
}
fn frame<'a>(value: &'a input::Frame, owner: &mut Decoder) -> Result<Cow<'a, str>> {
    owner.ready().map_err(decode)?;
    match value {
        input::Frame::Literal { text } => Ok(Cow::Borrowed(text.as_str())),
        input::Frame::Segments { parts } => {
            let mut length = 0;
            for part in &parts.0 {
                owner.slots(1).map_err(decode)?;
                let (text, count) = match part {
                    input::FramePart::Literal { text } => (text.as_str(), 1usize),
                    input::FramePart::Repeat { text, count } => (
                        text.as_str(),
                        usize::try_from(count.0)
                            .map_err(|_| CompilationError::Source(SourceError::SizeOverflow))?,
                    ),
                };
                owner.bytes(text.len()).map_err(decode)?;
                length = checked_add(
                    length,
                    text.len()
                        .checked_mul(count)
                        .ok_or(CompilationError::Source(SourceError::SizeOverflow))?,
                )?;
            }
            owner.bytes(length).map_err(decode)?;
            owner.slots(1).map_err(decode)?;
            let mut result = String::new();
            result
                .try_reserve_exact(length)
                .map_err(|_| decode(DecodeError::Allocation))?;
            // Existing typed Frame interpretation; no JSON/fixture generator.
            for part in &parts.0 {
                match part {
                    input::FramePart::Literal { text } => result.push_str(text.as_str()),
                    input::FramePart::Repeat { text, count } if !text.as_str().is_empty() => {
                        for _ in 0..count.0 {
                            result.push_str(text.as_str())
                        }
                    }
                    input::FramePart::Repeat { .. } => {}
                }
            }
            Ok(Cow::Owned(result))
        }
    }
}
fn root_credit(path: &str, decode_owner: &mut Decoder) -> Result<()> {
    super::super::installed_measurements::namespace_path(path, decode_owner).map_err(decode)?;
    // Actual portable-path component checks and the typed owned path copy.
    decode_owner
        .bytes(checked_add(path.len(), path.len())?)
        .map_err(decode)
}
fn core_credit(raw: &str, doc: &Document, owner: &mut Decoder) -> Result<()> {
    owner.bytes(raw.len()).map_err(decode)?;
    super::super::installed_measurements::reparse_credit(doc, owner).map_err(decode)
}
fn declared_root_credit(doc: &Document, owner: &mut Decoder) -> Result<()> {
    let Document::Array(roots) = doc else {
        return Err(decode(DecodeError::Shape("witness roots")));
    };
    owner.slots(roots.len()).map_err(decode)?;
    for (index, root) in roots.iter().enumerate() {
        let path = text(member(root, "path", owner)?)?;
        root_credit(path, owner)?;
        for earlier in &roots[..index] {
            let earlier = text(member(earlier, "path", owner)?)?;
            super::super::installed_measurements::normalized_copy(path, owner).map_err(decode)?;
            super::super::installed_measurements::normalized_copy(earlier, owner)
                .map_err(decode)?;
        }
    }
    Ok(())
}
fn normalized<'a>(
    path: &'a str,
    owner: &mut Decoder,
) -> Result<impl Iterator<Item = char> + 'a + use<'a>> {
    // The borrowed iterator allocates nothing; visit every original byte before
    // invoking the SAME normalization used by the original namespace collector.
    owner.bytes(path.len()).map_err(decode)?;
    // Admit emitted normalization bytes before the comparison traversal,
    // including Unicode lowercase expansion.
    for ch in protocol::folded_chars(path) {
        owner.bytes(ch.len_utf8()).map_err(decode)?;
    }
    Ok(protocol::folded_chars(path))
}
fn equal_path(a: &str, b: &str, owner: &mut Decoder) -> Result<bool> {
    Ok(normalized(a, owner)?.eq(normalized(b, owner)?))
}
fn under(path: &str, root: &protocol::Root, owner: &mut Decoder) -> Result<bool> {
    let mut actual = normalized(path, owner)?;
    for wanted in normalized(root.path.as_str(), owner)? {
        if actual.next() != Some(wanted) {
            return Ok(false);
        }
    }
    Ok(match actual.next() {
        None => true,
        Some('/') => matches!(root.kind, protocol::RootKind::Directory),
        Some(_) => false,
    })
}

fn record_text(
    value: &input::Bytes,
    expansion: &mut ExpansionOwner,
    owner: &mut Decoder,
) -> Result<String> {
    use super::super::observation_check::server::{part_length, recipe_part};
    let count = match value {
        input::Bytes::Concat { parts } => parts.0.len(),
        _ => 1,
    };
    // Parts, existing Plan and existing Atom destinations, before construction.
    owner
        .slots(
            count
                .checked_mul(3)
                .ok_or(CompilationError::Source(SourceError::SizeOverflow))?,
        )
        .map_err(decode)?;
    let mut parts = Vec::new();
    parts
        .try_reserve_exact(count)
        .map_err(|_| decode(DecodeError::Allocation))?;
    match value {
        input::Bytes::Utf8 { text } => parts.push(RecipePart::Utf8(text.as_str())),
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
                parts.push(recipe_part(part))
            }
        }
    }
    let mut length = 0;
    for part in &parts {
        owner.slots(1).map_err(decode)?;
        length = checked_add(length, part_length(*part))?;
        // Fund literal/hex validation and decoding scans before either the
        // existing ExpansionOwner validator or FixtureBytes factory sees them.
        let encoded = match part {
            RecipePart::Utf8(text) | RecipePart::Hex(text) => text.len(),
            _ => 0,
        };
        owner
            .bytes(checked_add(encoded, encoded)?)
            .map_err(decode)?;
    }
    expansion
        .measure_materialization_bytes(value)
        .map_err(CompilationError::Expansion)?;
    // Literal decoding, zero initialization, complete fill and UTF8 validation
    // are distinct admitted byte passes.
    for _ in 0..4 {
        owner.bytes(length).map_err(decode)?
    }
    let recipe =
        protocol::FixtureBytes::from_typed_parts(&parts, protocol::evidence::MAX_SOURCE_BYTES)
            .map_err(|_| decode(DecodeError::Shape("witness record recipe")))?;
    owner.slots(1).map_err(decode)?;
    let mut raw = Vec::new();
    raw.try_reserve_exact(length)
        .map_err(|_| decode(DecodeError::Allocation))?;
    raw.resize(length, 0);
    recipe
        .fill_window(0, &mut raw)
        .map_err(|_| decode(DecodeError::Shape("witness record fill")))?;
    String::from_utf8(raw).map_err(|_| decode(DecodeError::Shape("witness record UTF8")))
}

pub(in crate::workbench::model_originals::workflow) fn compile_fixture_witness_roles(
    fixture: &Fixture,
    paired: &PairedWorkflow<'_>,
    owner: &mut ClosureOwner,
    expansion: &mut ExpansionOwner,
    decode_owner: &mut Decoder,
) -> Result<SourceWitnessRoles> {
    let result = compile_roles(fixture, paired, owner, expansion, decode_owner);
    match result {
        Err(CompilationError::Closure(CompileError::Owner(error))) => bad(owner, error),
        result => result,
    }
}
fn compile_roles(
    fixture: &Fixture,
    paired: &PairedWorkflow<'_>,
    owner: &mut ClosureOwner,
    expansion: &mut ExpansionOwner,
    decode_owner: &mut Decoder,
) -> Result<SourceWitnessRoles> {
    // Sticky SAME Decode fault wins before any new closure/expansion work.
    decode_owner.ready().map_err(decode)?;
    owner.ready().map_err(super::closure)?;
    expansion.ready().map_err(CompilationError::Expansion)?;
    // An early concrete byte pass also refuses low-work callers before recipe
    // materialization. A short physical label is not a filesystem grant.
    decode_owner
        .bytes(fixture.module.as_str().len())
        .map_err(decode)?;
    let role_aliases = [&fixture.primary, &fixture.opaque, &fixture.record];
    for (index, alias) in role_aliases.iter().enumerate() {
        for other in &role_aliases[..index] {
            if owner.same_alias(alias, other).map_err(super::closure)? {
                return bad(owner, ClosureError::Semantic);
            }
        }
    }
    let mut roles = [None; 3];
    for (index, node) in fixture.nodes.0.iter().enumerate() {
        visit(owner)?;
        let path = node_path(node).as_str();
        root_credit(path, decode_owner)?;
        protocol::Root::file(path).map_err(|_| super::closure(ClosureError::Semantic))?;
        for prior in &fixture.nodes.0[..index] {
            if same(path, node_path(prior).as_str(), owner)? {
                return bad(owner, ClosureError::Duplicate);
            }
        }
        if let FixtureNode::ByteSource { source, .. } = node {
            for (role, alias) in role_aliases.iter().enumerate() {
                if owner.same_alias(source, alias).map_err(super::closure)?
                    && roles[role].replace(index).is_some()
                {
                    return bad(owner, ClosureError::Duplicate);
                }
            }
        }
    }
    let [Some(primary_index), Some(opaque_index), Some(record_index)] = roles else {
        return bad(owner, ClosureError::Missing);
    };
    let super::super::pairing::PairedRun::Client {
        actions,
        fixture: client,
    } = paired.run()
    else {
        return bad(owner, ClosureError::Semantic);
    };
    let input::ClientFixtureMode::Runtime {
        runtime:
            input::ClientRuntime::ControlledModelOriginalsHttpV1 {
                manifest,
                manifest_byte_limit,
                peer,
            },
    } = &client.mode
    else {
        return bad(owner, ClosureError::Semantic);
    };
    if manifest.status.0 != 200 {
        return bad(owner, ClosureError::Semantic);
    }
    let mut selected_peer = None;
    for candidate in &client.literal_peers.0 {
        visit(owner)?;
        if owner
            .same_alias(&candidate.alias, peer)
            .map_err(super::closure)?
            && selected_peer.replace(candidate).is_some()
        {
            return bad(owner, ClosureError::Ambiguous);
        }
    }
    let selected_peer = selected_peer.ok_or_else(|| super::closure(ClosureError::Missing))?;
    let mut opening = None;
    for action in actions {
        visit(owner)?;
        if let input::ClientAction::BeginConnectedOpening {
            source,
            project_id,
            scope,
            semantic,
            ..
        } = action
            && opening
                .replace((source, project_id, scope, semantic))
                .is_some()
        {
            return bad(owner, ClosureError::Ambiguous);
        }
    }
    let (selected_source, selected_project, selected_scope, selected_semantic) =
        opening.ok_or_else(|| super::closure(ClosureError::Missing))?;
    let manifest_raw = frame(&manifest.body, decode_owner)?;
    if manifest_raw.len() > manifest_byte_limit.0 as usize {
        return bad(owner, ClosureError::Semantic);
    }
    let manifest_doc = literal(&manifest_raw, decode_owner)?;
    let session_text = text(member(&manifest_doc, "sessionId", decode_owner)?)?;
    decode_owner.bytes(session_text.len()).map_err(decode)?;
    let session = protocol::SessionId::new(session_text)
        .map_err(|_| super::closure(ClosureError::Semantic))?;
    let Presence::Present(requests) = &selected_peer.requests else {
        return bad(owner, ClosureError::Missing);
    };
    let mut capture = None;
    for candidate in &requests.0 {
        visit(owner)?;
        let raw = frame(candidate, decode_owner)?;
        let doc = literal(&raw, decode_owner)?;
        let method = text(member(&doc, "method", decode_owner)?)?;
        if !same(method, "morphir.model-originals.capture", owner)? {
            continue;
        }
        core_credit(&raw, &doc, decode_owner)?;
        let request =
            protocol::Request::parse(&raw).map_err(|_| super::closure(ClosureError::Semantic))?;
        if capture.replace(request).is_some() {
            return bad(owner, ClosureError::Ambiguous);
        }
    }
    let request = capture.ok_or_else(|| super::closure(ClosureError::Missing))?;
    let protocol::Parameters::Capture {
        source,
        project,
        scope,
        semantic,
    } = request.parameters()
    else {
        return bad(owner, ClosureError::Semantic);
    };
    if !same(
        source.provider.as_str(),
        selected_source.provider_id.as_str(),
        owner,
    )? || !same(
        source.locator.as_str(),
        selected_source.locator.as_str(),
        owner,
    )? || !same(project.as_str(), selected_project.as_str(), owner)?
        || !same(
            match scope {
                protocol::CaptureScope::Primary => "primary",
                protocol::CaptureScope::Complete => "complete",
            },
            selected_scope.key(),
            owner,
        )?
        || !same(
            match semantic {
                protocol::SemanticRequest::None => "none",
                protocol::SemanticRequest::Projection => "projection",
            },
            selected_semantic.key(),
            owner,
        )?
    {
        return bad(owner, ClosureError::Semantic);
    }
    let mut captured = None;
    for candidate in &selected_peer.frames.0 {
        visit(owner)?;
        let raw = frame(candidate, decode_owner)?;
        let doc = literal(&raw, decode_owner)?;
        let id =
            Natural::<0, { u64::MAX }>::decode(member(&doc, "id", decode_owner)?, decode_owner)
                .map_err(decode)?
                .0;
        if id != request.id().get() {
            continue;
        }
        if captured.is_some() {
            return bad(owner, ClosureError::Ambiguous);
        }
        core_credit(&raw, &doc, decode_owner)?;
        let result = member(&doc, "result", decode_owner)?;
        let primary = member(result, "primary", decode_owner)?;
        let primary_path = text(member(primary, "path", decode_owner)?)?;
        root_credit(primary_path, decode_owner)?;
        let companions = member(result, "companions", decode_owner)?;
        declared_root_credit(companions, decode_owner)?;
        if let Document::Array(roots) = companions {
            for root in roots {
                super::super::installed_measurements::normalized_copy(primary_path, decode_owner)
                    .map_err(decode)?;
                super::super::installed_measurements::normalized_copy(
                    text(member(root, "path", decode_owner)?)?,
                    decode_owner,
                )
                .map_err(decode)?;
            }
        }
        // Binding/capture identity copies and all raw JSON copies were credited
        // by core_credit before this SAME existing protocol validator.
        let value = protocol::CaptureExpectation::from_exchange(
            &protocol::Exchange {
                request: &request,
                reply: &raw,
            },
            &session,
        )
        .map_err(|_| super::closure(ClosureError::Semantic))?;
        captured = Some(value);
    }
    let captured = captured.ok_or_else(|| super::closure(ClosureError::Missing))?;
    if !matches!(captured.primary().kind, protocol::RootKind::File) {
        return bad(owner, ClosureError::Semantic);
    }
    let domain::ExpectedWorkflow::ModelOriginalsClient { byte_sources, .. } = paired.expected()
    else {
        return bad(owner, ClosureError::Semantic);
    };
    let mut record = None;
    for candidate in &byte_sources.0 {
        if owner
            .same_alias(&fixture.record, &candidate.alias)
            .map_err(super::closure)?
            && record.replace(&candidate.bytes).is_some()
        {
            return bad(owner, ClosureError::Ambiguous);
        }
    }
    let record = record.ok_or_else(|| super::closure(ClosureError::Missing))?;
    let record_raw = record_text(record, expansion, decode_owner)?;
    let record_doc = literal(&record_raw, decode_owner)?;
    core_credit(&record_raw, &record_doc, decode_owner)?;
    let declaration = member(&record_doc, "morphirModelOriginals", decode_owner)?;
    declared_root_credit(
        member(declaration, "companions", decode_owner)?,
        decode_owner,
    )?;
    let declaration = protocol::Declaration::from_compile_record(&record_raw)
        .map_err(|_| super::closure(ClosureError::Semantic))?;
    if captured.companions().len() != declaration.companions().len() {
        return bad(owner, ClosureError::Semantic);
    }
    for a in captured.companions() {
        let mut matches = 0;
        for b in declaration.companions() {
            if a.kind == b.kind && equal_path(a.path.as_str(), b.path.as_str(), decode_owner)? {
                matches += 1;
            }
        }
        if matches != 1 {
            return bad(owner, ClosureError::Semantic);
        }
    }
    let physical_primary = node_path(&fixture.nodes.0[primary_index]).as_str();
    let relative_primary = captured.primary().path.as_str();
    decode_owner
        .bytes(checked_add(physical_primary.len(), relative_primary.len())?)
        .map_err(decode)?;
    let Some(prefix) = physical_primary
        .strip_suffix(relative_primary)
        .and_then(|value| value.strip_suffix('/'))
    else {
        return bad(owner, ClosureError::Semantic);
    };
    root_credit(prefix, decode_owner)?;
    protocol::Root::directory(prefix).map_err(|_| super::closure(ClosureError::Semantic))?;
    let opaque = node_path(&fixture.nodes.0[opaque_index]).as_str();
    decode_owner
        .bytes(checked_add(opaque.len(), prefix.len())?)
        .map_err(decode)?;
    let Some(opaque) = opaque
        .strip_prefix(prefix)
        .and_then(|value| value.strip_prefix('/'))
    else {
        return bad(owner, ClosureError::Semantic);
    };
    let mut opaque_matches = 0;
    for root in declaration.companions() {
        if under(opaque, root, decode_owner)? {
            opaque_matches += 1
        }
    }
    if opaque_matches != 1 {
        return bad(owner, ClosureError::Semantic);
    }
    let mut sentinel = None;
    for (index, node) in fixture.nodes.0.iter().enumerate() {
        visit(owner)?;
        let FixtureNode::Literal { path, .. } = node else {
            continue;
        };
        decode_owner
            .bytes(checked_add(path.as_str().len(), prefix.len())?)
            .map_err(decode)?;
        let Some(relative) = path
            .as_str()
            .strip_prefix(prefix)
            .and_then(|value| value.strip_prefix('/'))
        else {
            continue;
        };
        root_credit(relative, decode_owner)?;
        protocol::Root::file(relative).map_err(|_| super::closure(ClosureError::Semantic))?;
        for root in std::iter::once(captured.primary()).chain(declaration.companions()) {
            if under(relative, root, decode_owner)? {
                return bad(owner, ClosureError::Semantic);
            }
        }
        if sentinel.replace(index).is_some() {
            return bad(owner, ClosureError::Ambiguous);
        }
    }
    let sentinel = sentinel.ok_or_else(|| super::closure(ClosureError::Missing))?;
    Ok(SourceWitnessRoles {
        nodes: [record_index, primary_index, sentinel],
    })
}
