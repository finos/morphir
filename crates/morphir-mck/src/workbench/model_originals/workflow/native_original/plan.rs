//! One typed DATA plan. SourceVerifier/runtime capability are separate proofs.
use super::super::compile::{self, CompileError, CompiledAliases};
use super::super::expansion::{self, ExpansionOwner, ExpansionUsage};
use super::super::pairing::PairError;
use super::super::source_compile::CompilationError;
use super::super::source_proof::SourceError;
use super::super::work::{ClosureError, ClosureOwner, Resource};
use super::*;

#[derive(Debug, Clone, Copy)]
pub(in crate::workbench::model_originals::workflow) struct ValidatedRunIndex(usize);
impl ValidatedRunIndex {
    pub(in crate::workbench::model_originals::workflow) fn for_original(
        input: &OriginalScenario,
        index: usize,
    ) -> Result<Self, CompilationError> {
        input
            .runs
            .0
            .get(index)
            .map(|_| Self(index))
            .ok_or(CompilationError::Source(SourceError::Pair(
                PairError::RunIndex,
            )))
    }
    pub(in crate::workbench::model_originals::workflow) fn get(self) -> usize {
        self.0
    }
}

/// Retains the genuine shared closure and expansion results and all original
/// typed operands. This DATA plan is not immutable source correspondence,
// an owned host resource, a live run context or a qualification value.
pub(in crate::workbench::model_originals::workflow) struct NativeComparisonPlan<'a> {
    pub(in crate::workbench::model_originals::workflow) input: &'a OriginalScenario,
    pub(in crate::workbench::model_originals::workflow) expected: &'a NativeDeclarationExpectation,
    pub(in crate::workbench::model_originals::workflow) run: ValidatedRunIndex,
    pub(in crate::workbench::model_originals::workflow) aliases: CompiledAliases<'a>,
    pub(in crate::workbench::model_originals::workflow) expansion: ExpansionUsage,
}
impl<'a> NativeComparisonPlan<'a> {
    pub(in crate::workbench::model_originals::workflow) fn witness_metadata(
        &self,
    ) -> Option<WitnessMetadata> {
        // This is only the reviewed first-role DATA recipe. Other originals
        // require their own reviewed immutable asset mapping, never a guessed
        // observed path. The production source compiler must bind this row to
        // the actual configured source bundle before a live invocation.
        first_witness_metadata(&self.input.origin, self.run.get())
    }
    pub(in crate::workbench::model_originals::workflow) fn selected(
        &self,
    ) -> (&'a OriginalHostFixture, &'a [input::HostAction]) {
        match &self.input.runs.0[self.run.get()] {
            OriginalRun::ModelOriginalsServer { fixture, actions } => (fixture, &actions.0),
        }
    }
}
#[derive(Clone, Copy)]
pub(in crate::workbench::model_originals::workflow) struct WitnessMetadata {
    pub(in crate::workbench::model_originals::workflow) output_prefix: &'static str,
    pub(in crate::workbench::model_originals::workflow) record: &'static str,
    pub(in crate::workbench::model_originals::workflow) primary: &'static str,
    pub(in crate::workbench::model_originals::workflow) sentinel: &'static str,
}
pub(in crate::workbench::model_originals::workflow) fn first_witness_metadata(
    origin: &input::PacketRef,
    run: usize,
) -> Option<WitnessMetadata> {
    (run == 0
        && origin.packet.key() == "wire49"
        && origin.id.0 == "explicit-empty-companion-declaration-is-complete"
        && origin.sha256.0
            == [
                0xe1, 0x06, 0x1e, 0xa5, 0x3a, 0xe3, 0x53, 0xe5, 0x93, 0x74, 0x7e, 0x29, 0xcc, 0x4c,
                0xa8, 0x0b, 0x24, 0xf2, 0x8d, 0x2c, 0x04, 0x8a, 0x70, 0xac, 0x2b, 0xa2, 0x9f, 0x45,
                0x3b, 0x0c, 0xe3, 0xa5,
            ])
    .then_some(WitnessMetadata {
        output_prefix: ".morphir/out/compile.dest/",
        record: ".morphir/out/compile.json",
        primary: ".morphir/out/compile.dest/model.json",
        sentinel: ".morphir/out/compile.dest/secret",
    })
}

fn owner_error(error: ClosureError) -> CompilationError {
    CompilationError::Closure(CompileError::Owner(error))
}
fn mismatch(owner: &mut ClosureOwner, error: PairError) -> CompilationError {
    // Retain the genuine closure's first fault; preserve the more precise
    // typed pairing boundary in the returned compiler error.
    let _ = owner.refuse::<()>(ClosureError::Semantic);
    CompilationError::Source(SourceError::Pair(error))
}

pub(in crate::workbench::model_originals::workflow) fn compile_native_plan<'a>(
    input: &'a OriginalScenario,
    expected: &'a NativeDeclarationExpectation,
    run: ValidatedRunIndex,
    owner: &mut ClosureOwner,
    expansion_owner: &mut ExpansionOwner,
) -> Result<NativeComparisonPlan<'a>, CompilationError> {
    owner.ready().map_err(owner_error)?;
    expansion_owner
        .ready()
        .map_err(CompilationError::Expansion)?;
    if run.get() >= input.runs.0.len() {
        return Err(mismatch(owner, PairError::RunIndex));
    }
    owner
        .charge(Resource::StructuralVisits, 1)
        .map_err(owner_error)?;
    if !owner
        .same_text(input.origin.packet.key(), expected.origin.packet.key())
        .map_err(owner_error)?
    {
        return Err(mismatch(owner, PairError::Packet));
    }
    owner
        .charge(Resource::LookupBytes, 64)
        .map_err(owner_error)?;
    if input.origin.sha256 != expected.origin.sha256 {
        return Err(mismatch(owner, PairError::Digest));
    }
    if !owner
        .same_text(&input.origin.id.0, &expected.origin.id.0)
        .map_err(owner_error)?
    {
        return Err(mismatch(owner, PairError::Case));
    }
    // Both source dialects enter one actual alias compiler. No current
    // Scenario/configPolicy/default ledger values are fabricated.
    let aliases =
        compile::compile_native(input, expected, run, owner).map_err(CompilationError::Closure)?;
    // Alias failure stops the existing shared recipe algorithm before effects.
    let expansion =
        expansion::measure_native(input, expansion_owner).map_err(CompilationError::Expansion)?;
    Ok(NativeComparisonPlan {
        input,
        expected,
        run,
        aliases,
        expansion,
    })
}
