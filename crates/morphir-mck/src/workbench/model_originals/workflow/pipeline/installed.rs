//! The existing complete preparation gate is the sole inventory/run issuer.
use super::super::UniqueKey;
use super::super::{
    installed_client::{InstalledClientPlan, OriginalClientLeafBinding, PublicationObservation},
    source_compile::CompiledSourceCase,
    source_proof::LineageStatus,
};
use super::*;

pub(super) struct PreparedInstalledClientInventory<'inventory, 'case, 'sources, 'raw, 'supplied> {
    cases: &'inventory [CompiledExecution<'case, 'sources, 'raw, 'supplied>],
    selected: &'inventory CompiledSourceCase<'case, 'sources, 'raw, 'supplied>,
}
impl<'inventory, 'case, 'sources, 'raw, 'supplied>
    PreparedInstalledClientInventory<'inventory, 'case, 'sources, 'raw, 'supplied>
{
    pub(super) fn len(&self) -> usize {
        self.cases.len()
    }
    pub(super) fn cases(&self) -> &[CompiledExecution<'case, 'sources, 'raw, 'supplied>] {
        self.cases
    }
    pub(super) fn invocation(&self) -> InstalledClientRun<'_, 'case, 'sources, 'raw, 'supplied> {
        InstalledClientRun {
            selected: self.selected,
            plan: self
                .selected
                .installed()
                .expect("canonical issuer verified plan"),
        }
    }
}
/// Engine-internal view. Expected/raw/core accessors cannot reach adapters.
/// No Clone/Deserialize/constructor and no source/context can escape prepared R.
pub(super) struct InstalledClientRun<'run, 'case, 'sources, 'raw, 'supplied> {
    selected: &'run CompiledSourceCase<'case, 'sources, 'raw, 'supplied>,
    plan: &'run InstalledClientPlan<'case>,
}
impl<'case, 'sources, 'raw, 'supplied> InstalledClientRun<'_, 'case, 'sources, 'raw, 'supplied> {
    pub(super) fn case_id(&self) -> &str {
        self.selected.source().case().id()
    }
    pub(super) fn original_packet(&self) -> &str {
        self.selected
            .source()
            .paired()
            .scenario()
            .origin
            .packet
            .key()
    }
    pub(super) fn original_id(&self) -> &str {
        &self.selected.source().paired().scenario().origin.id.0
    }
    pub(super) fn run_index(&self) -> usize {
        self.selected.source().paired().run_index()
    }
    pub(super) fn operation(&self) -> crate::workbench::Operation {
        crate::workbench::Operation::ModelOriginalsClient
    }
    pub(super) fn lineage(&self) -> LineageStatus {
        self.selected.source().lineage()
    }
    pub(super) fn input_raw(&self) -> &'raw RawValue {
        self.selected.source().case().input_raw()
    }
    pub(super) fn expected_raw(&self) -> &'raw RawValue {
        self.selected.source().case().expected_raw()
    }
    pub(super) fn compiled_source(&self) -> &CompiledSourceCase<'case, 'sources, 'raw, 'supplied> {
        self.selected
    }
    pub(super) fn actions(&self) -> impl Iterator<Item = &super::super::installed_client::Action> {
        self.plan.actions()
    }
    pub(super) fn original_leaf_bindings(
        &self,
    ) -> impl Iterator<Item = OriginalClientLeafBinding<'_>> {
        self.plan.leaves()
    }
    pub(super) fn publication_observation(&self) -> PublicationObservation {
        self.plan.publication()
    }
}

pub(super) fn prepared_installed_client<R>(
    source: &Source,
    policy: &Policy,
    sources: ReviewedSources<'_>,
    action: impl FnOnce(
        PreparedInstalledClientInventory<'_, '_, '_, '_, '_>,
        &mut Owners,
    ) -> Result<R, String>,
) -> Result<R, String> {
    if sources.source_set() != super::super::reviewed_sources::SourceSet::InstalledClientFirst {
        return Err("source correspondence refused".to_owned());
    }
    // SAME slot allocation, bound corpus, all-case compiler, owner latches and
    // ordered require_inventory. This wrapper cannot omit or replace any step.
    prepared(source, policy, sources, |cases, owners| {
        ready(owners).map_err(|_| "source owner refused before invocation".to_owned())?;
        let selected = cases
            .first()
            .and_then(CompiledExecution::current)
            .filter(|case| case.installed().is_some())
            .ok_or_else(|| "source correspondence refused".to_owned())?;
        action(PreparedInstalledClientInventory { cases, selected }, owners)
    })
}
