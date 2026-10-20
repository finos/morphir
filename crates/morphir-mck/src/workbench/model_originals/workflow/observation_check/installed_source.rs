//! Conditional source/worker claim consistency. These DATA checks issue no
//! live source grant and cannot prove authenticity of a saved observation.
use super::*;
use crate::workbench::model_originals::workflow::native_original::{
    FileRole, SourceMeasurements, WorkerMeasurements,
};

fn span(length: usize, owner: &mut CompareOwner) -> Result<u64> {
    u64::try_from(length).map_err(|_| *owner.fault.get_or_insert(ObservationError::SizeOverflow))
}

/// Read minima come only from the already recipe-verified selected PRIMARY
/// stream and adopted record. Companion bytes are excluded from the primary.
fn verified_spans(
    actual: &InstalledClientMeasurements,
    owner: &mut CompareOwner,
) -> Result<(u64, u64)> {
    let facts = actual.protocol.as_ref().map_err(|fault| {
        *owner
            .fault
            .get_or_insert(ObservationError::InstalledClient(*fault))
    })?;
    let mut primary = None;
    for stream in &facts.streams {
        owner.visit()?;
        if owner.same_text(facts.capture.primary().path.as_str(), &stream.path)? {
            primary = Some(span(stream.bytes.len(), owner)?);
        }
    }
    let mut record = None;
    for event in &actual.wire.host.events.0 {
        owner.visit()?;
        if let SocketEvent::ReadyRecordAdopted { bytes } = &event.event {
            record = Some(span(bytes.bytes().len(), owner)?);
        }
    }
    match (primary, record) {
        (Some(primary), Some(record)) => Ok((primary, record)),
        _ => owner.refuse(ObservationError::InstalledClient(Fault::SourceWitness)),
    }
}

pub(super) fn check(
    plan: &InstalledClientPlan<'_>,
    actual: &InstalledClientMeasurements,
    owner: &mut CompareOwner,
) -> Result<()> {
    use super::super::server::{read_counts, valid_read_prefix, worker_counts};

    let sealed = match &actual.wire.host.source {
        SourceMeasurements::SealedComplete { counts, files } => Some((counts, files)),
        _ => None,
    };
    if let Some((counts, files)) = sealed {
        valid_read_prefix(
            counts,
            owner,
            ObservationError::InstalledClient(Fault::SourceCoverage),
        )?;
        require!(
            owner,
            files.0.len() == plan.witnesses().len(),
            Fault::SourceWitness
        )?;
        let (primary_length, record_length) = verified_spans(actual, owner)?;
        let mut seen = [false; 3];
        let mut witnessed = [0u64; 3];
        for file in &files.0 {
            owner.visit()?;
            let role_index = match file.role {
                FileRole::CompileRecord => 0,
                FileRole::OriginalPrimary => 1,
                FileRole::UndeclaredSentinel => 2,
            };
            require!(owner, !seen[role_index], Fault::SourceWitness)?;
            seen[role_index] = true;
            let mut matched = false;
            for (role, path) in plan.witnesses() {
                owner.visit()?;
                if role == file.role {
                    matched = owner.same_text(file.path.0.as_str(), path.as_str())?;
                    break;
                }
            }
            require!(owner, matched, Fault::SourceWitness)?;
            for ((aggregate, value), total) in witnessed
                .iter_mut()
                .zip(read_counts(&file.reads))
                .zip(read_counts(&counts.total))
            {
                *aggregate = aggregate
                    .checked_add(value)
                    .ok_or_else(|| *owner.fault.get_or_insert(ObservationError::SizeOverflow))?;
                require!(owner, *aggregate <= total, Fault::SourceWitness)?;
            }
            let valid = match file.role {
                FileRole::UndeclaredSentinel => read_counts(&file.reads) == [0; 3],
                FileRole::CompileRecord => {
                    file.reads.attempts.0 > 0
                        && file.reads.read_calls.0 > 0
                        && file.reads.returned_bytes.0 >= record_length
                }
                FileRole::OriginalPrimary => {
                    file.reads.attempts.0 > 0
                        && file.reads.read_calls.0 > 0
                        && file.reads.returned_bytes.0 >= primary_length
                }
            };
            require!(owner, valid, Fault::SourceWitness)?;
        }
        require!(
            owner,
            seen.into_iter().all(|present| present),
            Fault::SourceWitness
        )?;
    }

    match &actual.wire.host.workers {
        WorkerMeasurements::JoinedCleanup { counts } => {
            worker_counts(
                counts,
                owner,
                ObservationError::InstalledClient(Fault::WorkerCoverage),
            )?;
            // The preceding factual predicates verified a successful
            // selected capture, PRIMARY stream and adopted record regardless
            // of whether source measurements claim a complete or open view.
            require!(
                owner,
                counts.returned_ok.0 > 0 && counts.joined_ok.0 > 0,
                Fault::WorkerCoverage
            )?;
        }
        _ if sealed.is_some() => {
            return owner.refuse(ObservationError::InstalledClient(Fault::WorkerCoverage));
        }
        _ => {}
    }
    Ok(())
}
