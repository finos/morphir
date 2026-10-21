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
    consumer: crate::workbench::configuration::ConsumerObservationSelection,
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
            if saved.revision == super::report_revision::ReportRevision::Consumer31
                && matches!(
                    consumer,
                    crate::workbench::configuration::ConsumerObservationSelection::Disabled
                )
            {
                return Err(
                    "consumer report revision requires explicit operation selection".into(),
                );
            }
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
            // Replay retains a closed first-failure summary, never a recreated
            // live consumer/process fault or invocation authority.
            let mut first_failure = None;
            for (row, case) in saved.records.iter().zip(compiled) {
                if first_failure.is_some() {
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
                if matches!(
                    row.evidence,
                    Evidence::AttemptFailed { failure_index: 0 }
                        | Evidence::StoredConsumerAttemptFailed {
                            failure_index: 0,
                            ..
                        }
                ) {
                    if case.installed().is_none() {
                        return Err("installed failure/source kind differs".into());
                    }
                    let mut category = None;
                    if let Some(first) = saved.errors.first() {
                        for error in [
                            adapter::InstalledAdapterError::Cancelled,
                            adapter::InstalledAdapterError::ObservationIncomplete,
                        ] {
                            let summary = RunFault::Installed(error).summary();
                            if first
                                .matches_with_work(summary, &mut owners.decode)
                                .map_err(|_| "saved first failure work refused")?
                            {
                                category = Some(summary);
                                break;
                            }
                        }
                        if category.is_none()
                            && matches!(
                                consumer,
                                crate::workbench::configuration::ConsumerObservationSelection::OperationPort(_)
                            )
                        {
                            for kind in adapter::processes::ConsumerFailureKind::ALL {
                                let summary = FailureSummary::consumer(kind);
                                if first
                                    .matches_with_work(summary, &mut owners.decode)
                                    .map_err(|_| "saved first failure work refused")?
                                {
                                    category = Some(summary);
                                    break;
                                }
                            }
                        }
                    }
                    let category =
                        category.ok_or("unverified incomplete installed attempt category")?;
                    if let Evidence::StoredConsumerAttemptFailed {
                        consumer_failure, ..
                    } = &row.evidence
                    {
                        if !matches!(consumer,crate::workbench::configuration::ConsumerObservationSelection::OperationPort(_)) {
                            return Err("consumer partial selection differs".into());
                        }
                        let plan = case.installed().ok_or("consumer partial source differs")?;
                        consumer_failure
                            .value()
                            .check(plan, &mut owners.comparison)
                            .map_err(|_| "consumer partial factual consistency refused")?;
                        if !consumer_failure
                            .value()
                            .matches_first(category, &mut owners.decode)
                            .map_err(|_| "consumer first failure work refused")?
                        {
                            return Err("consumer record first failure differs".into());
                        }
                    }
                    // Closed failure DATA only. No replay callback, live owner,
                    // source grant or qualification is reconstructed.
                    first_failure = Some(category);
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
                        first_failure = Some(
                            RunFault::Record(WorkflowRecordError::Observation(error)).summary(),
                        )
                    }
                    _ => return Err("forged installed factual verdict".into()),
                }
            }
            match first_failure {
                Some(summary) if saved.errors.len() == 1 => {
                    if !saved.errors[0]
                        .matches_with_work(summary, &mut owners.decode)
                        .map_err(|_| "saved first failure work refused")?
                    {
                        return Err("saved first failure differs".into());
                    }
                }
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
            let mut consumer_output: Option<adapter::ReservedConsumerOutput> = None;
            for case in inventory.cases() {
                let evidence = if attempt.ready().is_err() {
                    Evidence::NotAttempted {
                        prior_failure_index: 0,
                    }
                } else if matches!(
                    consumer,
                    crate::workbench::configuration::ConsumerObservationSelection::OperationPort(_)
                ) {
                    let current = ready(owners).and_then(|()| {
                        // This closed source allocation selects one installed
                        // case. Refuse another effect rather than replace its
                        // unique preissued report writer with a later one.
                        if consumer_output.is_some() {
                            return Err(RunFault::UnsupportedRole);
                        }
                        record_owner
                            .ready()
                            .map_err(|error| RunFault::RecordRetention(*error))?;
                        receiving
                            .ready()
                            .map_err(|error| RunFault::InstalledObservation(*error))?;
                        case.current()
                            .filter(|current| current.installed().is_some())
                            .ok_or(RunFault::UnsupportedRole)
                    });
                    match current {
                        Err(error) => {
                            attempt.fail(error);
                            Evidence::AttemptFailed { failure_index: 0 }
                        }
                        Ok(current) => {
                            // The SAME collection survives an adapter error on
                            // this stack. The callback receives only its loan.
                            let mut collected =
                                super::super::installed_measurements::LiveMeasurements::new();
                            let mut revoker = adapter::InvocationRevoker::new(consumer);
                            let actual =
                                adapter.observe(adapter::InstalledClientRun::from_prepared(
                                    inventory.invocation(),
                                    limits,
                                    &mut owners.comparison,
                                    &mut record_owner,
                                    &mut attempt,
                                    adapter::HostObservationOwners {
                                        collected: &mut collected,
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
                            match actual {
                                Ok(mut actual) => {
                                    let Some(record) = actual
                                        .consumer
                                        .as_mut()
                                        .and_then(|record| record.live_mut())
                                    else {
                                        attempt.fail(RunFault::Installed(
                                            adapter::InstalledAdapterError::ObservationIncomplete,
                                        ));
                                        // Never publish a smaller report by
                                        // discarding an actual owned result.
                                        drop((actual, collected));
                                        return Err("consumer terminal record missing".into());
                                    };
                                    consumer_output =
                                        Some(record.take_output().ok_or(
                                            "consumer output permission already consumed",
                                        )?);
                                    let slot = record.take_measurement_slot();
                                    let measurement =
                                        wire::ClientProcessMeasurement::retain_reserved(
                                            actual, slot,
                                        );
                                    let verdict =
                                        match current.report_context().check_installed_process(
                                            measurement.value(),
                                            &mut owners.comparison,
                                        ) {
                                            Ok(()) => Verdict::Checked,
                                            Err(error) => {
                                                attempt.fail(RunFault::Record(
                                                    WorkflowRecordError::Observation(error),
                                                ));
                                                Verdict::Failed { failure_index: 0 }
                                            }
                                        };
                                    Evidence::ClientProcessMeasured {
                                        measurement,
                                        verdict,
                                    }
                                }
                                Err(error) => {
                                    attempt.fail(RunFault::Installed(error));
                                    if let Some(record) = collected.consumer.as_mut() {
                                        consumer_output = Some(record.take_output().ok_or(
                                            "consumer output permission already consumed",
                                        )?);
                                        let slot = record.take_failure_slot();
                                        Evidence::ConsumerAttemptFailed {
                                            failure_index: 0,
                                            consumer_failure:
                                                wire::ClientPartialFailure::retain_reserved(
                                                    collected, slot,
                                                ),
                                        }
                                    } else {
                                        Evidence::AttemptFailed { failure_index: 0 }
                                    }
                                }
                            }
                        }
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
                        let mut collected =
                            super::super::installed_measurements::LiveMeasurements::new();
                        let result = adapter.observe(adapter::InstalledClientRun::from_prepared(
                            inventory.invocation(),
                            limits,
                            &mut owners.comparison,
                            &mut record_owner,
                            &mut attempt,
                            adapter::HostObservationOwners {
                                collected: &mut collected,
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
            let mut execution = PreparedExecution {
                report: RuntimeReport {
                    format_version: super::report_revision::ReportRevision::selected(consumer)
                        .text(),
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
            };
            if let Some(output) = consumer_output {
                // The complete owned raw report remains here through either
                // bounded success or refusal. No partial report is published.
                match output.encode_report(&execution.report) {
                    Ok(encoded) => {
                        let text = encoded.into_text();
                        if let Err(fault) = owners.capture.retain(0, text.len()) {
                            execution.attempt.fail(RunFault::Capture(fault));
                            // Accounting refusal is secondary to any existing
                            // fault. Keep both raw report and encoded backing
                            // until their explicit disposal, publish nothing.
                            drop((execution, text));
                            return Err("consumer report capture aggregate refused".into());
                        }
                        Ok(StoredReport::rendered(text, execution.report.records.len()))
                    }
                    Err(rejected) => {
                        let fault = match rejected.fault() {
                            adapter::ConsumerEncodingFault::Limit => {
                                super::super::decode::DecodeError::SavedBytes
                            }
                            adapter::ConsumerEncodingFault::WorkLimit => {
                                super::super::decode::DecodeError::Work(
                                    super::super::decode::OperandResource::ByteVisits,
                                )
                            }
                            _ => super::super::decode::DecodeError::Shape(
                                "selected consumer report encoding",
                            ),
                        };
                        execution.attempt.fail(RunFault::Decode(fault));
                        // Both owners are still alive, including Outcome/tree,
                        // cached literals and the spent failed writer backing.
                        drop((execution, rejected));
                        Err("consumer report encoding refused".into())
                    }
                }
            } else {
                render(execution)
            }
        },
    )
}
