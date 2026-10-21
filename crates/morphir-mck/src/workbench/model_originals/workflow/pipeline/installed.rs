//! The existing complete preparation gate is the sole inventory/run issuer.
use super::super::UniqueKey;
use super::super::{
    installed_client::{InstalledClientPlan, OriginalClientLeafBinding, PublicationObservation},
    source_compile::CompiledSourceCase,
    source_proof::LineageStatus,
};
use super::*;

pub mod adapter;
pub(super) mod observation;

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

/// Saved DATA undergoes the same source preparation and factual checker. It
/// cannot recreate a live invocation, host credential or qualified result.
pub(in crate::workbench) fn replay_installed(
    source: &Source,
    policy: &Policy,
    report: &StoredReport,
) -> Result<(), String> {
    prepared_installed_client(
        source,
        policy,
        ReviewedSources::installed_client_selected(),
        |prepared, owners| {
            ready(owners).map_err(|_| "source owners refused before replay")?;
            let document =
                Document::parse_exact_with_work(report.text().as_bytes(), &mut owners.saved)
                    .map_err(|_| "saved report decode refused")?;
            let saved = wire::saved(document, &mut owners.decode)
                .map_err(|_| "saved report decode refused")?;
            let compiled = prepared.cases();
            if saved.corpus_hash != source.digest() || saved.records.len() != compiled.len() {
                return Err("inventory fullfile/count differs".into());
            }
            if saved.capabilities.is_some() || saved.negotiation.is_some() {
                return Err("installed report cannot claim external negotiation".into());
            }
            for (row, case) in saved.records.iter().zip(compiled) {
                owners
                    .decode
                    .bytes(
                        row.case_id
                            .len()
                            .checked_add(case.case().id().len())
                            .ok_or("inventory overflow")?,
                    )
                    .map_err(|_| "inventory work refused")?;
                if row.case_id != case.case().id()
                    || !row
                        .execution
                        .matches_compiled(case, &mut owners.decode)
                        .map_err(|_| "inventory work refused")?
                {
                    return Err("inventory execution key/order differs".into());
                }
            }
            let mut attempt = Attempt { fault: None };
            for (row, case) in saved.records.iter().zip(compiled) {
                if attempt.ready().is_err() {
                    if !matches!(
                        row.evidence,
                        Evidence::NotAttempted {
                            prior_failure_index: 0
                        }
                    ) {
                        return Err("evidence after first failure".into());
                    }
                    continue;
                }
                let Some(case) = case.current() else {
                    return Err("installed evidence source kind differs".into());
                };
                if let Evidence::AttemptFailed { failure_index: 0 } = row.evidence {
                    if case.installed().is_none() {
                        return Err("installed failure/source kind differs".into());
                    }
                    let category = [
                        adapter::InstalledAdapterError::Cancelled,
                        adapter::InstalledAdapterError::ObservationIncomplete,
                    ]
                    .into_iter()
                    .find(|error| {
                        saved
                            .errors
                            .first()
                            .is_some_and(|row| row.matches(RunFault::Installed(*error).summary()))
                    })
                    .ok_or("unverified incomplete installed attempt category")?;
                    // Closed failure DATA only. No replay callback, live owner,
                    // source grant or qualification is reconstructed.
                    attempt.fail(RunFault::Installed(category));
                    continue;
                }
                let Evidence::ClientProcessMeasured {
                    measurement,
                    verdict,
                } = &row.evidence
                else {
                    return Err("installed factual evidence missing".into());
                };
                ready(owners).map_err(|_| "replay owner refused")?;
                let size = crate::workbench::contract::encoded_size(
                    measurement.value(),
                    MAX_REPORT_BYTES,
                )?;
                owners
                    .capture
                    .retain(0, size)
                    .map_err(|_| "capture aggregate refused")?;
                match case
                    .report_context()
                    .check_installed_process(measurement.value(), &mut owners.comparison)
                {
                    Err(error) if matches!(verdict, Verdict::Failed { failure_index: 0 }) => {
                        attempt.fail(RunFault::Record(WorkflowRecordError::Observation(error)))
                    }
                    _ => return Err("forged installed factual verdict".into()),
                }
            }
            match &attempt.fault {
                Some(error)
                    if saved.errors.len() == 1 && saved.errors[0].matches(error.summary()) => {}
                _ => return Err("saved first failure differs".into()),
            }
            if saved.qualified {
                return Err("forged qualified claim for partial/unproven source set".into());
            }
            Ok(())
        },
    )
}

/// Same canonical inventory gate and report/checker, with explicitly selected
/// installed effects. All owners live outside every case/command callback.
pub(in crate::workbench) fn execute_installed(
    source: &Source,
    policy: &Policy,
    limits: &crate::workbench::configuration::NativeObservationLimits,
    record_limits: &crate::workbench::configuration::RecordRetentionLimits,
    receiving_limits: &crate::workbench::configuration::InstalledObservationLimits,
    consumer: crate::workbench::configuration::ConsumerObservationSelection,
    adapter: &mut dyn adapter::InstalledClientAdapter,
) -> Result<StoredReport, String> {
    let mut record_owner =
        super::super::native::record_retention::RecordRetentionOwner::new(record_limits);
    let mut receiving = observation::InstalledObservationOwner::new(receiving_limits);
    prepared_installed_client(
        source,
        policy,
        ReviewedSources::installed_client_selected(),
        |inventory, owners| {
            owners
                .decode
                .slots(inventory.len())
                .map_err(|_| "inventory work refused")?;
            let mut records = Vec::new();
            records
                .try_reserve_exact(inventory.len())
                .map_err(|_| "inventory allocation refused")?;
            owners
                .decode
                .slots(1)
                .map_err(|_| "failure inventory work refused")?;
            let mut errors = Vec::new();
            errors
                .try_reserve_exact(1)
                .map_err(|_| "failure inventory allocation refused")?;
            let mut attempt = Attempt { fault: None };
            for case in inventory.cases() {
                let evidence = if attempt.ready().is_err() {
                    Evidence::NotAttempted {
                        prior_failure_index: 0,
                    }
                } else {
                    let result = ready(owners).and_then(|()| {
                        record_owner
                            .ready()
                            .map_err(|error| RunFault::RecordRetention(*error))?;
                        receiving
                            .ready()
                            .map_err(|error| RunFault::InstalledObservation(*error))?;
                        let current = case
                            .current()
                            .filter(|current| current.installed().is_some())
                            .ok_or(RunFault::UnsupportedRole)?;
                        let mut revoker = adapter::InvocationRevoker::new(consumer);
                        let result = adapter.observe(adapter::InstalledClientRun::from_prepared(
                            inventory.invocation(),
                            limits,
                            &mut owners.comparison,
                            &mut record_owner,
                            &mut attempt,
                            adapter::HostObservationOwners {
                                receiving: &mut receiving,
                                revoker: &mut revoker,
                                capture: &mut owners.capture,
                                decode: &mut owners.decode,
                            },
                        ));
                        if revoker.consumer_fault() {
                            attempt.fail(RunFault::InstalledObservation(
                                observation::InstalledObservationFault::Abandoned,
                            ));
                        }
                        drop(revoker);
                        owners.comparison.ready().map_err(|error| {
                            RunFault::Record(WorkflowRecordError::Observation(error))
                        })?;
                        record_owner
                            .ready()
                            .map_err(|error| RunFault::RecordRetention(*error))?;
                        receiving
                            .ready()
                            .map_err(|error| RunFault::InstalledObservation(*error))?;
                        let actual = result.map_err(RunFault::Installed)?;
                        let size =
                            crate::workbench::contract::encoded_size(&actual, MAX_REPORT_BYTES)
                                .map_err(|_| RunFault::Capture(CaptureFault::Reply))?;
                        owners.capture.retain(0, size).map_err(RunFault::Capture)?;
                        let measurement =
                            wire::ClientProcessMeasurement::retain(actual, &mut owners.decode)
                                .map_err(RunFault::Decode)?;
                        let verdict = match current
                            .report_context()
                            .check_installed_process(measurement.value(), &mut owners.comparison)
                        {
                            Ok(()) => Verdict::Checked,
                            Err(error) => {
                                attempt.fail(RunFault::Record(WorkflowRecordError::Observation(
                                    error,
                                )));
                                Verdict::Failed { failure_index: 0 }
                            }
                        };
                        Ok(Evidence::ClientProcessMeasured {
                            measurement,
                            verdict,
                        })
                    });
                    match result {
                        Ok(evidence) => evidence,
                        Err(error) => {
                            attempt.fail(error);
                            Evidence::AttemptFailed { failure_index: 0 }
                        }
                    }
                };
                records.push(RuntimeRecord {
                    case_id: case.case().id(),
                    execution: ExecutionRef::from_compiled(case),
                    evidence,
                });
            }
            if let Some(fault) = &attempt.fault {
                errors.push(fault.summary())
            }
            render(PreparedExecution {
                report: RuntimeReport {
                    format_version: VERSION,
                    suite: "workbench",
                    corpus_hash: source.digest(),
                    capabilities: None,
                    negotiation: None,
                    records,
                    errors,
                    qualified: false,
                },
                attempt,
                shutdown: None,
            })
        },
    )
}
