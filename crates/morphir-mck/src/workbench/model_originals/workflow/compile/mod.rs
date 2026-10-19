//! Static association compiler. It cannot establish any runtime capability.
use super::FixtureAlias;
use super::meaning::Role;
use super::scope::{
    ResolvedMeaning, RuntimeBindingObligation, ScopeError, ScopeKey, ScopeWork, SourcePosition,
    Sources, Symbol,
};
use super::walk::{AliasSink, Segment, Trail, WalkAliases};
use super::work::{ClosureError, ClosureOwner, Resource};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(super) struct DefinitionId(usize);

pub(super) struct Definition<'source> {
    pub(super) alias: &'source FixtureAlias,
    pub(super) role: Role,
    pub(super) scope: ScopeKey<'source>,
    pub(super) position: SourcePosition,
    pub(super) origin: DefinitionOrigin,
}
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(super) enum DefinitionOrigin {
    Input,
    Expected,
    ObservationClaim,
}
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(super) enum ReferenceTiming {
    Historical,
    Prearm,
}
pub(super) struct Association<'source> {
    pub(super) alias: &'source FixtureAlias,
    pub(super) scope: ScopeKey<'source>,
    pub(super) definition: DefinitionId,
    pub(super) position: SourcePosition,
    pub(super) binding: Option<RuntimeBindingObligation<'source>>,
}
pub(super) struct CompiledAliases<'source> {
    definitions: Vec<Definition<'source>>,
    associations: Vec<Association<'source>>,
}
impl CompiledAliases<'_> {
    pub(super) fn definitions(&self) -> &[Definition<'_>] {
        &self.definitions
    }
    pub(super) fn associations(&self) -> &[Association<'_>] {
        &self.associations
    }
}
#[derive(Debug)]
pub(super) enum CompileError {
    Owner(ClosureError),
    Scope(ScopeError<ClosureError>),
}
impl From<ClosureError> for CompileError {
    fn from(value: ClosureError) -> Self {
        Self::Owner(value)
    }
}
#[derive(Clone, Copy)]
enum Pass {
    Declarations,
    References,
}

impl ScopeWork for ClosureOwner {
    type Error = ClosureError;
    fn visit(&mut self) -> Result<(), Self::Error> {
        self.charge(Resource::StructuralVisits, 1)
    }
}

fn scope_equal(
    owner: &mut ClosureOwner,
    first: ScopeKey<'_>,
    second: ScopeKey<'_>,
) -> Result<bool, ClosureError> {
    use ScopeKey::{
        CaptureAttempt, ConnectionProvider, ExpectedCheck, ExpectedTrace, OpeningAttempt, Provider,
        Run,
    };
    owner.charge(Resource::StructuralVisits, 1)?;
    match (first, second) {
        (Run(a), Run(b)) => Ok(a == b),
        (
            Provider {
                run: a,
                provider: aa,
            },
            Provider {
                run: b,
                provider: bb,
            },
        ) if a == b => owner.same_alias(aa, bb),
        (ExpectedCheck { run: a, check: aa }, ExpectedCheck { run: b, check: bb }) => {
            Ok(a == b && aa == bb)
        }
        (ExpectedTrace { run: a, trace: aa }, ExpectedTrace { run: b, trace: bb }) => {
            Ok(a == b && aa == bb)
        }
        (
            OpeningAttempt {
                run: a,
                attempt: aa,
            },
            OpeningAttempt {
                run: b,
                attempt: bb,
            },
        ) if a == b => owner.same_alias(aa, bb),
        (
            ConnectionProvider {
                run: a,
                connection: aa,
                provider: aaa,
            },
            ConnectionProvider {
                run: b,
                connection: bb,
                provider: bbb,
            },
        ) if a == b => Ok(owner.same_alias(aa, bb)? && owner.same_alias(aaa, bbb)?),
        (
            CaptureAttempt {
                run: a,
                connection: aa,
                attempt: aaa,
            },
            CaptureAttempt {
                run: b,
                connection: bb,
                attempt: bbb,
            },
        ) if a == b => Ok(owner.same_alias(aa, bb)? && owner.same_alias(aaa, bbb)?),
        _ => Ok(false),
    }
}

fn lookup(
    owner: &mut ClosureOwner,
    definitions: &[Definition<'_>],
    role: Role,
    scope: ScopeKey<'_>,
    alias: &FixtureAlias,
) -> Result<Option<DefinitionId>, ClosureError> {
    owner.ready()?;
    for (index, definition) in definitions.iter().enumerate() {
        owner.charge(Resource::StructuralVisits, 1)?;
        if definition.role == role
            && scope_equal(owner, definition.scope, scope)?
            && owner.same_alias(definition.alias, alias)?
        {
            return Ok(Some(DefinitionId(index)));
        }
    }
    Ok(None)
}

struct Compiler<'owner, 'source> {
    sources: Sources<'source>,
    owner: &'owner mut ClosureOwner,
    pass: Pass,
    result: CompiledAliases<'source>,
}

impl<'source> Compiler<'_, 'source> {
    fn scope_failure(&mut self, error: ScopeError<ClosureError>) -> CompileError {
        match error {
            ScopeError::Work(error) => CompileError::Owner(error),
            other => {
                // The first semantic fault prevents later source or table work.
                let _ = self.owner.refuse::<()>(ClosureError::Semantic);
                CompileError::Scope(other)
            }
        }
    }
    fn expected_only(role: Role) -> bool {
        use Role::*;
        matches!(
            role,
            ExpectedBytes
                | ExpectedRich
                | ExpectedTrace
                | ExpectedCheck
                | ExpectedBinding
                | ExpectedObligation
                | ExpectedEntry
                | ExpectedWork
                | ExpectedLockActor
                | ObservedConnection
                | ObservedCapture
                | ObservedRegistration
                | ObservedWork
        )
    }
    fn declare(
        &mut self,
        symbol: Symbol<'source>,
        role: Role,
        origin: DefinitionOrigin,
    ) -> Result<(), CompileError> {
        self.owner.charge(Resource::Definitions, 1)?;
        if let Some(id) = lookup(
            self.owner,
            &self.result.definitions,
            role,
            symbol.scope,
            symbol.alias,
        )? {
            if origin == DefinitionOrigin::ObservationClaim
                && self.result.definitions[id.0].origin == DefinitionOrigin::ObservationClaim
            {
                return Ok(());
            }
            return self
                .owner
                .refuse(ClosureError::Duplicate)
                .map_err(Into::into);
        }
        self.owner.reserve(&mut self.result.definitions)?;
        self.result.definitions.push(Definition {
            alias: symbol.alias,
            role,
            scope: symbol.scope,
            position: symbol.position,
            origin,
        });
        Ok(())
    }
}

impl<'source> Compiler<'_, 'source> {
    fn associate(
        &mut self,
        symbol: Symbol<'source>,
        roles: &[Role],
        timing: ReferenceTiming,
    ) -> Result<(), CompileError> {
        self.owner.charge(Resource::References, 1)?;
        let mut selected = None;
        for role in roles {
            if let Some(id) = lookup(
                self.owner,
                &self.result.definitions,
                *role,
                symbol.scope,
                symbol.alias,
            )? {
                if selected.is_some() {
                    return self
                        .owner
                        .refuse(ClosureError::Ambiguous)
                        .map_err(Into::into);
                }
                selected = Some(id);
            }
        }
        let Some(id) = selected else {
            return self.owner.refuse(ClosureError::Missing).map_err(Into::into);
        };
        let definition = &self.result.definitions[id.0];
        if let SourcePosition::Action(index) = symbol.position {
            if Self::expected_only(definition.role) {
                return self
                    .owner
                    .refuse(ClosureError::ExpectedDataAsInput)
                    .map_err(Into::into);
            }
            if timing == ReferenceTiming::Prearm {
                if !matches!(definition.role, Role::CaptureAttempt | Role::Writer) {
                    return self
                        .owner
                        .refuse(ClosureError::InvalidPrearmRole)
                        .map_err(Into::into);
                }
            } else if matches!(definition.position, SourcePosition::Action(created) if created > index)
            {
                return self
                    .owner
                    .refuse(ClosureError::ForwardReference)
                    .map_err(Into::into);
            }
        } else if timing == ReferenceTiming::Prearm {
            return self
                .owner
                .refuse(ClosureError::InvalidPrearmRole)
                .map_err(Into::into);
        }
        self.owner.reserve(&mut self.result.associations)?;
        self.result.associations.push(Association {
            alias: symbol.alias,
            scope: symbol.scope,
            definition: id,
            position: symbol.position,
            binding: symbol.binding,
        });
        Ok(())
    }
}

impl<'source> AliasSink<'source> for Compiler<'_, 'source> {
    type Error = CompileError;
    fn enter(&mut self, _trail: &Trail<'_>) -> Result<(), Self::Error> {
        self.owner
            .charge(Resource::StructuralVisits, 1)
            .map_err(Into::into)
    }
    fn alias(
        &mut self,
        alias: &'source FixtureAlias,
        trail: &Trail<'_>,
    ) -> Result<(), Self::Error> {
        let symbol = match self.sources.enclose(alias, trail, self.owner) {
            Ok(symbol) => symbol,
            Err(error) => return Err(self.scope_failure(error)),
        };
        match (self.pass, symbol.meaning) {
            (
                Pass::Declarations,
                ResolvedMeaning::Define(role) | ResolvedMeaning::LocalDefine(role),
            ) => {
                let origin = match symbol.position {
                    SourcePosition::Fixture | SourcePosition::Action(_) => DefinitionOrigin::Input,
                    SourcePosition::Expected(_) => DefinitionOrigin::Expected,
                };
                self.declare(symbol, role, origin)
            }
            (Pass::Declarations, ResolvedMeaning::ObservationClaim(role)) => {
                self.declare(symbol, role, DefinitionOrigin::ObservationClaim)
            }
            (
                Pass::References,
                ResolvedMeaning::Reference(role)
                | ResolvedMeaning::LocalReference(role)
                | ResolvedMeaning::ObservationClaim(role),
            ) => self.associate(symbol, &[role], ReferenceTiming::Historical),
            (Pass::References, ResolvedMeaning::Prearm(role)) => {
                self.associate(symbol, &[role], ReferenceTiming::Prearm)
            }
            (Pass::References, ResolvedMeaning::SubjectReference(roles)) => {
                self.associate(symbol, roles.candidates(), ReferenceTiming::Historical)
            }
            _ => Ok(()),
        }
    }
}

/// Both typed runs and the selected expected operands share this one owner.
/// Success means static name closure only. Binding obligations remain unproved.
pub(super) fn compile<'source>(
    paired: &super::pairing::PairedWorkflow<'source>,
    owner: &mut ClosureOwner,
) -> Result<CompiledAliases<'source>, CompileError> {
    owner.ready()?;
    let sources = Sources::from_paired(paired);
    let mut compiler = Compiler {
        sources,
        owner,
        pass: Pass::Declarations,
        result: CompiledAliases {
            definitions: Vec::new(),
            associations: Vec::new(),
        },
    };
    let root = Trail {
        parent: None,
        segment: Segment::Root,
    };
    for pass in [Pass::Declarations, Pass::References] {
        compiler.pass = pass;
        compiler.sources.input().walk(&root, &mut compiler)?;
        compiler.sources.expected().walk(&root, &mut compiler)?;
    }
    Ok(compiler.result)
}

#[cfg(test)]
#[path = "tests.rs"]
mod tests;
