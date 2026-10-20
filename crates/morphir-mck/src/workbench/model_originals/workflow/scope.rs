//! Source-derived enclosing scopes for aliases from the genuine typed walk.
use super::meaning::{Meaning, ObservationScope, Role, SemanticBlocker, classify};
use super::walk::{NativePending, Operand, Segment, Site, SubjectKind, Trail};
use super::{FixtureAlias, domain, input};

pub(super) trait ScopeWork {
    type Error;
    /// Charge before inspecting a borrowed trail link or typed source selector.
    fn visit(&mut self) -> Result<(), Self::Error>;
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(super) enum RunKey {
    First,
    Second,
}
impl RunKey {
    fn index(self) -> usize {
        match self {
            Self::First => 0,
            Self::Second => 1,
        }
    }
}

#[derive(Debug, Clone, Copy)]
pub(super) enum ScopeKey<'source> {
    Run(RunKey),
    Provider {
        run: RunKey,
        provider: &'source FixtureAlias,
    },
    ExpectedCheck {
        run: RunKey,
        check: usize,
    },
    ExpectedTrace {
        run: RunKey,
        trace: usize,
    },
    OpeningAttempt {
        run: RunKey,
        attempt: &'source FixtureAlias,
    },
    ConnectionProvider {
        run: RunKey,
        connection: &'source FixtureAlias,
        provider: &'source FixtureAlias,
    },
    CaptureAttempt {
        run: RunKey,
        connection: &'source FixtureAlias,
        attempt: &'source FixtureAlias,
    },
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(super) enum RequiredScope {
    Run,
    Provider,
    Check,
    Trace,
    OpeningAttempt,
    ConnectionProvider,
    CaptureAttempt,
    EffectKind,
    NativeBoundary,
}

#[derive(Debug)]
pub(super) enum ScopeError<E> {
    Work(E),
    Semantic(SemanticBlocker),
    Missing(RequiredScope),
    RunOutOfRange,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(super) enum SubjectRoles {
    Opening,
    Execution,
    LocalEvaluation,
    /// Exactly ExecutionRuntime or NativeRuntime; ambiguity must refuse.
    CatalogRuntime,
    /// Exactly OpeningAttempt or ExecutionRuntime; ambiguity must refuse.
    Initialize,
    NativeRuntime,
    CountQuery,
}
impl SubjectRoles {
    pub(super) fn candidates(self) -> &'static [Role] {
        use Role::*;
        match self {
            Self::Opening => &[OpeningAttempt],
            Self::Execution => &[Execution],
            Self::LocalEvaluation => &[LocalEvaluationAttempt],
            Self::CatalogRuntime => &[ExecutionRuntime, NativeRuntime],
            Self::Initialize => &[OpeningAttempt, ExecutionRuntime],
            Self::NativeRuntime => &[NativeRuntime],
            Self::CountQuery => &[
                OpeningAttempt,
                ExecutionRuntime,
                NativeRuntime,
                Execution,
                LocalEvaluationAttempt,
            ],
        }
    }
}

#[derive(Debug, Clone, Copy)]
pub(super) enum RuntimeBindingObligation<'source> {
    Capture {
        alias: &'source FixtureAlias,
        attempt: &'source FixtureAlias,
    },
    OfferRegistration {
        alias: &'source FixtureAlias,
        connection: &'source FixtureAlias,
        provider: &'source FixtureAlias,
    },
    CaptureWork {
        alias: &'source FixtureAlias,
        connection: &'source FixtureAlias,
        attempt: &'source FixtureAlias,
    },
}

#[derive(Debug, Clone, Copy)]
pub(super) enum SourcePosition {
    Fixture,
    Action(usize),
    Expected(Site),
}

#[derive(Debug, Clone, Copy)]
pub(super) enum ResolvedMeaning {
    Define(Role),
    Reference(Role),
    Prearm(Role),
    LocalDefine(Role),
    LocalReference(Role),
    SubjectReference(SubjectRoles),
    ObservationClaim(Role),
}

pub(super) struct Symbol<'source> {
    pub(super) alias: &'source FixtureAlias,
    pub(super) scope: ScopeKey<'source>,
    pub(super) position: SourcePosition,
    pub(super) meaning: ResolvedMeaning,
    pub(super) binding: Option<RuntimeBindingObligation<'source>>,
}

#[derive(Clone, Copy)]
pub(super) enum Sources<'source> {
    Current {
        input: &'source input::Scenario,
        expected: &'source domain::ExpectedWorkflow,
    },
    NativeDeclaration {
        input: &'source super::native_original::OriginalScenario,
        expected: &'source super::native_original::NativeDeclarationExpectation,
        selected_run: super::native_original::ValidatedRunIndex,
    },
}

fn field_index<W: ScopeWork>(
    trail: &Trail<'_>,
    declaration: &str,
    field: &str,
    work: &mut W,
) -> Result<Option<usize>, ScopeError<W::Error>> {
    let mut current = Some(trail);
    let mut child = None;
    while let Some(link) = current {
        work.visit().map_err(ScopeError::Work)?;
        if let Segment::Field(site) = link.segment {
            let (_, name, _, key) = site.parts();
            if name == declaration && key == field {
                return Ok(match child {
                    Some(Segment::Item(index)) => Some(index),
                    _ => None,
                });
            }
        }
        child = Some(link.segment);
        current = link.parent;
    }
    Ok(None)
}
fn site<W: ScopeWork>(trail: &Trail<'_>, work: &mut W) -> Result<Site, ScopeError<W::Error>> {
    let mut current = Some(trail);
    while let Some(link) = current {
        work.visit().map_err(ScopeError::Work)?;
        if let Segment::Field(site) = link.segment {
            return Ok(site);
        }
        current = link.parent;
    }
    Err(ScopeError::Missing(RequiredScope::Run))
}
fn subject<W: ScopeWork>(
    trail: &Trail<'_>,
    work: &mut W,
) -> Result<SubjectKind, ScopeError<W::Error>> {
    let mut current = Some(trail);
    while let Some(link) = current {
        work.visit().map_err(ScopeError::Work)?;
        if let Segment::Effect(kind) = link.segment {
            return Ok(kind);
        }
        current = link.parent;
    }
    Err(ScopeError::Missing(RequiredScope::EffectKind))
}
fn native_pending<W: ScopeWork>(
    trail: &Trail<'_>,
    work: &mut W,
) -> Result<Role, ScopeError<W::Error>> {
    let mut current = Some(trail);
    while let Some(link) = current {
        work.visit().map_err(ScopeError::Work)?;
        if let Segment::NativeBoundary(kind) = link.segment {
            return Ok(match kind {
                NativePending::Initialize => Role::PendingNativeInitialize,
                NativePending::Choose => Role::PendingNativeChoose,
                NativePending::Open => Role::PendingNativeOpen,
            });
        }
        current = link.parent;
    }
    Err(ScopeError::Missing(RequiredScope::NativeBoundary))
}

impl<'source> Sources<'source> {
    pub(super) fn from_paired(paired: &super::pairing::PairedWorkflow<'source>) -> Self {
        Self::Current {
            input: paired.scenario(),
            expected: paired.expected(),
        }
    }
    pub(super) fn from_native(
        input: &'source super::native_original::OriginalScenario,
        expected: &'source super::native_original::NativeDeclarationExpectation,
        selected_run: super::native_original::ValidatedRunIndex,
    ) -> Self {
        Self::NativeDeclaration {
            input,
            expected,
            selected_run,
        }
    }
    pub(super) fn walk_input<S: super::walk::AliasSink<'source>>(
        self,
        trail: &Trail<'_>,
        sink: &mut S,
    ) -> Result<(), S::Error> {
        use super::walk::WalkAliases;
        match self {
            Self::Current { input, .. } => input.walk(trail, sink),
            Self::NativeDeclaration { input, .. } => input.walk(trail, sink),
        }
    }
    pub(super) fn walk_expected<S: super::walk::AliasSink<'source>>(
        self,
        trail: &Trail<'_>,
        sink: &mut S,
    ) -> Result<(), S::Error> {
        use super::walk::WalkAliases;
        match self {
            Self::Current { expected, .. } => expected.walk(trail, sink),
            Self::NativeDeclaration { expected, .. } => expected.walk(trail, sink),
        }
    }
    fn current_expected(self) -> Option<&'source domain::ExpectedWorkflow> {
        match self {
            Self::Current { expected, .. } => Some(expected),
            Self::NativeDeclaration { .. } => None,
        }
    }
    fn run_count(self) -> usize {
        match self {
            Self::Current { input, .. } => input.runs.0.len(),
            Self::NativeDeclaration { input, .. } => input.runs.0.len(),
        }
    }
    fn server_actions(self, run: RunKey) -> Option<&'source [input::HostAction]> {
        match self {
            Self::Current { input, .. } => match &input.runs.0[run.index()] {
                input::Run::ModelOriginalsServer { actions, .. } => Some(&actions.0),
                input::Run::ModelOriginalsClient { .. } => None,
            },
            Self::NativeDeclaration { input, .. } => match &input.runs.0[run.index()] {
                super::native_original::OriginalRun::ModelOriginalsServer { actions, .. } => {
                    Some(&actions.0)
                }
            },
        }
    }
    fn provider_alias(self, run: RunKey, index: usize) -> Option<&'source FixtureAlias> {
        match self {
            Self::Current { input, .. } => match &input.runs.0[run.index()] {
                input::Run::ModelOriginalsServer { fixture, .. } => fixture
                    .providers
                    .0
                    .get(index)
                    .map(|provider| match provider {
                        input::Provider::Native { alias, .. }
                        | input::Provider::Installed { alias, .. } => alias,
                    }),
                input::Run::ModelOriginalsClient { .. } => None,
            },
            Self::NativeDeclaration { input, .. } => match &input.runs.0[run.index()] {
                super::native_original::OriginalRun::ModelOriginalsServer { fixture, .. } => {
                    fixture
                        .providers
                        .0
                        .get(index)
                        .map(|provider| match provider {
                            super::native_original::OriginalProvider::Native { alias, .. } => alias,
                        })
                }
            },
        }
    }
    fn run<W: ScopeWork>(
        &self,
        operand: Operand,
        trail: &Trail<'_>,
        work: &mut W,
    ) -> Result<RunKey, ScopeError<W::Error>> {
        let index = match operand {
            Operand::Input => field_index(trail, "Scenario", "runs", work)?
                .ok_or(ScopeError::Missing(RequiredScope::Run))?,
            Operand::Expected => {
                work.visit().map_err(ScopeError::Work)?;
                match *self {
                    Self::NativeDeclaration { selected_run, .. } => selected_run.get(),
                    Self::Current { expected, .. } => match expected {
                        domain::ExpectedWorkflow::ModelOriginalsServer { run_index, .. }
                        | domain::ExpectedWorkflow::ModelOriginalsClient { run_index, .. } => {
                            usize::try_from(run_index.0).map_err(|_| ScopeError::RunOutOfRange)?
                        }
                    },
                }
            }
        };
        work.visit().map_err(ScopeError::Work)?;
        if index >= self.run_count() {
            return Err(ScopeError::RunOutOfRange);
        }
        match index {
            0 => Ok(RunKey::First),
            1 => Ok(RunKey::Second),
            _ => Err(ScopeError::RunOutOfRange),
        }
    }
    fn check_index<W: ScopeWork>(
        &self,
        trail: &Trail<'_>,
        work: &mut W,
    ) -> Result<usize, ScopeError<W::Error>> {
        field_index(trail, "ExpectedWorkflow", "checks", work)?
            .ok_or(ScopeError::Missing(RequiredScope::Check))
    }
    fn provider<W: ScopeWork>(
        &self,
        run: RunKey,
        site: Site,
        trail: &Trail<'_>,
        work: &mut W,
    ) -> Result<&'source FixtureAlias, ScopeError<W::Error>> {
        match site.parts() {
            (Operand::Input, "ProjectBinding", _, _) => {
                let index = field_index(trail, "HostFixture", "providers", work)?
                    .ok_or(ScopeError::Missing(RequiredScope::Provider))?;
                work.visit().map_err(ScopeError::Work)?;
                if let Some(alias) = self.provider_alias(run, index) {
                    return Ok(alias);
                }
            }
            (Operand::Input, "HostAction", _, _) => {
                let index = field_index(trail, "Run", "actions", work)?
                    .ok_or(ScopeError::Missing(RequiredScope::Provider))?;
                work.visit().map_err(ScopeError::Work)?;
                if let Some(actions) = self.server_actions(run)
                    && let Some(
                        input::HostAction::CaptureSelected { provider, .. }
                        | input::HostAction::BeginCaptureSelected { provider, .. }
                        | input::HostAction::OpenLegacySelected { provider, .. },
                    ) = actions.get(index)
                {
                    return Ok(provider);
                }
            }
            (Operand::Expected, "ExpectedBinding", _, _) => {
                let index = field_index(trail, "ExpectedWorkflow", "bindings", work)?
                    .ok_or(ScopeError::Missing(RequiredScope::Provider))?;
                work.visit().map_err(ScopeError::Work)?;
                let Some(expected) = self.current_expected() else {
                    return Err(ScopeError::Missing(RequiredScope::Provider));
                };
                let bindings = match expected {
                    domain::ExpectedWorkflow::ModelOriginalsServer { bindings, .. }
                    | domain::ExpectedWorkflow::ModelOriginalsClient { bindings, .. } => bindings,
                };
                if let Some(domain::ExpectedBinding::DiscoveredServerSelection {
                    provider, ..
                }) = bindings.0.get(index)
                {
                    return Ok(provider);
                }
            }
            _ => {}
        }
        Err(ScopeError::Missing(RequiredScope::Provider))
    }
    fn observation<W: ScopeWork>(
        &self,
        alias: &'source FixtureAlias,
        run: RunKey,
        required: ObservationScope,
        trail: &Trail<'_>,
        work: &mut W,
    ) -> Result<(ScopeKey<'source>, RuntimeBindingObligation<'source>), ScopeError<W::Error>> {
        let index = self.check_index(trail, work)?;
        work.visit().map_err(ScopeError::Work)?;
        match (required, self.current_expected()) {
            (
                ObservationScope::OpeningAttempt,
                Some(domain::ExpectedWorkflow::ModelOriginalsClient { checks, .. }),
            ) => {
                if let Some(domain::ExpectedClientCheck::CaptureCleanup {
                    cleanup:
                        domain::ExpectedCleanup::ReleaseConfirmed { attempt, .. }
                        | domain::ExpectedCleanup::OwnConnectionClosed { attempt, .. },
                    ..
                }) = checks.0.get(index)
                {
                    return Ok((
                        ScopeKey::OpeningAttempt { run, attempt },
                        RuntimeBindingObligation::Capture { alias, attempt },
                    ));
                }
            }
            (
                ObservationScope::ConnectionProvider,
                Some(domain::ExpectedWorkflow::ModelOriginalsServer { checks, .. }),
            ) => {
                if let Some(domain::ExpectedServerCheck::Offer {
                    connection, state, ..
                }) = checks.0.get(index)
                {
                    let provider = match state {
                        domain::ExpectedOffer::Held { provider, .. }
                        | domain::ExpectedOffer::Revoked { provider, .. }
                        | domain::ExpectedOffer::Replaced { provider, .. } => provider,
                    };
                    return Ok((
                        ScopeKey::ConnectionProvider {
                            run,
                            connection,
                            provider,
                        },
                        RuntimeBindingObligation::OfferRegistration {
                            alias,
                            connection,
                            provider,
                        },
                    ));
                }
            }
            (
                ObservationScope::CaptureAttempt,
                Some(domain::ExpectedWorkflow::ModelOriginalsServer { checks, .. }),
            ) => {
                if let Some(domain::ExpectedServerCheck::CaptureLifecycle {
                    connection,
                    state:
                        domain::ExpectedLifecycleState::Capturing { attempt, .. }
                        | domain::ExpectedLifecycleState::PreparedPrivate { attempt, .. },
                    ..
                }) = checks.0.get(index)
                {
                    return Ok((
                        ScopeKey::CaptureAttempt {
                            run,
                            connection,
                            attempt,
                        },
                        RuntimeBindingObligation::CaptureWork {
                            alias,
                            connection,
                            attempt,
                        },
                    ));
                }
            }
            _ => {}
        }
        Err(ScopeError::Missing(match required {
            ObservationScope::OpeningAttempt => RequiredScope::OpeningAttempt,
            ObservationScope::ConnectionProvider => RequiredScope::ConnectionProvider,
            ObservationScope::CaptureAttempt => RequiredScope::CaptureAttempt,
        }))
    }
    pub(super) fn enclose<W: ScopeWork>(
        &self,
        alias: &'source FixtureAlias,
        trail: &Trail<'_>,
        work: &mut W,
    ) -> Result<Symbol<'source>, ScopeError<W::Error>> {
        let site = site(trail, work)?;
        let (operand, _, _, _) = site.parts();
        let run = self.run(operand, trail, work)?;
        let position = match operand {
            Operand::Input => match field_index(trail, "Run", "actions", work)? {
                Some(index) => SourcePosition::Action(index),
                None => SourcePosition::Fixture,
            },
            Operand::Expected => SourcePosition::Expected(site),
        };
        let meaning = classify(site);
        let mut scope = ScopeKey::Run(run);
        let mut binding = None;
        let resolved = match meaning {
            Meaning::Blocked(blocker) => return Err(ScopeError::Semantic(blocker)),
            Meaning::Define(role) | Meaning::Reference(role) | Meaning::Prearm(role) => {
                if role == Role::ProviderProject {
                    scope = ScopeKey::Provider {
                        run,
                        provider: self.provider(run, site, trail, work)?,
                    };
                }
                match meaning {
                    Meaning::Define(_) => ResolvedMeaning::Define(role),
                    Meaning::Reference(_) => ResolvedMeaning::Reference(role),
                    Meaning::Prearm(_) => ResolvedMeaning::Prearm(role),
                    _ => unreachable!(),
                }
            }
            Meaning::LocalDefine(role) | Meaning::LocalReference(role) => {
                scope = match role {
                    Role::ExpectedEntry | Role::ExpectedLockActor => ScopeKey::ExpectedCheck {
                        run,
                        check: self.check_index(trail, work)?,
                    },
                    Role::ExpectedWork => ScopeKey::ExpectedTrace {
                        run,
                        trace: field_index(trail, "ExpectedWorkflow", "traceSources", work)?
                            .ok_or(ScopeError::Missing(RequiredScope::Trace))?,
                    },
                    _ => {
                        return Err(ScopeError::Semantic(SemanticBlocker::UnclassifiedSite(
                            site,
                        )));
                    }
                };
                match meaning {
                    Meaning::LocalDefine(_) => ResolvedMeaning::LocalDefine(role),
                    _ => ResolvedMeaning::LocalReference(role),
                }
            }
            Meaning::NativeBoundaryPending => {
                ResolvedMeaning::Reference(native_pending(trail, work)?)
            }
            Meaning::CountSubject => ResolvedMeaning::SubjectReference(SubjectRoles::CountQuery),
            Meaning::EffectSubject => {
                work.visit().map_err(ScopeError::Work)?;
                if self.server_actions(run).is_some() {
                    return Err(ScopeError::Semantic(
                        SemanticBlocker::UnboundServerEffectIssuer(site),
                    ));
                }
                let roles = match subject(trail, work)? {
                    SubjectKind::Maintained(kind) => {
                        use crate::workbench::model_originals::EffectKind;
                        match kind {
                            EffectKind::Catalog => SubjectRoles::CatalogRuntime,
                            EffectKind::Initialize => SubjectRoles::Initialize,
                            EffectKind::NativeInvoke => SubjectRoles::NativeRuntime,
                            EffectKind::ExecutionSubmit
                            | EffectKind::ExecutionObserve
                            | EffectKind::ExecutionRelease => SubjectRoles::Execution,
                            EffectKind::LocalEvaluation => SubjectRoles::LocalEvaluation,
                            EffectKind::Picker
                            | EffectKind::FileRead
                            | EffectKind::NativeCapture
                            | EffectKind::Capture
                            | EffectKind::Inventory
                            | EffectKind::ReadOriginal
                            | EffectKind::ReadProjection
                            | EffectKind::Release
                            | EffectKind::Digest
                            | EffectKind::Inspection => SubjectRoles::Opening,
                        }
                    }
                    SubjectKind::ManifestFetch | SubjectKind::WorkspaceOpen => {
                        SubjectRoles::Opening
                    }
                };
                ResolvedMeaning::SubjectReference(roles)
            }
            Meaning::ObservationClaim {
                role,
                scope: required,
            } => {
                let (key, obligation) = self.observation(alias, run, required, trail, work)?;
                scope = key;
                binding = Some(obligation);
                ResolvedMeaning::ObservationClaim(role)
            }
        };
        Ok(Symbol {
            alias,
            scope,
            position,
            meaning: resolved,
            binding,
        })
    }
}
