//! Source-bound factual consistency only. No serialized claim issues live authority.
use super::super::{
    domain,
    installed_client::{Action, Command, InstalledClientPlan},
    installed_measurements::*,
    pairing::PairedWorkflow,
};
use super::{CompareOwner, CompareResource, InstalledClientFault as Fault, ObservationError};
use crate::json::strict::Document;
use crate::workbench::model_originals as protocol;
use sha2::{Digest, Sha256};
type Result<T> = std::result::Result<T, ObservationError>;
fn require_value(owner: &mut CompareOwner, yes: bool, fault: Fault) -> Result<()> {
    owner.charge(CompareResource::Checks, 1)?;
    if yes {
        Ok(())
    } else {
        owner.refuse(ObservationError::InstalledClient(fault))
    }
}
macro_rules! require {
    ($owner:expr,$yes:expr,$fault:expr) => {{
        let yes = $yes;
        require_value($owner, yes, $fault)
    }};
}
fn field<'a>(
    doc: &'a Document,
    key: &str,
    owner: &mut CompareOwner,
) -> Result<Option<&'a Document>> {
    if let Document::Object(fields) = doc {
        for (name, value) in fields {
            owner.visit()?;
            if owner.same_text(name, key)? {
                return Ok(Some(value));
            }
        }
    }
    Ok(None)
}
fn at<'a>(
    doc: &'a Document,
    keys: &[&str],
    owner: &mut CompareOwner,
) -> Result<Option<&'a Document>> {
    let mut result = Some(doc);
    for key in keys {
        result = match result {
            Some(value) => field(value, key, owner)?,
            None => None,
        }
    }
    Ok(result)
}
fn word(doc: &Document, keys: &[&str], wanted: &str, owner: &mut CompareOwner) -> Result<bool> {
    match at(doc, keys, owner)?.and_then(text) {
        Some(value) => owner.same_text(value, wanted),
        None => Ok(false),
    }
}
fn numeric(doc: &Document, keys: &[&str], wanted: u64, owner: &mut CompareOwner) -> Result<bool> {
    Ok(at(doc, keys, owner)?.and_then(number) == Some(wanted))
}
fn recipe(
    bytes: &domain::Bytes,
    actual: &[u8],
    owner: &mut CompareOwner,
    fault: Fault,
) -> Result<()> {
    let expected = expected_recipe(bytes, owner)?;
    owner.charge(CompareResource::ComparisonBytes, actual.len())?;
    let yes = expected
        .expected()
        .is_ok_and(|expected| expected.matches(actual));
    require!(owner, yes, fault)
}
/// Borrow the existing expected-domain recipe into the SAME FixtureBytes
/// mechanism. This adapter performs no byte generation or independent digest.
fn expected_recipe(
    value: &domain::Bytes,
    owner: &mut CompareOwner,
) -> Result<protocol::FixtureBytes> {
    use protocol::fixture_bytes::RecipePart;
    fn atomic(value: &domain::AtomicBytes) -> RecipePart<'_> {
        match value {
            domain::AtomicBytes::Utf8 { text } => RecipePart::Utf8(text.as_str()),
            domain::AtomicBytes::Hex { hex } => RecipePart::Hex(hex.as_str()),
            domain::AtomicBytes::RepeatU8 { byte, length } => RecipePart::Repeat {
                byte: byte.0 as u8,
                length: length.0 as usize,
            },
            domain::AtomicBytes::CycleU8 { seed, length } => RecipePart::Cycle {
                seed: seed.0 as u8,
                length: length.0 as usize,
            },
            domain::AtomicBytes::ChunkIndexedU8 { seed, length } => RecipePart::ChunkIndexed {
                seed: seed.0 as u8,
                length: length.0 as usize,
            },
        }
    }
    owner.visit()?;
    let count = match value {
        domain::Bytes::Concat { parts } => parts.0.len(),
        _ => 1,
    };
    let header = count
        .checked_mul(std::mem::size_of::<RecipePart<'_>>())
        .ok_or_else(|| *owner.fault.get_or_insert(ObservationError::SizeOverflow))?;
    owner.preflight_owned_text(header)?;
    let mut parts = Vec::new();
    parts.try_reserve_exact(count).map_err(|_| {
        *owner
            .fault
            .get_or_insert(ObservationError::InstalledClient(Fault::SourceBinding))
    })?;
    match value {
        domain::Bytes::Utf8 { text } => parts.push(RecipePart::Utf8(text.as_str())),
        domain::Bytes::Hex { hex } => parts.push(RecipePart::Hex(hex.as_str())),
        domain::Bytes::RepeatU8 { byte, length } => parts.push(RecipePart::Repeat {
            byte: byte.0 as u8,
            length: length.0 as usize,
        }),
        domain::Bytes::CycleU8 { seed, length } => parts.push(RecipePart::Cycle {
            seed: seed.0 as u8,
            length: length.0 as usize,
        }),
        domain::Bytes::ChunkIndexedU8 { seed, length } => parts.push(RecipePart::ChunkIndexed {
            seed: seed.0 as u8,
            length: length.0 as usize,
        }),
        domain::Bytes::Concat { parts: source } => {
            for part in &source.0 {
                owner.visit()?;
                parts.push(atomic(part))
            }
        }
    }
    let mut length = 0usize;
    for part in &parts {
        owner.visit()?;
        let size = match part {
            RecipePart::Utf8(text) => text.len(),
            RecipePart::Hex(hex) => hex.len() / 2,
            RecipePart::Repeat { length, .. }
            | RecipePart::Cycle { length, .. }
            | RecipePart::ChunkIndexed { length, .. } => *length,
        };
        length = length
            .checked_add(size)
            .ok_or_else(|| *owner.fault.get_or_insert(ObservationError::SizeOverflow))?;
    }
    owner.preflight_owned_text(length)?;
    protocol::FixtureBytes::from_typed_parts(&parts, protocol::evidence::MAX_SOURCE_BYTES).map_err(
        |_| {
            *owner
                .fault
                .get_or_insert(ObservationError::InstalledClient(Fault::SourceBinding))
        },
    )
}
fn frame(actual: &InstalledClientMeasurements, index: usize) -> Option<&Document> {
    actual
        .frames
        .iter()
        .find(|f| f.event == index)
        .and_then(|f| f.document.as_ref())
}
#[derive(Clone, Copy)]
enum Pending {
    Idle,
    Received(usize),
    Prepared(usize),
}
fn events(actual: &InstalledClientMeasurements, owner: &mut CompareOwner) -> Result<()> {
    let events = &actual.wire.host.events.0;
    for (index, event) in events.iter().enumerate() {
        owner.visit()?;
        require!(
            owner,
            event.sequence.get() == index as u64,
            Fault::SocketOrder
        )?;
        if let SocketEvent::AuthenticatedConnection {} = event.event {
            for earlier in &events[..index] {
                owner.visit()?;
                require!(
                    owner,
                    earlier.connection != event.connection,
                    Fault::SocketAssociation
                )?;
            }
            let mut pending = Pending::Idle;
            let mut initialized = false;
            let mut opened = false;
            let mut adopted = false;
            for (i, item) in events.iter().enumerate().skip(index + 1) {
                owner.visit()?;
                if item.connection != event.connection {
                    continue;
                }
                match &item.event {
                    SocketEvent::AuthenticatedConnection {} => {
                        return require!(owner, false, Fault::SocketAssociation);
                    }
                    SocketEvent::ReceivedText { .. } => {
                        require!(owner, matches!(pending, Pending::Idle), Fault::SocketOrder)?;
                        let doc = frame(actual, i).ok_or_else(|| {
                            *owner.fault.get_or_insert(ObservationError::InstalledClient(
                                Fault::SocketFrame,
                            ))
                        })?;
                        require!(
                            owner,
                            word(doc, &["jsonrpc"], "2.0", owner)?,
                            Fault::SocketFrame
                        )?;
                        let method = field(doc, "method", owner)?.and_then(text);
                        match method {
                            Some("morphir.session.initialize") => {
                                require!(
                                    owner,
                                    !initialized
                                        && numeric(doc, &["params", "protocolVersion"], 1, owner)?
                                        && word(
                                            doc,
                                            &["params", "sessionId"],
                                            actual.wire.host.selection.session_id.as_str(),
                                            owner
                                        )?,
                                    Fault::SocketFrame
                                )?;
                                initialized = true;
                            }
                            Some("morphir.workspace.open") => {
                                require!(
                                    owner,
                                    initialized
                                        && !opened
                                        && source(doc, &["params", "source"], actual, owner)?,
                                    Fault::SocketFrame
                                )?;
                                opened = true;
                            }
                            Some(method) if method.starts_with("morphir.model-originals.") => {
                                require!(owner, opened, Fault::SocketFrame)?
                            }
                            _ => return require!(owner, false, Fault::SocketFrame),
                        }
                        pending = Pending::Received(i);
                        adopted = false;
                    }
                    SocketEvent::ReadyRecordAdopted { .. } => {
                        let Pending::Received(received) = pending else {
                            return require!(owner, false, Fault::SocketOrder);
                        };
                        let capture = match frame(actual, received) {
                            Some(doc) => {
                                word(doc, &["method"], "morphir.model-originals.capture", owner)?
                            }
                            None => false,
                        };
                        require!(owner, !adopted && capture, Fault::SocketOrder)?;
                        adopted = true;
                    }
                    SocketEvent::PreparedSend { .. } => {
                        let Pending::Received(received) = pending else {
                            return require!(owner, false, Fault::SocketOrder);
                        };
                        let Some(request) = frame(actual, received) else {
                            return require!(owner, false, Fault::SocketFrame);
                        };
                        let Some(reply) = frame(actual, i) else {
                            return require!(owner, false, Fault::SocketFrame);
                        };
                        let request_id = field(request, "id", owner)?.and_then(number);
                        let reply_id = field(reply, "id", owner)?.and_then(number);
                        require!(
                            owner,
                            request_id.is_some()
                                && request_id == reply_id
                                && word(reply, &["jsonrpc"], "2.0", owner)?
                                && field(reply, "result", owner)?.is_some()
                                && field(reply, "error", owner)?.is_none(),
                            Fault::SocketFrame
                        )?;
                        if word(request, &["method"], "morphir.session.initialize", owner)? {
                            require!(
                                owner,
                                numeric(reply, &["result", "protocolVersion"], 1, owner)?,
                                Fault::SocketFrame
                            )?;
                        }
                        if word(request, &["method"], "morphir.workspace.open", owner)? {
                            let Some(Document::Array(projects)) =
                                at(reply, &["result", "snapshot", "projects"], owner)?
                            else {
                                return require!(owner, false, Fault::SocketFrame);
                            };
                            let mut selected = false;
                            for project in projects {
                                owner.visit()?;
                                selected |= word(
                                    project,
                                    &["id"],
                                    actual.wire.host.selection.project_id.as_str(),
                                    owner,
                                )?;
                            }
                            require!(owner, selected, Fault::SocketFrame)?;
                            require!(
                                owner,
                                source(reply, &["result", "snapshot", "root"], actual, owner)?
                                    && word(
                                        reply,
                                        &["result", "snapshot", "state"],
                                        "open",
                                        owner
                                    )?,
                                Fault::SocketFrame
                            )?;
                        }
                        pending = Pending::Prepared(i);
                    }
                    SocketEvent::SendOutcome {
                        prepared_sequence,
                        outcome,
                    } => {
                        let Pending::Prepared(prepared) = pending else {
                            return require!(owner, false, Fault::SocketOrder);
                        };
                        require!(
                            owner,
                            prepared_sequence.get() == prepared as u64,
                            Fault::SocketOrder
                        )?;
                        require!(
                            owner,
                            matches!(outcome, SendCompletion::Completed),
                            Fault::SendOutcome
                        )?;
                        pending = Pending::Idle;
                    }
                }
            }
            require!(
                owner,
                matches!(pending, Pending::Idle) && opened,
                Fault::SocketOrder
            )?;
        } else {
            let mut authenticated = false;
            for earlier in &events[..index] {
                owner.visit()?;
                if earlier.connection == event.connection
                    && matches!(earlier.event, SocketEvent::AuthenticatedConnection {})
                {
                    authenticated = true;
                    break;
                }
            }
            require!(owner, authenticated, Fault::SocketAssociation)?;
        }
    }
    Ok(())
}
fn source(
    doc: &Document,
    keys: &[&str],
    actual: &InstalledClientMeasurements,
    owner: &mut CompareOwner,
) -> Result<bool> {
    let Some(source) = at(doc, keys, owner)? else {
        return Ok(false);
    };
    Ok(word(
        source,
        &["providerId"],
        actual.wire.host.selection.source.provider.as_str(),
        owner,
    )? && word(
        source,
        &["locator"],
        actual.wire.host.selection.source.locator.as_str(),
        owner,
    )?)
}
fn processes(
    plan: &InstalledClientPlan<'_>,
    actual: &InstalledClientMeasurements,
    owner: &mut CompareOwner,
) -> Result<u64> {
    let mut count = 0;
    let mut publish = None;
    for (index, action) in plan.actions().enumerate() {
        owner.visit()?;
        if let Action::Run { command, .. } = action {
            let Some(process) = actual.wire.processes.0.get(count) else {
                return owner.refuse(ObservationError::InstalledClient(Fault::ProcessOrder));
            };
            require!(
                owner,
                process.action_index.0 == index as u64
                    && matches!(
                        (command, &process.command),
                        (Command::Connect, ProcessCommand::Connect)
                            | (Command::List, ProcessCommand::List)
                            | (Command::Publish, ProcessCommand::Publish)
                    ),
                Fault::ProcessOrder
            )?;
            require!(
                owner,
                matches!(
                    process.completion,
                    DirectProcessCompletion::Finished {
                        exit: ProcessExit::Code {
                            value: super::super::Natural(0)
                        }
                    }
                ),
                Fault::ProcessOutcome
            )?;
            if matches!(command, Command::Publish) {
                publish = Some(index as u64)
            }
            count += 1;
        }
    }
    require!(
        owner,
        count == actual.wire.processes.0.len(),
        Fault::ProcessOrder
    )?;
    publish.ok_or_else(|| {
        *owner
            .fault
            .get_or_insert(ObservationError::InstalledClient(Fault::SourceBinding))
    })
}
fn snapshot(
    plan: &InstalledClientPlan<'_>,
    actual: &InstalledClientMeasurements,
    publish: u64,
    owner: &mut CompareOwner,
) -> Result<()> {
    let wire = &actual.wire;
    let destination = &wire.destination;
    let prefix = wire.published_relative_root.as_str();
    let mut file_count = 0usize;
    require!(
        owner,
        matches!(destination.coverage, SnapshotCoverage::Complete)
            && destination.after_action.0 == publish,
        Fault::DestinationCoverage
    )?;
    for (index, entry) in destination.raw_entries.0.iter().enumerate() {
        owner.visit()?;
        owner.preflight_owned_text(entry.path().len().saturating_add(prefix.len()))?;
        for earlier in &destination.raw_entries.0[..index] {
            owner.visit()?;
            require!(
                owner,
                !owner.same_text(entry.path(), earlier.path())?,
                Fault::DestinationEntries
            )?;
        }
        let mut parent = entry.path();
        while let Some(boundary) = parent.rfind('/') {
            owner.preflight_owned_text(parent.len())?;
            parent = &parent[..boundary];
            let mut present = false;
            for possible in &destination.raw_entries.0 {
                owner.visit()?;
                if matches!(possible, CensusEntry::PhysicalDirectory { .. })
                    && owner.same_text(possible.path(), parent)?
                {
                    present = true;
                    break;
                }
            }
            require!(owner, present, Fault::DestinationEntries)?;
        }
        let relative = entry
            .path()
            .strip_prefix(prefix)
            .and_then(|v| v.strip_prefix('/'));
        match entry {
            CensusEntry::File { bytes, .. } => {
                file_count = file_count
                    .checked_add(1)
                    .ok_or_else(|| *owner.fault.get_or_insert(ObservationError::SizeOverflow))?;
                let mut found = None;
                for (path, recipe) in plan.files() {
                    owner.visit()?;
                    if relative.is_some_and(|v| v == path.as_str()) {
                        found = Some(recipe);
                        break;
                    }
                }
                let Some(wanted) = found else {
                    return require!(owner, false, Fault::DestinationEntries);
                };
                recipe(wanted, bytes.bytes(), owner, Fault::DestinationBytes)?;
                let mut summary = None;
                for item in &destination.files.0 {
                    owner.visit()?;
                    if owner.same_text(item.path.as_str(), entry.path())? {
                        require!(owner, summary.is_none(), Fault::DestinationEntries)?;
                        summary = Some(item)
                    }
                }
                let Some(summary) = summary else {
                    return require!(owner, false, Fault::DestinationEntries);
                };
                owner.charge(CompareResource::ComparisonBytes, bytes.bytes().len())?;
                let digest: [u8; 32] = Sha256::digest(bytes.bytes()).into();
                require!(
                    owner,
                    summary.byte_length.0 == bytes.bytes().len() as u64
                        && summary.sha256.0 == digest,
                    Fault::DestinationBytes
                )?;
            }
            CensusEntry::PhysicalDirectory { .. } => {
                let mut parent = entry.path() == prefix;
                for (path, _) in plan.files() {
                    owner.visit()?;
                    if let Some(relative) = relative {
                        parent |= path
                            .as_str()
                            .strip_prefix(relative)
                            .is_some_and(|v| v.starts_with('/'))
                    }
                }
                require!(owner, parent, Fault::DestinationEntries)?;
            }
        }
    }
    require!(
        owner,
        file_count == plan.files().len() && destination.files.0.len() == file_count,
        Fault::DestinationEntries
    )?;
    for (path, _) in plan.files() {
        let mut count = 0;
        for entry in &destination.raw_entries.0 {
            owner.visit()?;
            if let CensusEntry::File { .. } = entry
                && entry
                    .path()
                    .strip_prefix(prefix)
                    .and_then(|v| v.strip_prefix('/'))
                    == Some(path.as_str())
            {
                count += 1
            }
        }
        require!(owner, count == 1, Fault::DestinationEntries)?;
    }
    require!(
        owner,
        matches!(wire.scratch.coverage, SnapshotCoverage::Complete)
            && wire.scratch.after_action.0 == publish,
        Fault::ScratchCoverage
    )?;
    require!(
        owner,
        wire.scratch.raw_entries.0.is_empty() && wire.scratch.files.0.is_empty(),
        Fault::ScratchEntries
    )
}
fn claims(actual: &InstalledClientMeasurements, owner: &mut CompareOwner) -> Result<()> {
    for (index, process) in actual.wire.processes.0.iter().enumerate() {
        owner.visit()?;
        let Some(doc) = actual.claims.get(index).and_then(|v| v.as_ref()) else {
            return require!(owner, false, Fault::ProcessClaims);
        };
        require!(
            owner,
            word(doc, &["contractVersion"], "0.1.0", owner)?
                && word(doc, &["binding"], "workbench-http", owner)?,
            Fault::ProcessClaims
        )?;
        match process.command {
            ProcessCommand::Connect => require!(
                owner,
                word(doc, &["operation"], "connect", owner)?
                    && matches!(field(doc, "connected", owner)?, Some(Document::Bool(true)))
                    && word(
                        doc,
                        &["sessionId"],
                        actual.wire.host.selection.session_id.as_str(),
                        owner
                    )?,
                Fault::ProcessClaims
            )?,
            ProcessCommand::List => require!(
                owner,
                word(doc, &["operation"], "list", owner)?
                    && word(doc, &["observation"], "discovered", owner)?
                    && source(doc, &["source"], actual, owner)?,
                Fault::ProcessClaims
            )?,
            ProcessCommand::Publish => {
                require!(
                    owner,
                    word(doc, &["operation"], "originals", owner)?
                        && word(doc, &["observation"], "published", owner)?
                        && word(doc, &["publication"], "cli", owner)?
                        && word(doc, &["representation"], "original-bytes", owner)?
                        && word(doc, &["cleanup", "kind"], "released", owner)?,
                    Fault::ProcessClaims
                )?;
                let Some(Document::Array(paths)) = field(doc, "published", owner)? else {
                    return require!(owner, false, Fault::ProcessClaims);
                };
                let expected_root = actual.wire.destination.root.as_str();
                let expected_relative = actual.wire.published_relative_root.as_str();
                let Some(path) = paths.first().and_then(text) else {
                    return require!(owner, false, Fault::ProcessClaims);
                };
                owner.charge(
                    CompareResource::ComparisonBytes,
                    path.len()
                        .saturating_add(expected_root.len())
                        .saturating_add(expected_relative.len()),
                )?;
                require!(
                    owner,
                    paths.len() == 1
                        && path
                            .strip_prefix(expected_root)
                            .and_then(|v| v.strip_prefix('/'))
                            == Some(expected_relative),
                    Fault::ProcessClaims
                )?;
            }
        }
    }
    Ok(())
}
fn digest_matches(
    value: Option<&Document>,
    bytes: &[u8],
    owner: &mut CompareOwner,
) -> Result<bool> {
    owner.charge(CompareResource::ComparisonBytes, bytes.len())?;
    let digest: [u8; 32] = Sha256::digest(bytes).into();
    let mut encoded = [0u8; 64];
    let digits = b"0123456789abcdef";
    for (i, byte) in digest.iter().enumerate() {
        encoded[2 * i] = digits[usize::from(byte >> 4)];
        encoded[2 * i + 1] = digits[usize::from(byte & 15)];
    }
    owner.charge(CompareResource::ComparisonBytes, 128)?;
    Ok(value
        .and_then(text)
        .is_some_and(|value| value.as_bytes() == encoded))
}
fn same_scalar(
    left: Option<&Document>,
    right: Option<&Document>,
    owner: &mut CompareOwner,
) -> Result<bool> {
    owner.visit()?;
    match (left, right) {
        (Some(Document::String(a)), Some(Document::String(b))) => owner.same_text(a, b),
        (Some(Document::Number(a)), Some(Document::Number(b))) => {
            owner.same_text(a.as_str(), b.as_str())
        }
        (Some(Document::Bool(a)), Some(Document::Bool(b))) => Ok(a == b),
        (Some(Document::Null), Some(Document::Null)) => Ok(true),
        _ => Ok(false),
    }
}
/// Corroborate emitted claims with retained literal protocol facts. These
/// comparisons establish consistency, never dynamic publication/acceptance.
fn corroborate(
    plan: &InstalledClientPlan<'_>,
    actual: &InstalledClientMeasurements,
    owner: &mut CompareOwner,
) -> Result<()> {
    let mut ready = None;
    for (i, event) in actual.wire.host.events.0.iter().enumerate() {
        owner.visit()?;
        if let SocketEvent::ReadyRecordAdopted { bytes } = &event.event {
            for (j, next) in actual.wire.host.events.0.iter().enumerate().skip(i + 1) {
                owner.visit()?;
                if next.connection == event.connection
                    && matches!(next.event, SocketEvent::PreparedSend { .. })
                {
                    let doc = frame(actual, j).ok_or_else(|| {
                        *owner
                            .fault
                            .get_or_insert(ObservationError::InstalledClient(Fault::RecordAdoption))
                    })?;
                    require!(
                        owner,
                        numeric(
                            doc,
                            &["result", "origin", "record", "byteLength"],
                            bytes.bytes().len() as u64,
                            owner
                        )?,
                        Fault::RecordAdoption
                    )?;
                    let digest = at(doc, &["result", "origin", "record", "sha256"], owner)?;
                    require!(
                        owner,
                        digest_matches(digest, bytes.bytes(), owner)?,
                        Fault::RecordAdoption
                    )?;
                    require!(
                        owner,
                        word(
                            doc,
                            &["result", "origin", "record", "module"],
                            plan.module(),
                            owner
                        )?,
                        Fault::SourceBinding
                    )?;
                    ready = Some(doc);
                    break;
                }
            }
        }
    }
    let Some(ready) = ready else {
        return require!(owner, false, Fault::RecordAdoption);
    };
    let Some(claim) = actual.claims.last().and_then(|v| v.as_ref()) else {
        return require!(owner, false, Fault::ProcessClaims);
    };
    for key in ["fileCount", "directoryCount", "sourceByteLength"] {
        let a = at(claim, &[key], owner)?;
        let b = at(ready, &["result", "inventory", key], owner)?;
        require!(owner, same_scalar(a, b, owner)?, Fault::ProcessClaims)?;
    }
    let a = at(claim, &["inventorySha256"], owner)?;
    let b = at(ready, &["result", "inventory", "sha256"], owner)?;
    require!(owner, same_scalar(a, b, owner)?, Fault::ProcessClaims)?;
    for key in ["status", "release"] {
        let a = at(claim, &["sourceFormatVersion", key], owner)?;
        let b = at(ready, &["result", "sourceFormatVersion", key], owner)?;
        if a.is_some() || b.is_some() {
            require!(owner, same_scalar(a, b, owner)?, Fault::ProcessClaims)?;
        }
    }
    for (index, process) in actual.wire.processes.0.iter().enumerate() {
        owner.visit()?;
        let Some(doc) = actual.claims[index].as_ref() else {
            return require!(owner, false, Fault::ProcessClaims);
        };
        match process.command {
            ProcessCommand::Connect => {
                let Some(Document::Array(sources)) = field(doc, "sources", owner)? else {
                    return require!(owner, false, Fault::ProcessClaims);
                };
                let mut found = false;
                for item in sources {
                    owner.visit()?;
                    found |= source(item, &[], actual, owner)?;
                }
                require!(owner, found, Fault::ProcessClaims)?;
            }
            ProcessCommand::List => {
                let Some(Document::Array(projects)) = field(doc, "projects", owner)? else {
                    return require!(owner, false, Fault::ProcessClaims);
                };
                let mut found = false;
                for item in projects {
                    owner.visit()?;
                    found |= word(
                        item,
                        &["projectId"],
                        actual.wire.host.selection.project_id.as_str(),
                        owner,
                    )?;
                }
                require!(owner, found, Fault::ProcessClaims)?;
            }
            ProcessCommand::Publish => {}
        }
    }
    Ok(())
}
pub(in crate::workbench::model_originals::workflow) fn check(
    paired: &PairedWorkflow<'_>,
    plan: Option<&InstalledClientPlan<'_>>,
    actual: &InstalledClientMeasurements,
    owner: &mut CompareOwner,
) -> Result<()> {
    owner.ready()?;
    owner.visit()?;
    let Some(plan) = plan else {
        return owner.refuse(ObservationError::InstalledClient(Fault::SourceBinding));
    };
    let publish = processes(plan, actual, owner)?;
    events(actual, owner)?;
    let facts = match &actual.protocol {
        Ok(facts) => facts,
        Err(fault) => return owner.refuse(ObservationError::InstalledClient(*fault)),
    };
    require!(
        owner,
        matches!(facts.request.parameters(),protocol::Parameters::Capture{source,project,scope:protocol::CaptureScope::Complete,semantic:protocol::SemanticRequest::None} if source==&actual.wire.host.selection.source&&project==&actual.wire.host.selection.project_id),
        Fault::SocketFrame
    )?;
    let entries = facts.inventory.inventory().entries();
    require!(
        owner,
        entries.len() == plan.files().len() && facts.streams.len() == plan.files().len(),
        Fault::SocketFrame
    )?;
    let Some((primary, _)) = plan.files().next() else {
        return require!(owner, false, Fault::SourceBinding);
    };
    require!(
        owner,
        facts.capture.primary().kind == protocol::RootKind::File
            && owner.same_text(facts.capture.primary().path.as_str(), primary.as_str())?,
        Fault::SocketFrame
    )?;
    let companion = plan.companion();
    require!(
        owner,
        facts.capture.companions().len() == 1
            && facts.capture.companions()[0].kind == protocol::RootKind::File
            && owner.same_text(
                facts.capture.companions()[0].path.as_str(),
                companion.path.as_str()
            )?,
        Fault::SocketFrame
    )?;
    for (path, wanted) in plan.files() {
        owner.visit()?;
        let mut stream = None;
        for candidate in &facts.streams {
            owner.visit()?;
            if owner.same_text(path.as_str(), &candidate.path)? {
                require!(owner, stream.is_none(), Fault::SocketFrame)?;
                stream = Some(candidate)
            }
        }
        let Some(stream) = stream else {
            return require!(owner, false, Fault::SocketFrame);
        };
        recipe(wanted, &stream.bytes, owner, Fault::SocketFrame)?;
        if owner.same_text(path.as_str(), companion.path.as_str())? {
            owner.charge(CompareResource::ComparisonBytes, stream.bytes.len())?;
            let digest: [u8; 32] = Sha256::digest(&stream.bytes).into();
            require!(
                owner,
                stream.bytes.len() as u64 == companion.length.0 && digest == companion.sha.0,
                Fault::SocketFrame
            )?;
        }
    }
    let mut records = 0;
    for event in &actual.wire.host.events.0 {
        owner.visit()?;
        if let SocketEvent::ReadyRecordAdopted { bytes } = &event.event {
            recipe(
                plan.record_bytes(),
                bytes.bytes(),
                owner,
                Fault::RecordAdoption,
            )?;
            records += 1
        }
    }
    require!(owner, records == 1, Fault::RecordAdoption)?;
    snapshot(plan, actual, publish, owner)?;
    claims(actual, owner)?;
    corroborate(plan, actual, owner)?;
    if matches!(
        paired.expected(),
        domain::ExpectedWorkflow::ModelOriginalsClient {
            qualification: domain::ExpectedWorkflowModelOriginalsClientQualification::Blocked { .. },
            ..
        }
    ) {
        owner.refuse(ObservationError::ExpectedBlocked)
    } else {
        owner.refuse(ObservationError::UnqualifiedEvidence)
    }
}
