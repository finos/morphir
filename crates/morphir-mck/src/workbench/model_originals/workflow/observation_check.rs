//! Pure comparison of independently decoded observations and actual paired
//! input/expected operands. Comparison never issues runtime qualification.
use super::domain::{self, ExpectedClientCheck};
use super::input::{self, ClientAction};
use super::observed::{self, ClientCheckpoint};
use super::pairing::{PairedRun, PairedWorkflow};
use super::{FixtureAlias, Nullable, Presence};
pub(super) mod installed;
pub(super) mod server;
mod workspace;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(super) enum CompareResource {
    StructuralVisits,
    ComparisonBytes,
    Checks,
}
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(super) enum CorrelationFault {
    UnknownCheckpoint,
    DuplicateCheckpoint,
    MissingCheckpoint,
    UnboundOwner,
}
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(super) enum PredicateFault {
    Owner,
    CurrentOpening,
    CurrentModel,
    Navigation,
    IdentityKey,
    IdentityRelation,
    Controller,
}
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(super) enum IdentityFault {
    Plan,
    Snapshot,
    Path,
    Sample,
    ActionIndex,
    Checkpoint,
    Kind,
    Missing,
    Duplicate,
    Unexpected,
}
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(super) enum ControllerFault {
    SourceBinding,
    InvocationOrder,
    MissingInvocation,
    UnexpectedInvocation,
    Key,
    Checkpoint,
    Project,
    UnsupportedInput,
}
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(super) enum ObservationError {
    InvalidLimits,
    Resource(CompareResource),
    SizeOverflow,
    Role,
    ExpectedBlocked,
    InstalledClient(InstalledClientFault),
    UnsupportedServer,
    NativeDeclaration(server::NativeFault),
    UnsupportedClientCheck {
        index: usize,
    },
    UnsupportedOutcome,
    UnqualifiedEvidence,
    IdentityInputActionMissing,
    Controller {
        index: usize,
        kind: ControllerFault,
    },
    Identity {
        result: usize,
        kind: IdentityFault,
    },
    Outcome,
    Teardown,
    Correlation {
        checkpoint: usize,
        kind: CorrelationFault,
    },
    Predicate {
        index: usize,
        kind: PredicateFault,
    },
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(super) enum InstalledClientFault {
    ImplementationMissing,
    ImplementationBinding,
    ImplementationDigest,
    ImplementationProcess,
    SourceBinding,
    SourceCoverage,
    SourceWitness,
    WorkerCoverage,
    ProcessOrder,
    ProcessOutcome,
    ProcessClaims,
    SocketAssociation,
    SocketOrder,
    SocketFrame,
    SendOutcome,
    RecordAdoption,
    DestinationCoverage,
    DestinationEntries,
    DestinationBytes,
    ScratchCoverage,
    ScratchEntries,
    ConsumerAssociation,
    ConsumerClock,
    ConsumerTranscript,
    ConsumerRelease,
    ConsumerCommit,
    ConsumerCleanup,
    ConsumerHelper,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub(super) struct CompareUsage {
    pub(super) visits: usize,
    pub(super) comparison_bytes: usize,
    pub(super) checks: usize,
}
pub(super) struct CompareLimits(CompareUsage);
impl CompareLimits {
    pub(super) fn new(
        visits: usize,
        comparison_bytes: usize,
        checks: usize,
    ) -> Result<Self, ObservationError> {
        if [visits, comparison_bytes, checks]
            .into_iter()
            .any(|n| n > isize::MAX as usize)
        {
            return Err(ObservationError::InvalidLimits);
        }
        Ok(Self(CompareUsage {
            visits,
            comparison_bytes,
            checks,
        }))
    }
}

/// One explicit cumulative comparison owner, separate from Decoder/workflow
/// policy and producer pools. It owns no map, result history or allocator cap.
pub(super) struct CompareOwner {
    limits: CompareLimits,
    usage: CompareUsage,
    fault: Option<ObservationError>,
}
impl CompareOwner {
    pub(super) fn new(limits: CompareLimits) -> Self {
        Self {
            limits,
            usage: CompareUsage::default(),
            fault: None,
        }
    }
    #[cfg(test)]
    pub(super) fn usage(&self) -> CompareUsage {
        self.usage
    }
    pub(super) fn ready(&self) -> Result<(), ObservationError> {
        self.fault.map_or(Ok(()), Err)
    }
    pub(super) fn preflight_owned_text(&mut self, bytes: usize) -> Result<(), ObservationError> {
        self.ready()?;
        let Some(visits) = bytes.checked_mul(2) else {
            return self.refuse(ObservationError::SizeOverflow);
        };
        self.charge(CompareResource::ComparisonBytes, visits)
    }
    pub(super) fn refuse<T>(&mut self, error: ObservationError) -> Result<T, ObservationError> {
        Err(*self.fault.get_or_insert(error))
    }
    pub(super) fn charge(
        &mut self,
        resource: CompareResource,
        amount: usize,
    ) -> Result<(), ObservationError> {
        self.ready()?;
        let (used, maximum) = match resource {
            CompareResource::StructuralVisits => (&mut self.usage.visits, self.limits.0.visits),
            CompareResource::ComparisonBytes => (
                &mut self.usage.comparison_bytes,
                self.limits.0.comparison_bytes,
            ),
            CompareResource::Checks => (&mut self.usage.checks, self.limits.0.checks),
        };
        let Some(next) = used.checked_add(amount) else {
            return self.refuse(ObservationError::SizeOverflow);
        };
        if next > maximum {
            return self.refuse(ObservationError::Resource(resource));
        }
        *used = next;
        Ok(())
    }
    pub(super) fn visit(&mut self) -> Result<(), ObservationError> {
        self.charge(CompareResource::StructuralVisits, 1)
    }
    fn same(
        &mut self,
        left: &FixtureAlias,
        right: &FixtureAlias,
    ) -> Result<bool, ObservationError> {
        self.ready()?;
        let Some(upper) = left.as_str().len().checked_add(right.as_str().len()) else {
            return self.refuse(ObservationError::SizeOverflow);
        };
        self.charge(CompareResource::ComparisonBytes, upper)?;
        Ok(left == right)
    }
    pub(super) fn same_text(&mut self, left: &str, right: &str) -> Result<bool, ObservationError> {
        self.ready()?;
        let Some(upper) = left.len().checked_add(right.len()) else {
            return self.refuse(ObservationError::SizeOverflow);
        };
        self.charge(CompareResource::ComparisonBytes, upper)?;
        Ok(left == right)
    }
    fn nullable(
        &mut self,
        expected: &Nullable<FixtureAlias>,
        actual: &Nullable<FixtureAlias>,
    ) -> Result<bool, ObservationError> {
        self.visit()?;
        match (&expected.0, &actual.0) {
            (None, None) => Ok(true),
            (Some(a), Some(b)) => self.same(a, b),
            _ => Ok(false),
        }
    }
}

/// These predicates compared. This is deliberately not a runtime, Ready,
/// source-provenance or complete original-lineage qualification value.
#[derive(Debug)]
pub(super) struct ComparedPredicates<'source, 'actual> {
    scenario: &'source input::Scenario,
    expected: &'source domain::ExpectedWorkflow,
    actual: &'actual observed::Observation,
    checked: usize,
}
impl<'source, 'actual> ComparedPredicates<'source, 'actual> {
    pub(super) fn checked_predicates(&self) -> usize {
        self.checked
    }
    pub(super) fn scenario(&self) -> &'source input::Scenario {
        self.scenario
    }
    pub(super) fn expected(&self) -> &'source domain::ExpectedWorkflow {
        self.expected
    }
    pub(super) fn observation(&self) -> &'actual observed::Observation {
        self.actual
    }
}

#[derive(Clone, Copy)]
enum InputOwnerRole {
    Opening,
    Model,
}

fn owner_was_named(
    actions: &[ClientAction],
    before: usize,
    alias: &FixtureAlias,
    role: InputOwnerRole,
    owner: &mut CompareOwner,
) -> Result<bool, ObservationError> {
    for action in &actions[..before] {
        owner.visit()?;
        let candidate = match (role, action) {
            (
                InputOwnerRole::Opening,
                ClientAction::StartImport { attempt, .. }
                | ClientAction::StartConnected { attempt, .. }
                | ClientAction::BeginNativeOpenProject { attempt, .. }
                | ClientAction::BeginConnectedOpening { attempt, .. },
            ) => Some(attempt),
            (InputOwnerRole::Model, ClientAction::BindModelOwner { model, .. }) => Some(model),
            _ => None,
        };
        if let Some(candidate) = candidate
            && owner.same(candidate, alias)?
        {
            return Ok(true);
        }
    }
    Ok(false)
}

fn correlate_owner(
    actions: &[ClientAction],
    action: usize,
    checkpoint: usize,
    alias: &FixtureAlias,
    role: InputOwnerRole,
    owner: &mut CompareOwner,
) -> Result<(), ObservationError> {
    if !owner_was_named(actions, action, alias, role, owner)? {
        return owner.refuse(ObservationError::Correlation {
            checkpoint,
            kind: CorrelationFault::UnboundOwner,
        });
    }
    // A preceding action declaration establishes only source correspondence.
    // Actual retained/current owner provenance still needs the production port.
    Ok(())
}

fn correlate_checkpoints(
    actions: &[ClientAction],
    checkpoints: &[ClientCheckpoint],
    owner: &mut CompareOwner,
) -> Result<(), ObservationError> {
    let mut next_action = 0;
    for (index, checkpoint) in checkpoints.iter().enumerate() {
        owner.visit()?;
        for previous in &checkpoints[..index] {
            owner.visit()?;
            if owner.same(&previous.name, &checkpoint.name)? {
                return owner.refuse(ObservationError::Correlation {
                    checkpoint: index,
                    kind: CorrelationFault::DuplicateCheckpoint,
                });
            }
        }
        let mut matched_action = None;
        while next_action < actions.len() {
            owner.visit()?;
            let position = next_action;
            next_action += 1;
            if let ClientAction::Checkpoint { name } = &actions[position] {
                if !owner.same(name, &checkpoint.name)? {
                    return owner.refuse(ObservationError::Correlation {
                        checkpoint: index,
                        kind: CorrelationFault::UnknownCheckpoint,
                    });
                }
                matched_action = Some(position);
                break;
            }
        }
        let Some(action) = matched_action else {
            return owner.refuse(ObservationError::Correlation {
                checkpoint: index,
                kind: CorrelationFault::UnknownCheckpoint,
            });
        };
        if let Some(alias) = &checkpoint.current_opening.0 {
            correlate_owner(
                actions,
                action,
                index,
                alias,
                InputOwnerRole::Opening,
                owner,
            )?;
        }
        for alias in [
            &checkpoint.current_model.0,
            &checkpoint.navigation.inspection_owner.0,
            &checkpoint.navigation.output_owner.0,
            &checkpoint.navigation.search_owner.0,
        ]
        .into_iter()
        .flatten()
        {
            correlate_owner(actions, action, index, alias, InputOwnerRole::Model, owner)?;
        }
        match &checkpoint.owner {
            observed::OwnerEvidence::None {} => {}
            observed::OwnerEvidence::VerifiedOriginalFile { opening, .. }
            | observed::OwnerEvidence::VerifiedOriginalInventory { opening, .. } => {
                correlate_owner(
                    actions,
                    action,
                    index,
                    opening,
                    InputOwnerRole::Opening,
                    owner,
                )?
            }
            observed::OwnerEvidence::SemanticOnly { model, .. } => {
                correlate_owner(actions, action, index, model, InputOwnerRole::Model, owner)?
            }
        }
    }
    for action in &actions[next_action..] {
        owner.visit()?;
        if matches!(action, ClientAction::Checkpoint { .. }) {
            return owner.refuse(ObservationError::Correlation {
                checkpoint: checkpoints.len(),
                kind: CorrelationFault::MissingCheckpoint,
            });
        }
    }
    Ok(())
}

fn checkpoint<'actual>(
    name: &FixtureAlias,
    checkpoints: &'actual [ClientCheckpoint],
    owner: &mut CompareOwner,
) -> Result<&'actual ClientCheckpoint, ObservationError> {
    for item in checkpoints {
        owner.visit()?;
        if owner.same(&item.name, name)? {
            return Ok(item);
        }
    }
    owner.refuse(ObservationError::Correlation {
        checkpoint: checkpoints.len(),
        kind: CorrelationFault::MissingCheckpoint,
    })
}

fn number(
    expected: &domain::NumberRequirement,
    actual: u64,
    owner: &mut CompareOwner,
) -> Result<bool, ObservationError> {
    owner.visit()?;
    Ok(match expected {
        domain::NumberRequirement::Exact { value } => actual == value.0,
        domain::NumberRequirement::AtMost { value } => actual <= value.0,
        domain::NumberRequirement::Positive { maximum } => actual > 0 && actual <= maximum.0,
    })
}

fn identity_parts(
    result: &observed::IdentityResult,
) -> (
    &FixtureAlias,
    u64,
    &FixtureAlias,
    &input::IdentitySourceSnapshot,
    Option<&str>,
    &str,
) {
    match result {
        observed::IdentityResult::SourceKey {
            sample,
            action_index,
            checkpoint,
            source_snapshot,
            actual_key,
        } => (
            sample,
            action_index.0,
            checkpoint,
            source_snapshot,
            None,
            &actual_key.0,
        ),
        observed::IdentityResult::ProjectKey {
            sample,
            action_index,
            checkpoint,
            source_snapshot,
            relative_path,
            actual_key,
        } => (
            sample,
            action_index.0,
            checkpoint,
            source_snapshot,
            Some(&relative_path.0),
            &actual_key.0,
        ),
    }
}
fn identity_fault<T>(
    owner: &mut CompareOwner,
    result: usize,
    kind: IdentityFault,
) -> Result<T, ObservationError> {
    owner.refuse(ObservationError::Identity { result, kind })
}
fn same_snapshot(
    left: &input::IdentitySourceSnapshot,
    right: &input::IdentitySourceSnapshot,
    owner: &mut CompareOwner,
) -> Result<bool, ObservationError> {
    owner.visit()?;
    Ok(owner.same_text(&left.provider_id.0, &right.provider_id.0)?
        && owner.same_text(&left.locator.0, &right.locator.0)?
        && owner.same_text(&left.display_name.0, &right.display_name.0)?
        && matches!(
            (&left.persistence, &right.persistence),
            (Presence::Absent, Presence::Absent) | (Presence::Present(_), Presence::Present(_))
        ))
}
fn correlate_identity(
    paired: &PairedWorkflow<'_>,
    plan: Option<&super::identity_input::IdentityInputPlan<'_>>,
    results: Option<&[observed::IdentityResult]>,
    actions: &[ClientAction],
    owner: &mut CompareOwner,
) -> Result<(), ObservationError> {
    owner.ready()?;
    let Some(plan) = plan else {
        for action in actions {
            owner.visit()?;
            if matches!(action, ClientAction::ObserveIdentity { .. }) {
                return owner.refuse(ObservationError::IdentityInputActionMissing);
            }
        }
        match results {
            None => return Ok(()),
            Some([]) => return Ok(()),
            _ => return identity_fault(owner, 0, IdentityFault::Unexpected),
        }
    };
    if !std::ptr::eq(plan.scenario(), paired.scenario()) {
        return identity_fault(owner, 0, IdentityFault::Plan);
    }
    let mut count = 0usize;
    for binding in plan.bindings() {
        owner.visit()?;
        if binding.run_index() == paired.run_index() {
            count = count
                .checked_add(1)
                .ok_or_else(|| *owner.fault.get_or_insert(ObservationError::SizeOverflow))?;
        }
    }
    let items = results.unwrap_or(&[]);
    // Exact action/sample duplicates precede cardinality. A collision on only
    // one coordinate must reach input binding, so a forged sample is reported
    // at the offending row rather than as a duplicate of a later valid row.
    for (index, result) in items.iter().enumerate() {
        owner.visit()?;
        let (sample, action, ..) = identity_parts(result);
        for previous in &items[..index] {
            owner.visit()?;
            let (earlier, earlier_action, ..) = identity_parts(previous);
            if action == earlier_action && owner.same(sample, earlier)? {
                return identity_fault(owner, index, IdentityFault::Duplicate);
            }
        }
    }
    if items.len() < count {
        return identity_fault(owner, items.len(), IdentityFault::Missing);
    }
    if items.len() > count {
        return identity_fault(owner, count, IdentityFault::Unexpected);
    }
    for (index, result) in items.iter().enumerate() {
        owner.visit()?;
        let (sample, action, checkpoint, snapshot, path, _) = identity_parts(result);
        let mut found = None;
        for binding in plan.bindings() {
            owner.visit()?;
            if binding.run_index() == paired.run_index()
                && u64::try_from(binding.action_index()).ok() == Some(action)
            {
                found = Some(binding);
                break;
            }
        }
        let Some(binding) = found else {
            return identity_fault(owner, index, IdentityFault::ActionIndex);
        };
        if !owner.same(sample, binding.sample())? {
            return identity_fault(owner, index, IdentityFault::Sample);
        }
        if !owner.same(checkpoint, binding.checkpoint())? {
            return identity_fault(owner, index, IdentityFault::Checkpoint);
        }
        let (source, source_path) = match binding.subject() {
            input::IdentitySubject::SourceKey { source_snapshot } => (source_snapshot, None),
            input::IdentitySubject::ProjectKey {
                source_snapshot,
                relative_path,
            } => (source_snapshot, Some(relative_path.0.as_str())),
        };
        if source_path.is_some() != path.is_some() {
            return identity_fault(owner, index, IdentityFault::Kind);
        }
        if !same_snapshot(source, snapshot, owner)? {
            return identity_fault(owner, index, IdentityFault::Snapshot);
        }
        if let (Some(a), Some(b)) = (source_path, path)
            && !owner.same_text(a, b)?
        {
            return identity_fault(owner, index, IdentityFault::Path);
        }
    }
    Ok(())
}
fn identity_result<'actual>(
    sample: &FixtureAlias,
    results: &'actual [observed::IdentityResult],
    owner: &mut CompareOwner,
) -> Result<&'actual observed::IdentityResult, ObservationError> {
    for result in results {
        owner.visit()?;
        if owner.same(sample, identity_parts(result).0)? {
            return Ok(result);
        }
    }
    identity_fault(owner, results.len(), IdentityFault::Missing)
}

fn predicate(
    index: usize,
    check: &ExpectedClientCheck,
    identity_results: &[observed::IdentityResult],
    checkpoints: &[ClientCheckpoint],
    workspace_checkpoints: Option<&[observed::WorkspaceCheckpoint]>,
    owner: &mut CompareOwner,
) -> Result<(), ObservationError> {
    owner.charge(CompareResource::Checks, 1)?;
    owner.visit()?;
    let (matches, kind) = match check {
        ExpectedClientCheck::IdentityKey {
            sample,
            expected_key,
            ..
        } => {
            let result = identity_result(sample, identity_results, owner)?;
            (
                owner.same_text(&expected_key.0, identity_parts(result).5)?,
                PredicateFault::IdentityKey,
            )
        }
        ExpectedClientCheck::IdentityLocationRelation {
            left,
            right,
            relation,
            ..
        } => {
            let a = identity_result(left, identity_results, owner)?;
            let b = identity_result(right, identity_results, owner)?;
            let (_, _, _, _, path_a, key_a) = identity_parts(a);
            let (_, _, _, _, path_b, key_b) = identity_parts(b);
            let same_kind = path_a.is_some() == path_b.is_some();
            let equal = owner.same_text(key_a, key_b)?;
            (
                same_kind
                    && match relation {
                        domain::IdentityRelation::Same => equal,
                        domain::IdentityRelation::Different => !equal,
                    },
                PredicateFault::IdentityRelation,
            )
        }
        ExpectedClientCheck::OwnerAbsent {
            checkpoint: name, ..
        } => {
            let actual = checkpoint(name, checkpoints, owner)?;
            (
                matches!(actual.owner, observed::OwnerEvidence::None {}),
                PredicateFault::Owner,
            )
        }
        ExpectedClientCheck::CurrentOpening {
            checkpoint: name,
            current,
            ..
        } => {
            let actual = checkpoint(name, checkpoints, owner)?;
            let same = match (current, &actual.current_opening.0) {
                (domain::ExpectedCurrentOpening::None {}, None) => true,
                (domain::ExpectedCurrentOpening::Attempt { .. }, _) => {
                    return owner.refuse(ObservationError::UnsupportedClientCheck { index });
                }
                _ => false,
            };
            (same, PredicateFault::CurrentOpening)
        }
        ExpectedClientCheck::CurrentModel {
            checkpoint: name,
            current,
            ..
        } => {
            let actual = checkpoint(name, checkpoints, owner)?;
            let same = match (current, &actual.current_model.0) {
                (domain::ExpectedCurrentModel::None {}, None) => true,
                (domain::ExpectedCurrentModel::Model { .. }, _) => {
                    return owner.refuse(ObservationError::UnsupportedClientCheck { index });
                }
                _ => false,
            };
            (same, PredicateFault::CurrentModel)
        }
        ExpectedClientCheck::Navigation {
            checkpoint: name,
            inspection_owner,
            output_owner,
            search_owner,
            destinations,
            ..
        } => {
            if inspection_owner.0.is_some() || output_owner.0.is_some() || search_owner.0.is_some()
            {
                return owner.refuse(ObservationError::UnsupportedClientCheck { index });
            }
            let actual = &checkpoint(name, checkpoints, owner)?.navigation;
            let same = owner.nullable(inspection_owner, &actual.inspection_owner)?
                && owner.nullable(output_owner, &actual.output_owner)?
                && owner.nullable(search_owner, &actual.search_owner)?
                && number(destinations, actual.destination_count.0, owner)?;
            (same, PredicateFault::Navigation)
        }
        ExpectedClientCheck::IdentityController {
            checkpoint,
            active_key,
            entries,
            recent_keys,
            ..
        } => {
            let Some(checkpoints) = workspace_checkpoints else {
                return owner.refuse(ObservationError::UnsupportedClientCheck { index });
            };
            (
                workspace::predicate(
                    checkpoint,
                    active_key,
                    &entries.0,
                    &recent_keys.0,
                    checkpoints,
                    owner,
                )?,
                PredicateFault::Controller,
            )
        }
        ExpectedClientCheck::PortTrace { .. }
        | ExpectedClientCheck::PortCounts { .. }
        | ExpectedClientCheck::VerifiedOwner { .. }
        | ExpectedClientCheck::CoreResult { .. }
        | ExpectedClientCheck::Download { .. }
        | ExpectedClientCheck::Archive { .. }
        | ExpectedClientCheck::RichOwner { .. }
        | ExpectedClientCheck::CaptureCleanup { .. }
        | ExpectedClientCheck::ExecutionOwner { .. }
        | ExpectedClientCheck::ExecutionReceipt { .. }
        | ExpectedClientCheck::LocalExplorerState { .. }
        | ExpectedClientCheck::LocalEvaluationState { .. }
        | ExpectedClientCheck::ModelOutputCleared { .. }
        | ExpectedClientCheck::NativeTranscript { .. }
        | ExpectedClientCheck::NativeOpenReleaseOrder { .. }
        | ExpectedClientCheck::NativeWorkspaceOwnerState { .. }
        | ExpectedClientCheck::ConnectedTranscript { .. }
        | ExpectedClientCheck::ConnectedOpeningTransfer { .. }
        | ExpectedClientCheck::ConnectedInventoryRefusal { .. }
        | ExpectedClientCheck::ConnectedOriginalsRetained { .. } => {
            return owner.refuse(ObservationError::UnsupportedClientCheck { index });
        }
    };
    if matches {
        Ok(())
    } else {
        owner.refuse(ObservationError::Predicate { index, kind })
    }
}

/// This cannot ignore extra evidence or use matching peer labels as actual
/// production bindings. The historical empty-state subset and the separate
/// source-correlated workspace component share this comparison owner.
fn check_core<'source, 'actual>(
    paired: &PairedWorkflow<'source>,
    identity_plan: Option<&super::identity_input::IdentityInputPlan<'source>>,
    actual: &'actual observed::Observation,
    owner: &mut CompareOwner,
) -> Result<ComparedPredicates<'source, 'actual>, ObservationError> {
    owner.ready()?;
    owner.visit()?;
    if let Some(plan) = identity_plan
        && !std::ptr::eq(plan.scenario(), paired.scenario())
    {
        return identity_fault(owner, 0, IdentityFault::Plan);
    }
    if matches!(actual, observed::Observation::WorkspaceClient { .. }) {
        return workspace::check(paired, identity_plan, actual, owner);
    }
    let (
        PairedRun::Client { actions, fixture },
        domain::ExpectedWorkflow::ModelOriginalsClient {
            checks,
            qualification,
            outcome: expected_outcome,
            ..
        },
        observed::Observation::ModelOriginalsClient {
            checkpoints,
            effects,
            core_results,
            downloads,
            rich_owners,
            outbound,
            outcome,
            teardown,
            identity_results,
        },
    ) = (paired.run(), paired.expected(), actual)
    else {
        return owner.refuse(match (paired.run(), actual) {
            (PairedRun::Server { .. }, observed::Observation::ModelOriginalsServer { .. }) => {
                ObservationError::UnsupportedServer
            }
            _ => ObservationError::Role,
        });
    };
    if matches!(
        qualification,
        domain::ExpectedWorkflowModelOriginalsClientQualification::Blocked { .. }
    ) {
        return owner.refuse(ObservationError::ExpectedBlocked);
    }
    correlate_checkpoints(actions, &checkpoints.0, owner)?;
    correlate_identity(
        paired,
        identity_plan,
        match identity_results {
            Presence::Absent => None,
            Presence::Present(items) => Some(&items.0),
        },
        actions,
        owner,
    )?;

    // Actual effect/core/download/transcript/owner proof paths are not yet
    // connected. Explicitly block them rather than accepting matching claims.
    if !effects.0.is_empty()
        || !core_results.0.is_empty()
        || !downloads.0.is_empty()
        || !rich_owners.0.is_empty()
        || !outbound.0.is_empty()
        || !fixture.files.0.is_empty()
        || !fixture.literal_peers.0.is_empty()
        || !matches!(fixture.mode, input::ClientFixtureMode::Basic)
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
    for checkpoint in &checkpoints.0 {
        owner.visit()?;
        if !checkpoint.pending_effects.0.is_empty()
            || !checkpoint.prepared_core_effects.0.is_empty()
            || checkpoint.held_core_result_bytes.0 != 0
            || checkpoint.event_count.0 != 0
            || !matches!(checkpoint.owner, observed::OwnerEvidence::None {})
            || !matches!(
                checkpoint.execution_owner,
                observed::ExecutionOwner::None {}
            )
            || !matches!(
                checkpoint.capture_cleanup,
                observed::CaptureCleanup::None {}
            )
        {
            return owner.refuse(ObservationError::UnqualifiedEvidence);
        }
    }

    let mut checked = 0usize;
    for (index, check) in checks.0.iter().enumerate() {
        let results = match identity_results {
            Presence::Absent => &[][..],
            Presence::Present(items) => &items.0,
        };
        predicate(index, check, results, &checkpoints.0, None, owner)?;
        let Some(next) = checked.checked_add(1) else {
            return owner.refuse(ObservationError::SizeOverflow);
        };
        checked = next;
    }
    owner.visit()?;
    match (expected_outcome, outcome) {
        (
            domain::ExpectedWorkflowModelOriginalsClientOutcome::Clean {
                final_checkpoint: expected,
            },
            observed::ScenarioOutcome::Clean {
                final_checkpoint: actual,
            },
        ) => {
            let Some(last) = checkpoints.0.last() else {
                return owner.refuse(ObservationError::Outcome);
            };
            if !owner.same(expected, actual)? || !owner.same(actual, &last.name)? {
                return owner.refuse(ObservationError::Outcome);
            }
        }
        _ => return owner.refuse(ObservationError::UnsupportedOutcome),
    }
    owner.visit()?;
    match teardown {
        observed::HarnessTeardown::Confirmed {
            workers_started,
            workers_exited,
            disposed_transports,
            ..
        } if workers_started.0 == 0 && workers_exited.0 == 0 && disposed_transports.0 == 0 => {}
        _ => return owner.refuse(ObservationError::Teardown),
    }
    Ok(ComparedPredicates {
        scenario: paired.scenario(),
        expected: paired.expected(),
        actual,
        checked,
    })
}

pub(super) fn check_paired<'source, 'actual>(
    paired: &PairedWorkflow<'source>,
    actual: &'actual observed::Observation,
    owner: &mut CompareOwner,
) -> Result<ComparedPredicates<'source, 'actual>, ObservationError> {
    check_core(paired, None, actual, owner)
}
pub(super) fn check_planned<'source, 'actual>(
    paired: &PairedWorkflow<'source>,
    plan: &super::identity_input::IdentityInputPlan<'source>,
    actual: &'actual observed::Observation,
    owner: &mut CompareOwner,
) -> Result<ComparedPredicates<'source, 'actual>, ObservationError> {
    check_core(paired, Some(plan), actual, owner)
}
