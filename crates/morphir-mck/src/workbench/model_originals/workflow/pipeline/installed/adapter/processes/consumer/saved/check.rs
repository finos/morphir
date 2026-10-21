//! Corroboration inside the existing installed checker, using its SAME owner.
use super::*;
use crate::workbench::model_originals::workflow::observation_check::{
    CompareOwner, CompareResource, InstalledClientFault as Fault, ObservationError,
};
use sha2::{Digest, Sha256};
type Result<T> = std::result::Result<T, ObservationError>;
macro_rules! need {
    ($owner:expr,$yes:expr,$fault:expr) => {{
        let yes = $yes;
        check($owner, yes, $fault)
    }};
}
pub(super) fn check(owner: &mut CompareOwner, yes: bool, fault: Fault) -> Result<()> {
    owner.charge(CompareResource::Checks, 1)?;
    if yes {
        Ok(())
    } else {
        owner.refuse(ObservationError::InstalledClient(fault))
    }
}
fn operand_length(path: &wire::Operand) -> usize {
    match path {
        wire::Operand::UnixBytes {
            bytes: wire::LiteralBytes::Utf8 { text },
        } => text.0.len(),
        wire::Operand::UnixBytes {
            bytes: wire::LiteralBytes::Hex { hex },
        } => hex.as_str().len() / 2,
    }
}
fn path_bytes(path: &wire::Operand) -> impl Iterator<Item = u8> + '_ {
    let wire::Operand::UnixBytes { bytes } = path;
    let text = match bytes {
        wire::LiteralBytes::Utf8 { text } => Some(text.0.as_bytes().iter().copied()),
        _ => None,
    };
    let hex = match bytes {
        wire::LiteralBytes::Hex { hex } => {
            Some(hex.as_str().as_bytes().chunks_exact(2).map(|pair| {
                let digit = |b: u8| if b <= b'9' { b - b'0' } else { b - b'a' + 10 };
                digit(pair[0]) * 16 + digit(pair[1])
            }))
        }
        _ => None,
    };
    text.into_iter().flatten().chain(hex.into_iter().flatten())
}
fn matches_bytes(
    path: &wire::Operand,
    wanted: impl Iterator<Item = u8>,
    length: usize,
    owner: &mut CompareOwner,
) -> Result<bool> {
    owner.charge(
        CompareResource::ComparisonBytes,
        operand_length(path)
            .checked_add(length)
            .ok_or(ObservationError::SizeOverflow)?,
    )?;
    Ok(path_bytes(path).eq(wanted))
}
fn same_operand(
    a: &model::implementation::OsOperand,
    b: &model::implementation::OsOperand,
    owner: &mut CompareOwner,
) -> Result<bool> {
    match (a, b) {
        (
            model::implementation::OsOperand::UnixBytes { bytes: a },
            model::implementation::OsOperand::UnixBytes { bytes: b },
        ) => {
            owner.charge(
                CompareResource::ComparisonBytes,
                a.bytes()
                    .len()
                    .checked_add(b.bytes().len())
                    .ok_or(ObservationError::SizeOverflow)?,
            )?;
            Ok(a.bytes() == b.bytes())
        }
        _ => Ok(false),
    }
}
fn matches_operand(
    path: &wire::Operand,
    actual: &model::implementation::OsOperand,
    owner: &mut CompareOwner,
) -> Result<bool> {
    match actual {
        model::implementation::OsOperand::UnixBytes { bytes } => matches_bytes(
            path,
            bytes.bytes().iter().copied(),
            bytes.bytes().len(),
            owner,
        ),
        _ => Ok(false),
    }
}
fn complete_output(output: &wire::Output, nonempty: bool) -> bool {
    matches!(output,wire::Output::Owned{read:wire::OutputRead::Complete{length},disposal:wire::Disposal::Disposed{}} if !nonempty||length.value()>0)
}
fn same_fact(a: &wire::Fact, b: &wire::Fact, owner: &mut CompareOwner) -> Result<bool> {
    Ok(match (a, b) {
        (
            wire::Fact::Release {
                request: a,
                capture: ac,
                binding: ab,
                request_sha: aq,
                reply_sha: ar,
            },
            wire::Fact::Release {
                request: b,
                capture: bc,
                binding: bb,
                request_sha: bq,
                reply_sha: br,
            },
        ) => {
            a.value() == b.value()
                && owner.same_text(&ac.0, &bc.0)?
                && owner.same_text(&ab.session.0, &bb.session.0)?
                && owner.same_text(&ab.provider.0, &bb.provider.0)?
                && owner.same_text(&ab.source.0, &bb.source.0)?
                && owner.same_text(&ab.project.0, &bb.project.0)?
                && owner.same_text(aq.as_str(), bq.as_str())?
                && owner.same_text(ar.as_str(), br.as_str())?
        }
        (
            wire::Fact::Commit {
                path: a,
                policy: ap,
                outcome: ao,
            },
            wire::Fact::Commit {
                path: b,
                policy: bp,
                outcome: bo,
            },
        ) => ap == bp && ao == bo && matches_bytes(a, path_bytes(b), operand_length(b), owner)?,
        (
            wire::Fact::Cleanup {
                path: a,
                outcome: ao,
            },
            wire::Fact::Cleanup {
                path: b,
                outcome: bo,
            },
        ) => ao == bo && matches_bytes(a, path_bytes(b), operand_length(b), owner)?,
        _ => false,
    })
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
fn text_at<'a>(
    doc: &'a Document,
    keys: &[&str],
    owner: &mut CompareOwner,
) -> Result<Option<&'a str>> {
    let mut value = Some(doc);
    for key in keys {
        value = match value {
            Some(v) => field(v, key, owner)?,
            None => None,
        };
    }
    Ok(value.and_then(model::text))
}
fn word(doc: &Document, keys: &[&str], wanted: &str, owner: &mut CompareOwner) -> Result<bool> {
    match text_at(doc, keys, owner)? {
        Some(actual) => owner.same_text(actual, wanted),
        None => Ok(false),
    }
}
impl Measurement {
    pub(in crate::workbench::model_originals::workflow) fn check(
        &self,
        actual: &model::InstalledClientMeasurements,
        owner: &mut CompareOwner,
    ) -> Result<()> {
        owner.ready()?;
        let mut found = None;
        for process in &actual.wire.processes.0 {
            owner.visit()?;
            if process.process_ordinal.0 == self.record.association.process.0 {
                need!(owner, found.is_none(), Fault::ConsumerAssociation)?;
                found = Some(process);
            }
        }
        let Some(process) = found else {
            return need!(owner, false, Fault::ConsumerAssociation);
        };
        let binding = association(&self.record, process, &actual.wire.implementation, owner)?;
        let launch = binding.launch;
        need!(
            owner,
            matches!(self.record.completion, Completion::Drained {}),
            Fault::ConsumerTranscript
        )?;
        let mut facts: [Option<(&wire::Fact, &Role, u64)>; 3] = [None, None, None];
        let mut roles = [false, false];
        for endpoint in &self.record.endpoints.0 {
            owner.visit()?;
            let index = if endpoint.role == Role::Outer { 0 } else { 1 };
            need!(owner, !roles[index], Fault::ConsumerTranscript)?;
            roles[index] = true;
            need!(
                owner,
                matches!(endpoint.terminal, Terminal::Drained {}) && endpoint.fault.0.is_none(),
                Fault::ConsumerTranscript
            )?;
            let mut business = 0;
            let mut closed = false;
            let mut helper_started = false;
            for (position, row) in endpoint.frames.0.iter().enumerate() {
                owner.visit()?;
                let frame = &row.frame;
                need!(
                    owner,
                    !closed
                        && frame.sequence() == position as u64
                        && owner.same_text(frame.version(), wire::VERSION)?,
                    Fault::ConsumerTranscript
                )?;
                let digits = frame.sequence().checked_ilog10().unwrap_or(0) as u64 + 1;
                let total = 4
                    + b"{\"kind\":\"retained\",\"version\":\"".len() as u64
                    + wire::VERSION.len() as u64
                    + b"\",\"sequence\":".len() as u64
                    + digits
                    + 1;
                need!(
                    owner,
                    matches!(row.delivery,Delivery::Written{total:Natural(value)}if value==total),
                    Fault::ConsumerTranscript
                )?;
                if position == 0 {
                    need!(
                        owner,
                        matches!(frame, wire::Frame::Open { .. }),
                        Fault::ConsumerTranscript
                    )?;
                    continue;
                }
                match frame {
                    wire::Frame::Fact { fact, .. } => {
                        business += 1;
                        let slot = match fact {
                            wire::Fact::Release { .. } => 0,
                            wire::Fact::Commit { .. } => 1,
                            wire::Fact::Cleanup { .. } => 2,
                        };
                        need!(
                            owner,
                            facts[slot].is_none() && (slot == 0) == (endpoint.role == Role::Helper),
                            Fault::ConsumerTranscript
                        )?;
                        facts[slot] = Some((fact, &endpoint.role, frame.sequence()));
                    }
                    wire::Frame::Close {
                        attempted,
                        started,
                        retained,
                        helper,
                        ..
                    } => {
                        need!(
                            owner,
                            attempted.0 == business
                                && started.0 == business
                                && retained.0 == business,
                            Fault::ConsumerTranscript
                        )?;
                        close_helper(
                            launch,
                            helper,
                            helper_started,
                            &endpoint.role,
                            HelperExpectation::Successful,
                            owner,
                        )?;
                        closed = true;
                    }
                    wire::Frame::HelperStarted {
                        launch: delegated, ..
                    } => {
                        started_helper(&binding, delegated, helper_started, &endpoint.role, owner)?;
                        helper_started = true;
                    }
                    _ => return need!(owner, false, Fault::ConsumerTranscript),
                }
            }
            need!(
                owner,
                closed
                    && endpoint.frames.0.len() <= if endpoint.role == Role::Outer { 5 } else { 3 },
                Fault::ConsumerTranscript
            )?;
        }
        for (slot, dynamic) in [&self.release, &self.commit, &self.cleanup]
            .iter()
            .enumerate()
        {
            let Some((fact, role, sequence)) = facts[slot] else {
                return need!(owner, false, Fault::ConsumerTranscript);
            };
            let Dynamic::Observed {
                reference,
                fact: projection,
            } = dynamic
            else {
                return need!(owner, false, Fault::ConsumerTranscript);
            };
            need!(
                owner,
                reference.role == *role
                    && reference.sequence.0 == sequence
                    && same_fact(fact, projection, owner)?,
                Fault::ConsumerTranscript
            )?;
        }
        if let Some((fact @ wire::Fact::Release { .. }, _, _)) = facts[0] {
            release(
                fact,
                &actual.wire.host.selection,
                &actual.wire.host.events.0,
                &actual.frames,
                &actual.protocol,
                owner,
            )?;
        }
        if let Some((wire::Fact::Commit { path, outcome, .. }, _, _)) = facts[1] {
            let model::implementation::ImplementationObservation::Observed {
                command_paths, ..
            } = &actual.wire.implementation
            else {
                unreachable!()
            };
            let model::implementation::OsOperand::UnixBytes { bytes: destination } =
                &command_paths.destination
            else {
                return need!(owner, false, Fault::ConsumerCommit);
            };
            let relative = actual.wire.published_relative_root.as_str().as_bytes();
            let length = destination
                .bytes()
                .len()
                .checked_add(1)
                .and_then(|n| n.checked_add(relative.len()))
                .ok_or(ObservationError::SizeOverflow)?;
            need!(
                owner,
                matches!(outcome, wire::Outcome::Returned)
                    && matches_bytes(
                        path,
                        destination
                            .bytes()
                            .iter()
                            .copied()
                            .chain(Some(b'/'))
                            .chain(relative.iter().copied()),
                        length,
                        owner
                    )?,
                Fault::ConsumerCommit
            )?;
        }
        if let Some((wire::Fact::Cleanup { path, outcome }, _, _)) = facts[2] {
            let root = actual.wire.scratch.root.as_str().as_bytes();
            owner.charge(
                CompareResource::ComparisonBytes,
                operand_length(path)
                    .checked_add(root.len())
                    .ok_or(ObservationError::SizeOverflow)?,
            )?;
            let mut actual = path_bytes(path);
            let mut within = root.iter().copied().all(|byte| actual.next() == Some(byte));
            within &= actual.next() == Some(b'/');
            let mut n = 0;
            let mut dots = true;
            let mut any = false;
            for byte in actual.chain(Some(b'/')) {
                if byte == b'/' {
                    within &= n > 0 && !(dots && n <= 2);
                    any = true;
                    n = 0;
                    dots = true;
                } else {
                    within &= byte != 0;
                    n += 1;
                    dots &= byte == b'.';
                }
            }
            need!(
                owner,
                matches!(outcome, wire::Outcome::Returned) && within && any,
                Fault::ConsumerCleanup
            )?;
        }
        Ok(())
    }
}

pub(super) struct HelperBinding<'a> {
    pub(super) launch: &'a model::implementation::LaunchObservation,
    runtime: &'a model::implementation::OsOperand,
    directory: &'a model::implementation::OsOperand,
    helper: &'a model::implementation::OsOperand,
}
pub(super) fn association<'a>(
    record: &'a Record,
    process: &model::ProcessMeasurement,
    implementation: &'a model::implementation::ImplementationObservation,
    owner: &mut CompareOwner,
) -> Result<HelperBinding<'a>> {
    need!(
        owner,
        process.process_ordinal.0 == record.association.process.0,
        Fault::ConsumerAssociation
    )?;
    // The ordinary checker has already bound this actual process to the
    // compiled Publish action. Use that actual index, not a copied index.
    need!(
        owner,
        process.action_index.0 == record.association.action.0
            && matches!(process.command, model::ProcessCommand::Publish),
        Fault::ConsumerAssociation
    )?;
    let model::implementation::ImplementationObservation::Observed {
        runtime,
        launch,
        package,
        ..
    } = implementation
    else {
        return refuse(owner, Fault::ConsumerAssociation);
    };
    let (bound_runtime, bound_directory, bound_helper) = match &record.association.launch {
        Launch::NodePackage {
            runtime: bound,
            entry,
            helper,
            directory,
        } => {
            let model::implementation::LaunchObservation::NodePackage {
                entry: actual_entry,
            } = launch
            else {
                return refuse(owner, Fault::ConsumerAssociation);
            };
            need!(
                owner,
                same_operand(entry, actual_entry, owner)?,
                Fault::ConsumerAssociation
            )?;
            (bound, directory, helper)
        }
        Launch::NativeExecutable {
            program,
            runtime: bound,
            helper,
            directory,
        } => {
            let model::implementation::LaunchObservation::NativeExecutable {
                program: actual_program,
                ..
            } = launch
            else {
                return refuse(owner, Fault::ConsumerAssociation);
            };
            need!(
                owner,
                same_operand(program, actual_program, owner)?,
                Fault::ConsumerAssociation
            )?;
            (bound, directory, helper)
        }
    };
    need!(
        owner,
        same_operand(bound_runtime, &runtime.program, owner)?
            && same_operand(bound_directory, &process.directory, owner)?,
        Fault::ConsumerAssociation
    )?;
    let helper_ok = match (bound_helper, &package.root) {
        (
            model::implementation::OsOperand::UnixBytes { bytes: helper },
            model::implementation::OsOperand::UnixBytes { bytes: root },
        ) => {
            let tail = b"/build-provider/originals.mjs";
            owner.charge(
                CompareResource::ComparisonBytes,
                helper
                    .bytes()
                    .len()
                    .checked_add(root.bytes().len())
                    .and_then(|n| n.checked_add(tail.len()))
                    .ok_or(ObservationError::SizeOverflow)?,
            )?;
            helper.bytes().iter().copied().eq(root
                .bytes()
                .iter()
                .copied()
                .chain(tail.iter().copied()))
        }
        _ => false,
    };
    need!(owner, helper_ok, Fault::ConsumerAssociation)?;
    let Clock::Issued {
        at,
        end,
        numer,
        denom,
        ..
    } = &record.clock
    else {
        return refuse(owner, Fault::ConsumerClock);
    };
    owner.charge(CompareResource::ComparisonBytes, 64)?;
    need!(
        owner,
        runtime.byte_length.0 == super::super::candidate::SELECTED_LENGTH
            && runtime.sha256.0 == super::super::candidate::SELECTED_SHA
            && numer.0 == 125
            && denom.0 == 3
            && at.0 < end.0
            && end.0 <= u64::MAX / 3,
        Fault::ConsumerClock
    )?;
    Ok(HelperBinding {
        launch,
        runtime: bound_runtime,
        directory: bound_directory,
        helper: bound_helper,
    })
}

pub(super) fn release(
    fact: &wire::Fact,
    selected: &model::SelectedRuntimeData,
    events: &[model::SequencedSocketEvent],
    frames: &[model::ParsedFrame],
    protocol: &std::result::Result<model::ProtocolFacts, Fault>,
    owner: &mut CompareOwner,
) -> Result<()> {
    if let wire::Fact::Release {
        request,
        capture,
        binding,
        request_sha,
        reply_sha,
    } = fact
    {
        need!(
            owner,
            owner.same_text(&binding.session.0, selected.session_id.as_str())?
                && owner.same_text(&binding.provider.0, selected.source.provider.as_str())?
                && owner.same_text(&binding.source.0, selected.source.locator.as_str())?
                && owner.same_text(&binding.project.0, selected.project_id.as_str())?,
            Fault::ConsumerRelease
        )?;
        // Use the exact validated exchange. IDs may be reused by another
        // connection or by an earlier completed request on this connection.
        let protocol = match protocol {
            Ok(facts) => facts,
            Err(_) => return need!(owner, false, Fault::ConsumerRelease),
        };
        let mut received = None;
        let mut reply = None;
        for cached in frames {
            owner.visit()?;
            let event = &events[cached.event];
            if event.connection.get() != protocol.connection
                || !protocol.release_events.contains(&cached.event)
            {
                continue;
            }
            let Some(document) = &cached.document else {
                continue;
            };
            if field(document, "id", owner)?.and_then(model::number) != Some(request.value()) {
                continue;
            }
            match &event.event {
                model::SocketEvent::ReceivedText { payload } => {
                    need!(
                        owner,
                        received.is_none()
                            && word(
                                document,
                                &["method"],
                                "morphir.model-originals.release",
                                owner
                            )?
                            && word(document, &["params", "captureId"], &capture.0, owner)?,
                        Fault::ConsumerRelease
                    )?;
                    received = Some((payload.text(), event.connection.get()));
                }
                model::SocketEvent::PreparedSend { payload } => {
                    need!(
                        owner,
                        reply.is_none()
                            && word(document, &["result", "status"], "released", owner)?
                            && word(document, &["result", "captureId"], &capture.0, owner)?,
                        Fault::ConsumerRelease
                    )?;
                    reply = Some((payload.text(), event.connection.get()));
                }
                _ => {}
            }
        }
        let (Some((received, connection)), Some((reply, other))) = (received, reply) else {
            return need!(owner, false, Fault::ConsumerRelease);
        };
        need!(owner, connection == other, Fault::ConsumerRelease)?;
        for (raw, wanted) in [(received, request_sha), (reply, reply_sha)] {
            owner.charge(
                CompareResource::ComparisonBytes,
                raw.len()
                    .checked_add(64)
                    .ok_or(ObservationError::SizeOverflow)?,
            )?;
            let digest = Sha256::digest(raw.as_bytes());
            let mut matches = true;
            for (pair, byte) in wanted.as_str().as_bytes().chunks_exact(2).zip(digest) {
                let d = |b: u8| if b <= b'9' { b - b'0' } else { b - b'a' + 10 };
                matches &= d(pair[0]) * 16 + d(pair[1]) == byte;
            }
            need!(owner, matches, Fault::ConsumerRelease)?;
        }
    }
    Ok(())
}

fn refuse<T>(owner: &mut CompareOwner, fault: Fault) -> Result<T> {
    owner.charge(CompareResource::Checks, 1)?;
    owner.refuse(ObservationError::InstalledClient(fault))
}

#[derive(Clone, Copy)]
pub(super) enum HelperExpectation {
    Retained,
    Successful,
}
pub(super) fn close_helper(
    launch: &model::implementation::LaunchObservation,
    helper: &wire::HelperCompletion,
    helper_started: bool,
    role: &Role,
    expectation: HelperExpectation,
    owner: &mut CompareOwner,
) -> Result<()> {
    // These are the SAME scalar/output invariants required before live cache
    // retention. A truthful helper failure is DATA, not helper success.
    match helper {
        wire::HelperCompletion::Started {
            wait,
            stdout,
            stderr,
        } => {
            owner.visit()?;
            if let wire::Wait::Failed { code } = wait {
                need!(owner, wire::positive(code).is_ok(), Fault::ConsumerHelper)?;
            }
            helper_outputs(stdout, stderr, owner)?;
        }
        wire::HelperCompletion::LaunchFailed { stdout, stderr, .. } => {
            helper_outputs(stdout, stderr, owner)?
        }
        _ => {}
    }
    if matches!(role, Role::Helper) {
        need!(
            owner,
            matches!(helper, wire::HelperCompletion::NotApplicable {}),
            Fault::ConsumerTranscript
        )?;
    } else {
        match (launch, helper) {
            (
                model::implementation::LaunchObservation::NodePackage { .. },
                wire::HelperCompletion::InProcess {},
            ) => need!(owner, !helper_started, Fault::ConsumerAssociation)?,
            (
                model::implementation::LaunchObservation::NativeExecutable { .. },
                wire::HelperCompletion::Started {
                    wait,
                    stdout,
                    stderr,
                },
            ) => {
                need!(owner, helper_started, Fault::ConsumerAssociation)?;
                if matches!(expectation, HelperExpectation::Successful) {
                    need!(
                        owner,
                        matches!(wait,wire::Wait::Waited{status}if status.is_zero())
                            && complete_output(stdout, true)
                            && complete_output(stderr, false),
                        Fault::ConsumerHelper
                    )?;
                }
            }
            (
                model::implementation::LaunchObservation::NativeExecutable { .. },
                wire::HelperCompletion::NotAttempted {}
                | wire::HelperCompletion::LaunchFailed { .. },
            ) if matches!(expectation, HelperExpectation::Retained) => {
                need!(owner, !helper_started, Fault::ConsumerAssociation)?
            }
            _ => return need!(owner, false, Fault::ConsumerAssociation),
        }
    }
    Ok(())
}
pub(super) fn started_helper(
    binding: &HelperBinding<'_>,
    delegated: &wire::Launch,
    helper_started: bool,
    role: &Role,
    owner: &mut CompareOwner,
) -> Result<()> {
    need!(
        owner,
        matches!(role, Role::Outer)
            && !helper_started
            && matches!(
                binding.launch,
                model::implementation::LaunchObservation::NativeExecutable { .. }
            ),
        Fault::ConsumerAssociation
    )?;
    need!(
        owner,
        matches_operand(&delegated.program, binding.runtime, owner)?
            && matches_operand(&delegated.directory, binding.directory, owner)?
            && delegated.arguments.0.len() == 3,
        Fault::ConsumerAssociation
    )?;
    let arguments = &delegated.arguments.0;
    need!(
        owner,
        matches_operand(&arguments[0], binding.helper, owner)?
            && matches_bytes(
                &arguments[1],
                b"--morphir-originals-v1".iter().copied(),
                b"--morphir-originals-v1".len(),
                owner
            )?,
        Fault::ConsumerAssociation
    )?;
    owner.charge(
        CompareResource::ComparisonBytes,
        operand_length(&arguments[2]),
    )?;
    let mut config = path_bytes(&arguments[2]);
    need!(
        owner,
        config.next() == Some(b'/') && config.all(|byte| byte != 0),
        Fault::ConsumerAssociation
    )?;
    Ok(())
}
fn helper_outputs(
    stdout: &wire::Output,
    stderr: &wire::Output,
    owner: &mut CompareOwner,
) -> Result<()> {
    for output in [stdout, stderr] {
        owner.visit()?;
        need!(
            owner,
            wire::validate_output(output).is_ok(),
            Fault::ConsumerHelper
        )?;
    }
    Ok(())
}
pub(super) fn published_success(
    process: &model::ProcessMeasurement,
    claim: Option<&Document>,
    owner: &mut CompareOwner,
) -> Result<HelperExpectation> {
    owner.visit()?;
    if matches!(
        process.completion,
        model::DirectProcessCompletion::Finished {
            exit: model::ProcessExit::Code { value: Natural(0) }
        }
    ) && let Some(claim) = claim
        && word(claim, &["operation"], "originals", owner)?
        && word(claim, &["observation"], "published", owner)?
    {
        Ok(HelperExpectation::Successful)
    } else {
        Ok(HelperExpectation::Retained)
    }
}
