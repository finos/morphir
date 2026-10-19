//! Compose reviewed byte correspondence, static aliases and recipe expansion.
//! The three genuine caller policies stay separate and cumulative. This does
//! not establish semantic lineage, runtime capability or readiness.
use super::DecodeUsage;
use super::compile::{self, CompileError, CompiledAliases};
use super::expansion::{ExpansionError, ExpansionOwner, ExpansionUsage, ScenarioExpansion};
use super::identity_input::{IdentityInputError, IdentityInputPlan};
use super::ingress::BoundCase;
use super::observation_check::{self, CompareOwner, ComparedPredicates, ObservationError};
use super::observed;
use super::pairing::PairedWorkflow;
pub(super) use super::record_check::WorkflowRecordError;
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
}
impl<'case, 'sources, 'raw, 'supplied> CompiledSourceCase<'case, 'sources, 'raw, 'supplied> {
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

        let source = self.verifier.bind(case).map_err(CompilationError::Source)?;
        // bind already paid the genuine paired_with_work comparison. Reuse
        // that same value instead of revalidating metadata without a debit.
        let aliases =
            compile::compile(source.paired(), self.closure).map_err(CompilationError::Closure)?;
        let identity_input = IdentityInputPlan::from_paired(source.paired(), self.closure)
            .map_err(CompilationError::IdentityInput)?;
        let expansion = ScenarioExpansion::measure(source.paired().scenario(), self.expansion)
            .map_err(CompilationError::Expansion)?;
        Ok(CompiledSourceCase {
            source,
            aliases,
            expansion,
            identity_input,
        })
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
