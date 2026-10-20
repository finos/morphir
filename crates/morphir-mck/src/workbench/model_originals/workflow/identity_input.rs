//! One source-borrowing plan, issued once per paired case. This is not an
//! observation, a UI invocation, source provenance, or runtime authority.
use super::FixtureAlias;
use super::input::{ClientAction, IdentitySubject, Run, Scenario};
use super::pairing::PairedWorkflow;
use super::work::{ClosureError, ClosureOwner, Resource};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(super) enum IdentityInputError {
    Work(ClosureError),
    MissingCheckpoint {
        run: usize,
        action: usize,
    },
    DuplicateSample {
        run: usize,
        action: usize,
    },
    Controller {
        run: usize,
        source: usize,
        kind: ControllerInputFault,
    },
}
#[derive(Debug)]
pub(super) struct IdentityBinding<'source> {
    run: usize,
    action: usize,
    checkpoint_index: usize,
    checkpoint: &'source FixtureAlias,
    sample: &'source FixtureAlias,
    subject: &'source IdentitySubject,
}
impl<'source> IdentityBinding<'source> {
    pub(super) fn run_index(&self) -> usize {
        self.run
    }
    pub(super) fn action_index(&self) -> usize {
        self.action
    }
    pub(super) fn checkpoint_index(&self) -> usize {
        self.checkpoint_index
    }
    pub(super) fn checkpoint(&self) -> &'source FixtureAlias {
        self.checkpoint
    }
    pub(super) fn sample(&self) -> &'source FixtureAlias {
        self.sample
    }
    pub(super) fn subject(&self) -> &'source IdentitySubject {
        self.subject
    }
}
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(super) enum ControllerInputFault {
    Provider,
    DuplicateProvider,
    Reply,
    EmptyLocator,
}
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(super) enum ControllerCallKind {
    Inspect,
    LoadDevelopment,
}
#[derive(Debug)]
pub(super) struct ControllerCall<'source> {
    pub(super) kind: ControllerCallKind,
    pub(super) source: &'source super::input::IdentitySourceSnapshot,
    pub(super) reply: &'source super::RawJson,
}
#[derive(Debug)]
pub(super) struct ControllerInput<'source> {
    pub(super) run: usize,
    pub(super) fixture: &'source super::input::IdentityControllerFixture,
    /// First successfully initialized location, in insertion order. The actual
    /// controller presents distinct locations in reverse insertion order.
    pub(super) entries: Vec<&'source super::input::IdentitySourceSnapshot>,
    pub(super) calls: Vec<ControllerCall<'source>>,
}
fn controller_text(
    left: &str,
    right: &str,
    owner: &mut ClosureOwner,
) -> Result<bool, IdentityInputError> {
    owner.ready().map_err(IdentityInputError::Work)?;
    let Some(upper) = left.len().checked_add(right.len()) else {
        return owner
            .refuse(ClosureError::SizeOverflow)
            .map_err(IdentityInputError::Work);
    };
    owner
        .charge(Resource::LookupBytes, upper)
        .map_err(IdentityInputError::Work)?;
    Ok(left == right)
}
fn controller_location(
    left: &super::input::IdentitySourceSnapshot,
    right: &super::input::IdentitySourceSnapshot,
    owner: &mut ClosureOwner,
) -> Result<bool, IdentityInputError> {
    Ok(
        controller_text(&left.provider_id.0, &right.provider_id.0, owner)?
            && controller_text(&left.locator.0, &right.locator.0, owner)?,
    )
}
fn controller_snapshot(
    left: &super::input::IdentitySourceSnapshot,
    right: &super::input::IdentitySourceSnapshot,
    owner: &mut ClosureOwner,
) -> Result<bool, IdentityInputError> {
    Ok(controller_location(left, right, owner)?
        && controller_text(&left.display_name.0, &right.display_name.0, owner)?
        && matches!(
            (&left.persistence, &right.persistence),
            (super::Presence::Absent, super::Presence::Absent)
                | (super::Presence::Present(_), super::Presence::Present(_))
        ))
}
fn controller_fault<T>(
    run: usize,
    source: usize,
    kind: ControllerInputFault,
) -> Result<T, IdentityInputError> {
    Err(IdentityInputError::Controller { run, source, kind })
}
fn controller_increment(
    value: usize,
    owner: &mut ClosureOwner,
) -> Result<usize, IdentityInputError> {
    owner.ready().map_err(IdentityInputError::Work)?;
    match value.checked_add(1) {
        Some(next) => Ok(next),
        None => owner
            .refuse(ClosureError::SizeOverflow)
            .map_err(IdentityInputError::Work),
    }
}
impl<'source> ControllerInput<'source> {
    fn new(
        run: usize,
        fixture: &'source super::input::IdentityControllerFixture,
        owner: &mut ClosureOwner,
    ) -> Result<Self, IdentityInputError> {
        owner.ready().map_err(IdentityInputError::Work)?;
        let mut entries: Vec<&'source super::input::IdentitySourceSnapshot> = Vec::new();
        let mut calls = Vec::new();
        for (index, provider) in fixture.providers.0.iter().enumerate() {
            owner
                .charge(Resource::StructuralVisits, 1)
                .map_err(IdentityInputError::Work)?;
            for previous in &fixture.providers.0[..index] {
                owner
                    .charge(Resource::StructuralVisits, 1)
                    .map_err(IdentityInputError::Work)?;
                if controller_text(&provider.provider_id.0, &previous.provider_id.0, owner)? {
                    return controller_fault(run, index, ControllerInputFault::DuplicateProvider);
                }
            }
        }
        for (index, source) in fixture.initial_sources.0.iter().enumerate() {
            owner
                .charge(Resource::StructuralVisits, 1)
                .map_err(IdentityInputError::Work)?;
            // Actual WorkbenchStore.open returns without a provider call for an
            // empty locator. The ready-development evidence arm cannot prove it.
            if source.locator.0.is_empty() {
                return controller_fault(run, index, ControllerInputFault::EmptyLocator);
            }
            let mut provider = None;
            for candidate in &fixture.providers.0 {
                owner
                    .charge(Resource::StructuralVisits, 1)
                    .map_err(IdentityInputError::Work)?;
                if controller_text(&source.provider_id.0, &candidate.provider_id.0, owner)? {
                    provider = Some(candidate);
                    break;
                }
            }
            let Some(provider) = provider else {
                return controller_fault(run, index, ControllerInputFault::Provider);
            };
            let mut inspection = 0usize;
            for previous in &fixture.initial_sources.0[..index] {
                owner
                    .charge(Resource::StructuralVisits, 1)
                    .map_err(IdentityInputError::Work)?;
                if controller_text(&source.provider_id.0, &previous.provider_id.0, owner)? {
                    inspection = controller_increment(inspection, owner)?;
                }
            }
            let Some(reply) = provider.inspections.0.get(inspection) else {
                return controller_fault(run, index, ControllerInputFault::Reply);
            };
            if !controller_snapshot(source, &reply.source_snapshot, owner)? {
                return controller_fault(run, index, ControllerInputFault::Reply);
            }
            owner
                .reserve(&mut calls)
                .map_err(IdentityInputError::Work)?;
            calls.push(ControllerCall {
                kind: ControllerCallKind::Inspect,
                source,
                reply: &reply.reply,
            });
            let mut existed = false;
            let mut workspace = 0usize;
            for previous in &entries {
                owner
                    .charge(Resource::StructuralVisits, 1)
                    .map_err(IdentityInputError::Work)?;
                if controller_location(source, previous, owner)? {
                    existed = true;
                }
                if controller_text(&source.provider_id.0, &previous.provider_id.0, owner)? {
                    workspace = controller_increment(workspace, owner)?;
                }
            }
            if !existed {
                let Some(reply) = provider.workspaces.0.get(workspace) else {
                    return controller_fault(run, index, ControllerInputFault::Reply);
                };
                if !controller_snapshot(source, &reply.source_snapshot, owner)? {
                    return controller_fault(run, index, ControllerInputFault::Reply);
                }
                owner
                    .reserve(&mut calls)
                    .map_err(IdentityInputError::Work)?;
                calls.push(ControllerCall {
                    kind: ControllerCallKind::LoadDevelopment,
                    source,
                    reply: &reply.reply,
                });
                owner
                    .reserve(&mut entries)
                    .map_err(IdentityInputError::Work)?;
                entries.push(source);
            }
        }
        Ok(Self {
            run,
            fixture,
            entries,
            calls,
        })
    }
}

#[derive(Debug)]
pub(super) struct IdentityInputPlan<'source> {
    scenario: &'source Scenario,
    bindings: Vec<IdentityBinding<'source>>,
    controllers: Vec<ControllerInput<'source>>,
}
impl<'source> IdentityInputPlan<'source> {
    pub(super) fn from_paired(
        paired: &PairedWorkflow<'source>,
        owner: &mut ClosureOwner,
    ) -> Result<Self, IdentityInputError> {
        owner.ready().map_err(IdentityInputError::Work)?;
        let scenario = paired.scenario();
        let mut bindings: Vec<IdentityBinding<'source>> = Vec::new();
        let mut controllers = Vec::new();
        for (run, input) in scenario.runs.0.iter().enumerate() {
            owner
                .charge(Resource::StructuralVisits, 1)
                .map_err(IdentityInputError::Work)?;
            let Run::ModelOriginalsClient { actions, fixture } = input else {
                continue;
            };
            if let super::input::ClientFixtureMode::IdentityController { controller } =
                &fixture.mode
            {
                let input = ControllerInput::new(run, controller, owner)?;
                owner
                    .reserve(&mut controllers)
                    .map_err(IdentityInputError::Work)?;
                controllers.push(input);
            }
            // The next checkpoint is scanned once and reused by all samples
            // before it. No per-predicate or per-selected-run plan rebuilding.
            let mut checkpoint = None;
            for (action, input) in actions.0.iter().enumerate() {
                owner
                    .charge(Resource::StructuralVisits, 1)
                    .map_err(IdentityInputError::Work)?;
                if matches!(input, ClientAction::Checkpoint { .. }) {
                    checkpoint = None;
                }
                let ClientAction::ObserveIdentity { sample, subject } = input else {
                    continue;
                };
                for previous in &bindings {
                    owner
                        .charge(Resource::StructuralVisits, 1)
                        .map_err(IdentityInputError::Work)?;
                    if previous.run == run
                        && owner
                            .same_alias(previous.sample, sample)
                            .map_err(IdentityInputError::Work)?
                    {
                        return Err(IdentityInputError::DuplicateSample { run, action });
                    }
                }
                if checkpoint.is_none() {
                    for (index, following) in actions.0.iter().enumerate().skip(action + 1) {
                        owner
                            .charge(Resource::StructuralVisits, 1)
                            .map_err(IdentityInputError::Work)?;
                        if let ClientAction::Checkpoint { name } = following {
                            checkpoint = Some((index, name));
                            break;
                        }
                    }
                }
                let Some((checkpoint_index, name)) = checkpoint else {
                    return Err(IdentityInputError::MissingCheckpoint { run, action });
                };
                owner
                    .reserve(&mut bindings)
                    .map_err(IdentityInputError::Work)?;
                bindings.push(IdentityBinding {
                    run,
                    action,
                    checkpoint_index,
                    checkpoint: name,
                    sample,
                    subject,
                });
            }
        }
        Ok(Self {
            scenario,
            bindings,
            controllers,
        })
    }
    pub(super) fn controllers(&self) -> &[ControllerInput<'source>] {
        &self.controllers
    }
    pub(super) fn bindings(&self) -> &[IdentityBinding<'source>] {
        &self.bindings
    }
    pub(super) fn scenario(&self) -> &'source Scenario {
        self.scenario
    }
}

#[cfg(test)]
mod controller_tests;
