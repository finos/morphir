//! One source-borrowing plan, issued once per paired case. This is not an
//! observation, a UI invocation, source provenance, or runtime authority.
use super::FixtureAlias;
use super::input::{ClientAction, IdentitySubject, Run, Scenario};
use super::pairing::PairedWorkflow;
use super::work::{ClosureError, ClosureOwner, Resource};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(super) enum IdentityInputError {
    Work(ClosureError),
    MissingCheckpoint { run: usize, action: usize },
    DuplicateSample { run: usize, action: usize },
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
#[derive(Debug)]
pub(super) struct IdentityInputPlan<'source> {
    scenario: &'source Scenario,
    bindings: Vec<IdentityBinding<'source>>,
}
impl<'source> IdentityInputPlan<'source> {
    pub(super) fn from_paired(
        paired: &PairedWorkflow<'source>,
        owner: &mut ClosureOwner,
    ) -> Result<Self, IdentityInputError> {
        owner.ready().map_err(IdentityInputError::Work)?;
        let scenario = paired.scenario();
        let mut bindings: Vec<IdentityBinding<'source>> = Vec::new();
        for (run, input) in scenario.runs.0.iter().enumerate() {
            owner
                .charge(Resource::StructuralVisits, 1)
                .map_err(IdentityInputError::Work)?;
            let Run::ModelOriginalsClient { actions, .. } = input else {
                continue;
            };
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
        Ok(Self { scenario, bindings })
    }
    pub(super) fn bindings(&self) -> &[IdentityBinding<'source>] {
        &self.bindings
    }
    pub(super) fn scenario(&self) -> &'source Scenario {
        self.scenario
    }
}
