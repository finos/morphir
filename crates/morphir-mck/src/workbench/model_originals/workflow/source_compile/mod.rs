//! Compose reviewed byte correspondence, static aliases and recipe expansion.
//! The three genuine caller policies stay separate and cumulative. This does
//! not establish semantic lineage, runtime capability or readiness.
use super::DecodeUsage;
use super::compile::{self, CompileError, CompiledAliases};
use super::expansion::{ExpansionError, ExpansionOwner, ExpansionUsage, ScenarioExpansion};
use super::identity_input::{IdentityInputError, IdentityInputPlan};
use super::ingress::BoundCase;
use super::native_original::{self, NativeComparisonPlan};
use super::observation_check::{self, CompareOwner, ComparedPredicates, ObservationError};
use super::observed;
use super::pairing::PairedWorkflow;
pub(super) use super::record_check::WorkflowRecordError;
use super::source_proof::MatchedNativeSourceCase;
use super::source_proof::{LineageStatus, MatchedSourceCase, SourceError, SourceVerifier};
use super::work::{ClosureOwner, ClosureUsage};
use serde_json::value::RawValue;

#[derive(Debug)]
pub(super) enum CompilationError {
    Source(SourceError),
    Closure(CompileError),
    Expansion(ExpansionError),
    IdentityInput(IdentityInputError),
}

/// Observations of distinct existing ledgers, never a combined runtime quota.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(super) struct CompilationUsage {
    pub(super) decode: DecodeUsage,
    pub(super) closure: ClosureUsage,
    pub(super) expansion: ExpansionUsage,
}

/// All operands and source views remain borrowed from their genuine owners.
/// Only this module can assemble these static proofs into a result.
pub(super) struct CompiledSourceCase<'case, 'sources, 'raw, 'supplied> {
    source: MatchedSourceCase<'case, 'sources, 'raw, 'supplied>,
    aliases: CompiledAliases<'case>,
    expansion: ScenarioExpansion<'case>,
    identity_input: IdentityInputPlan<'case>,
    installed: Option<super::installed_client::InstalledClientPlan<'case>>,
}
pub(super) struct CompiledNativeSourceCase<'case, 'sources, 'raw, 'supplied> {
    source: MatchedNativeSourceCase<'case, 'sources, 'raw, 'supplied>,
    plan: NativeComparisonPlan<'case>,
}
impl<'case, 'raw> CompiledNativeSourceCase<'case, '_, 'raw, '_> {
    pub(super) fn source(&self) -> &MatchedNativeSourceCase<'case, '_, 'raw, '_> {
        &self.source
    }
    pub(super) fn plan(&self) -> &NativeComparisonPlan<'case> {
        &self.plan
    }
}
pub(super) enum CompiledExecution<'case, 'sources, 'raw, 'supplied> {
    Current(CompiledSourceCase<'case, 'sources, 'raw, 'supplied>),
    Native(CompiledNativeSourceCase<'case, 'sources, 'raw, 'supplied>),
}
impl<'case, 'raw> CompiledExecution<'case, '_, 'raw, '_> {
    pub(super) fn case(&self) -> &'case BoundCase<'raw> {
        match self {
            Self::Current(value) => value.source.case(),
            Self::Native(value) => value.source.case(),
        }
    }
    pub(super) fn current(&self) -> Option<&CompiledSourceCase<'case, '_, 'raw, '_>> {
        match self {
            Self::Current(value) => Some(value),
            Self::Native(_) => None,
        }
    }
    pub(super) fn origin(&self) -> &super::input::PacketRef {
        match self {
            Self::Current(value) => &value.source.paired().scenario().origin,
            Self::Native(value) => &value.source.input().origin,
        }
    }
    pub(super) fn run_index(&self) -> usize {
        match self {
            Self::Current(value) => value.source.paired().run_index(),
            Self::Native(value) => value.source.run().get(),
        }
    }
}
impl<'case, 'sources, 'raw, 'supplied> CompiledSourceCase<'case, 'sources, 'raw, 'supplied> {
    pub(super) fn installed(&self) -> Option<&super::installed_client::InstalledClientPlan<'case>> {
        self.installed.as_ref()
    }
    pub(super) fn source(&self) -> &MatchedSourceCase<'case, 'sources, 'raw, 'supplied> {
        &self.source
    }
    pub(super) fn aliases(&self) -> &CompiledAliases<'case> {
        &self.aliases
    }
    pub(super) fn identity_input(&self) -> &IdentityInputPlan<'case> {
        &self.identity_input
    }
    pub(super) fn expansion(&self) -> &ScenarioExpansion<'case> {
        &self.expansion
    }
    pub(super) fn report_context(
        &self,
    ) -> WorkflowReportContext<'_, 'case, 'sources, 'raw, 'supplied> {
        WorkflowReportContext { compiled: self }
    }
}

/// A report borrows the genuine compiler result, including its already-paid
/// identity plan. Saved metadata cannot construct or replace this context.
/// Source correspondence alone leaves semantic lineage unproven.
pub(super) struct WorkflowReportContext<'compiled, 'case, 'sources, 'raw, 'supplied> {
    compiled: &'compiled CompiledSourceCase<'case, 'sources, 'raw, 'supplied>,
}
impl<'case, 'raw> WorkflowReportContext<'_, 'case, '_, 'raw, '_> {
    pub(super) fn case(&self) -> &'case BoundCase<'raw> {
        self.compiled.source.case()
    }
    pub(super) fn paired(&self) -> &PairedWorkflow<'case> {
        self.compiled.source.paired()
    }
    pub(super) fn input_raw(&self) -> &'raw RawValue {
        self.case().input_raw()
    }
    pub(super) fn lineage(&self) -> LineageStatus {
        self.compiled.source.lineage()
    }
    pub(super) fn check_installed_process(
        &self,
        actual: &super::installed_measurements::InstalledClientMeasurements,
        owner: &mut CompareOwner,
    ) -> Result<(), ObservationError> {
        observation_check::installed::check(self.paired(), self.compiled.installed(), actual, owner)
    }
    pub(super) fn check_observation<'actual>(
        &self,
        actual: &'actual observed::Observation,
        owner: &mut CompareOwner,
    ) -> Result<ComparedPredicates<'case, 'actual>, ObservationError> {
        observation_check::check_planned(
            self.paired(),
            &self.compiled.identity_input,
            actual,
            owner,
        )
    }
}

/// No Clone, reset, free source constructor or implicit per-case policy.
pub(super) struct CaseCompiler<'owner, 'policies, 'sources, 'supplied> {
    verifier: SourceVerifier<'owner, 'sources, 'supplied>,
    closure: &'policies mut ClosureOwner,
    expansion: &'policies mut ExpansionOwner,
    fault: Option<CompilationError>,
}
impl<'owner, 'policies, 'sources, 'supplied> CaseCompiler<'owner, 'policies, 'sources, 'supplied> {
    pub(super) fn new(
        verifier: SourceVerifier<'owner, 'sources, 'supplied>,
        closure: &'policies mut ClosureOwner,
        expansion: &'policies mut ExpansionOwner,
    ) -> Self {
        Self {
            verifier,
            closure,
            expansion,
            fault: None,
        }
    }

    /// Additional actual pipeline inventory work on the same first-fault owner.
    pub(super) fn require_inventory<'compiler>(
        &'compiler mut self,
        cases: &[BoundCase<'_>],
    ) -> Result<(), &'compiler CompilationError> {
        if self.fault.is_none()
            && let Err(error) = self.verifier.require_inventory(cases)
        {
            self.fault = Some(CompilationError::Source(error));
        }
        match &self.fault {
            Some(error) => Err(error),
            None => Ok(()),
        }
    }
    pub(super) fn usage(&self) -> CompilationUsage {
        CompilationUsage {
            decode: self.verifier.usage(),
            closure: self.closure.usage(),
            expansion: self.expansion.usage(),
        }
    }

    fn compile_case<'case, 'raw>(
        &mut self,
        case: &'case BoundCase<'raw>,
    ) -> Result<CompiledSourceCase<'case, 'sources, 'raw, 'supplied>, CompilationError> {
        // Observe all existing faults before any new source effects. These
        // readiness calls neither replace owners nor reset their spent work.
        self.verifier
            .ready()
            .map_err(|error| CompilationError::Source(SourceError::Decode(error)))?;
        self.closure
            .ready()
            .map_err(|error| CompilationError::Closure(CompileError::Owner(error)))?;
        self.expansion
            .ready()
            .map_err(CompilationError::Expansion)?;

        let mut source = self.verifier.bind(case).map_err(CompilationError::Source)?;
        // bind already paid the genuine paired_with_work comparison. Reuse
        // that same value instead of revalidating metadata without a debit.
        let aliases =
            compile::compile(source.paired(), self.closure).map_err(CompilationError::Closure)?;
        let identity_input = IdentityInputPlan::from_paired(source.paired(), self.closure)
            .map_err(CompilationError::IdentityInput)?;
        let expansion = ScenarioExpansion::measure(source.paired().scenario(), self.expansion)
            .map_err(CompilationError::Expansion)?;
        let installed = source
            .take_installed()
            .map(|reviewed| {
                super::installed_client::InstalledClientPlan::compile(
                    reviewed,
                    source.paired(),
                    self.closure,
                    self.expansion,
                )
            })
            .transpose()?;
        Ok(CompiledSourceCase {
            source,
            aliases,
            expansion,
            identity_input,
            installed,
        })
    }
    fn compile_native_case<'case, 'raw>(
        &mut self,
        case: &'case BoundCase<'raw>,
    ) -> Result<CompiledNativeSourceCase<'case, 'sources, 'raw, 'supplied>, CompilationError> {
        self.verifier
            .ready()
            .map_err(|error| CompilationError::Source(SourceError::Decode(error)))?;
        self.closure
            .ready()
            .map_err(|error| CompilationError::Closure(CompileError::Owner(error)))?;
        self.expansion
            .ready()
            .map_err(CompilationError::Expansion)?;
        let source = self
            .verifier
            .bind_native(case)
            .map_err(CompilationError::Source)?;
        // Same cumulative alias and expansion algorithms, after exact actual
        // source proof. A free DATA plan cannot construct this wrapper.
        let plan = native_original::compile_native_plan(
            source.input(),
            source.expected(),
            source.run(),
            self.closure,
            self.expansion,
        )?;
        Ok(CompiledNativeSourceCase { source, plan })
    }
    pub(super) fn compile_execution<'compiler, 'case, 'raw>(
        &'compiler mut self,
        case: &'case BoundCase<'raw>,
    ) -> Result<CompiledExecution<'case, 'sources, 'raw, 'supplied>, &'compiler CompilationError>
    {
        if self.fault.is_none() {
            let result = if case.native_operands().is_some() {
                self.compile_native_case(case)
                    .map(CompiledExecution::Native)
            } else {
                self.compile_case(case).map(CompiledExecution::Current)
            };
            match result {
                Ok(value) => return Ok(value),
                Err(error) => self.fault = Some(error),
            }
        }
        Err(self
            .fault
            .as_ref()
            .expect("failed compiler retains its fault"))
    }

    pub(super) fn compile<'compiler, 'case, 'raw>(
        &'compiler mut self,
        case: &'case BoundCase<'raw>,
    ) -> Result<CompiledSourceCase<'case, 'sources, 'raw, 'supplied>, &'compiler CompilationError>
    {
        if self.fault.is_none() {
            match self.compile_case(case) {
                Ok(compiled) => return Ok(compiled),
                Err(error) => {
                    // Move the exact error into stable compiler state. Later
                    // calls return this borrow without cloning or phase work.
                    self.fault = Some(error);
                }
            }
        }
        Err(self
            .fault
            .as_ref()
            .expect("failed compiler retains its fault"))
    }
}

#[cfg(test)]
mod tests;
