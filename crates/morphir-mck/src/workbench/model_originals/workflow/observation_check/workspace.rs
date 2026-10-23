//! Pure source-correlated development workspace evidence. This is not a second
//! UI implementation, mounted owner, host grant or semantic-opening proof.
use super::*;
use crate::workbench::model_originals::workflow::identity_input::{
    ControllerCallKind, ControllerInput, IdentityInputPlan,
};
use std::io::{self, Write};

fn fault<T>(
    owner: &mut CompareOwner,
    index: usize,
    kind: ControllerFault,
) -> Result<T, ObservationError> {
    owner.refuse(ObservationError::Controller { index, kind })
}

/// Compare the maintained UI's exact JSON string-tuple spelling without an
/// owned intermediate key. Genuine input scan and emitted comparison bytes are
/// charged separately before their effects. No expected key reaches this helper.
struct KeySink<'owner, 'actual> {
    owner: &'owner mut CompareOwner,
    actual: &'actual [u8],
    offset: usize,
    equal: bool,
}
impl Write for KeySink<'_, '_> {
    fn write(&mut self, bytes: &[u8]) -> io::Result<usize> {
        self.owner.ready().map_err(|_| io::ErrorKind::Other)?;
        let Some(end) = self.offset.checked_add(bytes.len()) else {
            let _: Result<(), _> = self.owner.refuse(ObservationError::SizeOverflow);
            return Err(io::ErrorKind::Other.into());
        };
        let actual = self.actual.get(self.offset..end);
        let Some(upper) = bytes.len().checked_add(actual.map_or(0, <[u8]>::len)) else {
            let _: Result<(), _> = self.owner.refuse(ObservationError::SizeOverflow);
            return Err(io::ErrorKind::Other.into());
        };
        self.owner
            .charge(CompareResource::ComparisonBytes, upper)
            .map_err(|_| io::ErrorKind::Other)?;
        self.equal &= actual == Some(bytes);
        self.offset = end;
        Ok(bytes.len())
    }
    fn flush(&mut self) -> io::Result<()> {
        Ok(())
    }
}
fn canonical_key(
    source: &input::IdentitySourceSnapshot,
    path: Option<&str>,
    actual: &str,
    owner: &mut CompareOwner,
) -> Result<bool, ObservationError> {
    owner.ready()?;
    owner.visit()?;
    let Some(scan) = source
        .provider_id
        .0
        .len()
        .checked_add(source.locator.0.len())
        .and_then(|n| n.checked_add(path.map_or(0, str::len)))
    else {
        return owner.refuse(ObservationError::SizeOverflow);
    };
    owner.charge(CompareResource::ComparisonBytes, scan)?;
    let (encoded, equal) = {
        let mut sink = KeySink {
            owner,
            actual: actual.as_bytes(),
            offset: 0,
            equal: true,
        };
        let encoded = match path {
            Some(path) => serde_json::to_writer(
                &mut sink,
                &[
                    source.provider_id.0.as_str(),
                    source.locator.0.as_str(),
                    path,
                ],
            ),
            None => serde_json::to_writer(
                &mut sink,
                &[source.provider_id.0.as_str(), source.locator.0.as_str()],
            ),
        };
        (encoded, sink.equal && sink.offset == sink.actual.len())
    };
    owner.ready()?;
    if encoded.is_err() {
        return owner.refuse(ObservationError::UnqualifiedEvidence);
    }
    Ok(equal)
}

fn controller<'plan, 'source>(
    paired: &PairedWorkflow<'source>,
    plan: &'plan IdentityInputPlan<'source>,
    owner: &mut CompareOwner,
) -> Result<&'plan ControllerInput<'source>, ObservationError> {
    owner.ready()?;
    if !std::ptr::eq(plan.scenario(), paired.scenario()) {
        return identity_fault(owner, 0, IdentityFault::Plan);
    }
    for controller in plan.controllers() {
        owner.visit()?;
        if controller.run == paired.run_index() {
            return Ok(controller);
        }
    }
    fault(owner, 0, ControllerFault::UnsupportedInput)
}

fn invocations(
    plan: &ControllerInput<'_>,
    actual: &[observed::WorkspaceInvocation],
    owner: &mut CompareOwner,
) -> Result<(), ObservationError> {
    owner.visit()?;
    if actual.len() < plan.calls.len() {
        return fault(owner, actual.len(), ControllerFault::MissingInvocation);
    }
    if actual.len() > plan.calls.len() {
        return fault(
            owner,
            plan.calls.len(),
            ControllerFault::UnexpectedInvocation,
        );
    }
    for (index, (input, actual)) in plan.calls.iter().zip(actual).enumerate() {
        owner.visit()?;
        if !matches!(
            (input.kind, &actual.kind),
            (
                ControllerCallKind::Inspect,
                observed::WorkspaceInvocationKind::Inspect
            ) | (
                ControllerCallKind::LoadDevelopment,
                observed::WorkspaceInvocationKind::LoadDevelopment
            )
        ) {
            return fault(owner, index, ControllerFault::InvocationOrder);
        }
        if !same_snapshot(input.source, &actual.source_snapshot, owner)? {
            return fault(owner, index, ControllerFault::SourceBinding);
        }
        if !owner.same_text(&input.reply.0, &actual.reply.0)? {
            return fault(owner, index, ControllerFault::InvocationOrder);
        }
    }
    Ok(())
}

fn checkpoint_sources(
    paired: &PairedWorkflow<'_>,
    identity: &IdentityInputPlan<'_>,
    plan: &ControllerInput<'_>,
    checkpoint: &observed::WorkspaceCheckpoint,
    index: usize,
    owner: &mut CompareOwner,
) -> Result<(), ObservationError> {
    owner.visit()?;
    if checkpoint.entries.0.len() != plan.entries.len() || !checkpoint.recent_keys.0.is_empty() {
        return fault(owner, index, ControllerFault::SourceBinding);
    }
    for (entry, source) in checkpoint.entries.0.iter().zip(plan.entries.iter().rev()) {
        owner.visit()?;
        if !same_snapshot(source, &entry.source_snapshot, owner)? {
            return fault(owner, index, ControllerFault::SourceBinding);
        }
        if !canonical_key(source, None, &entry.key.0, owner)? {
            return fault(owner, index, ControllerFault::Key);
        }
        for project in &entry.projects.0 {
            owner.visit()?;
            let mut matched = false;
            for binding in identity.bindings() {
                owner.visit()?;
                if binding.run_index() != paired.run_index() {
                    continue;
                }
                if let input::IdentitySubject::ProjectKey {
                    source_snapshot,
                    relative_path,
                } = binding.subject()
                    && owner.same_text(&source.provider_id.0, &source_snapshot.provider_id.0)?
                    && owner.same_text(&source.locator.0, &source_snapshot.locator.0)?
                    && owner.same_text(&relative_path.0, &project.relative_path.0)?
                {
                    if !canonical_key(
                        source_snapshot,
                        Some(&relative_path.0),
                        &project.key.0,
                        owner,
                    )? {
                        return fault(owner, index, ControllerFault::Key);
                    }
                    matched = true;
                    break;
                }
            }
            if !matched {
                return fault(owner, index, ControllerFault::Project);
            }
        }
    }
    let Some(last) = plan.fixture.initial_sources.0.last() else {
        return fault(owner, index, ControllerFault::UnsupportedInput);
    };
    let Some(active) = &checkpoint.active_key.0 else {
        return fault(owner, index, ControllerFault::Key);
    };
    if !canonical_key(last, None, &active.0, owner)? {
        return fault(owner, index, ControllerFault::Key);
    }
    Ok(())
}

fn checkpoints(
    paired: &PairedWorkflow<'_>,
    identity: &IdentityInputPlan<'_>,
    plan: &ControllerInput<'_>,
    actions: &[ClientAction],
    checkpoints: &[observed::WorkspaceCheckpoint],
    owner: &mut CompareOwner,
) -> Result<(), ObservationError> {
    let mut position = 0usize;
    for (index, checkpoint) in checkpoints.iter().enumerate() {
        owner.visit()?;
        for previous in &checkpoints[..index] {
            owner.visit()?;
            if owner.same(&previous.name, &checkpoint.name)? {
                return fault(owner, index, ControllerFault::Checkpoint);
            }
        }
        let mut found = false;
        while position < actions.len() {
            owner.visit()?;
            let action = &actions[position];
            position += 1;
            if let ClientAction::Checkpoint { name } = action {
                if !owner.same(name, &checkpoint.name)? {
                    return fault(owner, index, ControllerFault::Checkpoint);
                }
                found = true;
                break;
            }
        }
        if !found {
            return fault(owner, index, ControllerFault::Checkpoint);
        }
        checkpoint_sources(paired, identity, plan, checkpoint, index, owner)?;
    }
    for action in &actions[position..] {
        owner.visit()?;
        if matches!(action, ClientAction::Checkpoint { .. }) {
            return fault(owner, checkpoints.len(), ControllerFault::Checkpoint);
        }
    }
    Ok(())
}

pub(super) fn predicate(
    name: &FixtureAlias,
    active_key: &Nullable<super::super::Text<0, { usize::MAX }>>,
    entries: &[domain::IdentityControllerEntry],
    recent_keys: &[super::super::Text<0, { usize::MAX }>],
    checkpoints: &[observed::WorkspaceCheckpoint],
    owner: &mut CompareOwner,
) -> Result<bool, ObservationError> {
    let mut actual = None;
    for checkpoint in checkpoints {
        owner.visit()?;
        if owner.same(name, &checkpoint.name)? {
            actual = Some(checkpoint);
            break;
        }
    }
    let Some(actual) = actual else {
        return fault(owner, checkpoints.len(), ControllerFault::Checkpoint);
    };
    owner.visit()?;
    match (&active_key.0, &actual.active_key.0) {
        (None, None) => {}
        (Some(a), Some(b)) if owner.same_text(&a.0, &b.0)? => {}
        _ => return Ok(false),
    }
    if entries.len() != actual.entries.0.len() || recent_keys.len() != actual.recent_keys.0.len() {
        return Ok(false);
    }
    for (expected, actual) in entries.iter().zip(&actual.entries.0) {
        owner.visit()?;
        if !owner.same_text(&expected.key.0, &actual.key.0)?
            || !same_snapshot(&expected.source_snapshot, &actual.source_snapshot, owner)?
            || expected.projects.0.len() != actual.projects.0.len()
        {
            return Ok(false);
        }
        // Both development/ready constants were validated by the same decoder.
        for (expected, actual) in expected.projects.0.iter().zip(&actual.projects.0) {
            owner.visit()?;
            if !owner.same_text(&expected.key.0, &actual.key.0)?
                || !owner.same_text(&expected.name.0, &actual.name.0)?
                || !owner.same_text(&expected.relative_path.0, &actual.relative_path.0)?
            {
                return Ok(false);
            }
        }
    }
    for (expected, actual) in recent_keys.iter().zip(&actual.recent_keys.0) {
        owner.visit()?;
        if !owner.same_text(&expected.0, &actual.0)? {
            return Ok(false);
        }
    }
    Ok(true)
}

pub(super) fn check<'source, 'actual>(
    paired: &PairedWorkflow<'source>,
    identity: Option<&IdentityInputPlan<'source>>,
    actual: &'actual observed::Observation,
    owner: &mut CompareOwner,
) -> Result<ComparedPredicates<'source, 'actual>, ObservationError> {
    owner.ready()?;
    let (
        PairedRun::Client { actions, fixture },
        domain::ExpectedWorkflow::ModelOriginalsClient {
            checks,
            qualification,
            outcome: expected_outcome,
            ..
        },
        observed::Observation::WorkspaceClient {
            checkpoints: actual_checkpoints,
            identity_results,
            provider_invocations,
            outcome,
            ..
        },
    ) = (paired.run(), paired.expected(), actual)
    else {
        return owner.refuse(ObservationError::Role);
    };
    if matches!(
        qualification,
        domain::ExpectedWorkflowModelOriginalsClientQualification::Blocked { .. }
    ) {
        return owner.refuse(ObservationError::ExpectedBlocked);
    }
    let Some(identity) = identity else {
        return owner.refuse(ObservationError::IdentityInputActionMissing);
    };
    let controller = controller(paired, identity, owner)?;
    if !fixture.files.0.is_empty()
        || !fixture.literal_peers.0.is_empty()
        || !matches!(&fixture.mode, input::ClientFixtureMode::IdentityController { controller: input } if std::ptr::eq(input, controller.fixture))
    {
        return owner.refuse(ObservationError::UnqualifiedEvidence);
    }
    for action in actions {
        owner.visit()?;
        if !matches!(
            action,
            ClientAction::Checkpoint { .. } | ClientAction::ObserveIdentity { .. }
        ) {
            return owner.refuse(ObservationError::UnqualifiedEvidence);
        }
    }
    // Bind genuine source/action/sample/checkpoint first, preserving the named
    // identity diagnostics before comparing any independently authored keys.
    correlate_identity(
        paired,
        Some(identity),
        Some(&identity_results.0),
        actions,
        owner,
    )?;
    invocations(controller, &provider_invocations.0, owner)?;
    checkpoints(
        paired,
        identity,
        controller,
        actions,
        &actual_checkpoints.0,
        owner,
    )?;
    for (index, result) in identity_results.0.iter().enumerate() {
        owner.visit()?;
        let (_, action, _, _, _, key) = identity_parts(result);
        for binding in identity.bindings() {
            owner.visit()?;
            if binding.run_index() == paired.run_index()
                && u64::try_from(binding.action_index()).ok() == Some(action)
            {
                let (source, path) = match binding.subject() {
                    input::IdentitySubject::SourceKey { source_snapshot } => {
                        (source_snapshot, None)
                    }
                    input::IdentitySubject::ProjectKey {
                        source_snapshot,
                        relative_path,
                    } => (source_snapshot, Some(relative_path.0.as_str())),
                };
                if !canonical_key(source, path, key, owner)? {
                    return fault(owner, index, ControllerFault::Key);
                }
                break;
            }
        }
    }
    let mut checked = 0usize;
    for (index, check) in checks.0.iter().enumerate() {
        owner.visit()?;
        if !matches!(
            check,
            ExpectedClientCheck::IdentityKey { .. }
                | ExpectedClientCheck::IdentityLocationRelation { .. }
                | ExpectedClientCheck::IdentityController { .. }
        ) {
            return owner.refuse(ObservationError::UnsupportedClientCheck { index });
        }
        super::predicate(
            index,
            check,
            &identity_results.0,
            &[],
            Some(&actual_checkpoints.0),
            None,
            owner,
        )?;
        let Some(next) = checked.checked_add(1) else {
            return owner.refuse(ObservationError::SizeOverflow);
        };
        checked = next;
    }
    owner.visit()?;
    match expected_outcome {
        domain::ExpectedWorkflowModelOriginalsClientOutcome::Clean { final_checkpoint } => {
            let Some(last) = actual_checkpoints.0.last() else {
                return owner.refuse(ObservationError::Outcome);
            };
            if !owner.same(final_checkpoint, &outcome.final_checkpoint)?
                || !owner.same(&outcome.final_checkpoint, &last.name)?
            {
                return owner.refuse(ObservationError::Outcome);
            }
        }
        _ => return owner.refuse(ObservationError::UnsupportedOutcome),
    }
    // Disposed and all three zero ownership counters are closed decoded
    // constants, not fabricated product release or worker-exit evidence.
    owner.visit()?;
    Ok(ComparedPredicates {
        scenario: paired.scenario(),
        expected: paired.expected(),
        actual,
        checked,
    })
}

#[cfg(test)]
mod tests;
