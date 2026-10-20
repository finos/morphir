//! Native effects for the shared MCK engine. The engine remains the checker.
mod client;
mod completion;
mod fixture;
mod measurements;
mod product;

use std::{
    collections::BTreeMap,
    path::Path,
    sync::{Arc, atomic::AtomicBool},
};

use cap_std::fs::Dir;
use morphir_common::config::observation::ReadLimits;
use morphir_devkit::ConfigLoadOptions;
use morphir_mck::{
    transport::Limits,
    workbench::model_originals::native::{
        CaptureScope, NativeAdapterError, NativeAuthentication, NativeOriginalAction,
        NativeOriginalAdapter, NativeOriginalMeasurements, NativeOriginalRun, NativeReadTarget,
        SemanticRequest, data,
    },
};
use serde_json::json;

use super::{
    model_originals::{
        CaptureId,
        observation::{
            HostObservationLimits, HostSourceObservationScope, HostSourceSnapshot,
            WorkerObservationLimits,
        },
    },
    native_startup::PreparedNativeUi,
    prepare_native_ui_observed,
    provider::WorkspaceCapability as _,
    server::BoundUiHost,
};
use client::{Deadline, RunningHost};
use completion::reconcile_completion;
use measurements::{SnapshotPhase, Witnesses, alias, data_error, text};
use product::{
    CaptureBinding, CompletedCapture, DiscoveredProject, Discovery, ReadyCapture, RecordOwnership,
    State,
};

pub(in crate::commands) struct NativeWorkbenchAdapter {
    limits: Limits,
    interrupted: Arc<AtomicBool>,
}
impl NativeWorkbenchAdapter {
    /// Construction performs no filesystem, host or transport effects.
    pub(in crate::commands) fn new(limits: Limits, interrupted: Arc<AtomicBool>) -> Self {
        Self {
            limits,
            interrupted,
        }
    }
}
impl NativeOriginalAdapter for NativeWorkbenchAdapter {
    fn observe(
        &mut self,
        run: NativeOriginalRun<'_>,
    ) -> Result<NativeOriginalMeasurements, NativeAdapterError> {
        // The command calls the synchronous engine inside block_in_place.
        // Reuse that actual runtime, never a second synthetic service worker.
        let runtime =
            tokio::runtime::Handle::try_current().map_err(|_| NativeAdapterError::Startup)?;
        runtime.block_on(observe(run, self.limits, self.interrupted.clone()))
    }
}
#[derive(Clone, Copy)]
enum CaptureWork {
    NotRequested,
    Requested,
}

async fn observe(
    mut run: NativeOriginalRun<'_>,
    limits: Limits,
    interrupted: Arc<AtomicBool>,
) -> Result<NativeOriginalMeasurements, NativeAdapterError> {
    let deadline = Deadline::new(limits, interrupted)?;
    deadline.check()?;
    let fixture = fixture::Fixture::materialize(&mut run, || deadline.check())?;
    deadline.check()?;
    let held = Dir::open_ambient_dir(&fixture.root, cap_std::ambient_authority())
        .map_err(|_| NativeAdapterError::Startup)?;
    let policy = run.observation_limits();
    let scope = HostSourceObservationScope::bind_native_ui(
        &held,
        &fixture.root,
        ReadLimits::new(
            policy.source_attempts(),
            policy.source_read_calls(),
            policy.source_returned_bytes(),
            policy.source_files(),
        )
        .map_err(|_| NativeAdapterError::Startup)?,
        WorkerObservationLimits::new(policy.worker_attempts(), policy.worker_updates())
            .map_err(|_| NativeAdapterError::Startup)?,
        HostObservationLimits::new(policy.host_updates())
            .map_err(|_| NativeAdapterError::Startup)?,
    )
    .map_err(|_| NativeAdapterError::Startup)?;
    let witnesses = run.source().witnesses();
    let register = |path: &str| -> Result<_, NativeAdapterError> {
        Ok((
            path.to_owned(),
            scope
                .source_scope()
                .register_file(&held, Path::new(path))
                .map_err(|_| NativeAdapterError::Startup)?,
        ))
    };
    let files = Witnesses {
        record: register(witnesses.compile_record())?,
        primary: register(witnesses.original_primary())?,
        sentinel: register(witnesses.undeclared_sentinel())?,
    };
    let session = uuid::Uuid::new_v4().to_string();
    let home = crate::home::MorphirHome::resolve().map_err(|_| NativeAdapterError::Startup)?;
    let prepared = prepare_native_ui_observed(
        held,
        &fixture.root,
        &session,
        home,
        ConfigLoadOptions::default(),
        fixture.output.clone(),
        &scope,
    )
    .map_err(|_| NativeAdapterError::Startup)?;
    deadline.check()?;
    let sources = prepared.workspace_provider().initial_sources();
    let source = sources.first().ok_or(NativeAdapterError::Discovery)?;
    if sources.len() != 1 {
        return Err(NativeAdapterError::UnsupportedAction);
    }
    let source_wire = json!({"providerId":source.provider_id,"locator":source.locator});
    let (host, records) = deadline
        .exchange(async {
            BoundUiHost::bind_record_observed(
                session.clone(),
                prepared.capabilities(),
                Some(prepared.originals_provider()),
                &scope,
            )
            .await
            .map_err(|_| NativeAdapterError::Startup)
        })
        .await?;
    let usage = host.model_originals_observer();
    // This alias labels this genuine bound registration for comparison DATA;
    // it grants neither a provider nor permission to select another host.
    let registration = alias(&format!("registration-{}", uuid::Uuid::new_v4()))?;
    let mut host = RunningHost::start(host)?;
    let mut prepared = Some(prepared);
    let mut scope = Some(scope);
    let mut state = State::Unconnected;
    let mut capture_work = CaptureWork::NotRequested;
    let mut shutdown = ShutdownDeadline::NotStarted;
    let mut transcript = Vec::new();
    let mut checkpoints = Vec::new();
    let mut entries = BTreeMap::new();
    let mut disposed_transports = 0;

    let result:Result<State,NativeAdapterError> = async {
        for action in run.actions() {
            deadline.check()?;
            state = match (action,state) {
                (NativeOriginalAction::Connect {authentication,connection},State::Unconnected) => {
                    if authentication!=NativeAuthentication::Valid { return Err(NativeAdapterError::UnsupportedAction); }
                    host.connect(&deadline).await?;
                    let (initialized,_) = host.request(&deadline,u64::MAX,"morphir.session.initialize",
                        json!({"protocolVersion":1,"sessionId":session})).await?;
                    if initialized["result"]["protocolVersion"]!=1 { return Err(NativeAdapterError::Authentication); }
                    State::Connected {connection:connection.clone()}
                }
                (NativeOriginalAction::Discover {connection,provider},State::Connected {connection:actual}) => {
                    require_alias(&actual,connection)?;
                    let fixture=run.fixture();
                    let declared=fixture.providers().find(|p|p.alias()==provider).ok_or(NativeAdapterError::Selection)?;
                    if declared.locator()!=source.locator { return Err(NativeAdapterError::Selection); }
                    let (opened,_)=host.request(&deadline,u64::MAX-1,"morphir.workspace.open",json!({"source":source})).await?;
                    let projects=opened["result"]["snapshot"]["projects"].as_array().ok_or(NativeAdapterError::Discovery)?
                        .iter().map(DiscoveredProject::from_reply).collect::<Result<Vec<_>,_>>()?;
                    State::Discovered(Discovery {connection:actual,provider:provider.clone(),projects})
                }
                (NativeOriginalAction::CaptureSelected {capture,connection,project,provider,request_id,scope:requested_scope,semantic,..},
                    State::Discovered(discovered)) => {
                    require_alias(&discovered.connection,connection)?; require_alias(&discovered.provider,provider)?;
                    if semantic!=SemanticRequest::None { return Err(NativeAdapterError::UnsupportedAction); }
                    let fixture=run.fixture();
                    let declared=fixture.providers().find(|p|p.alias()==provider).ok_or(NativeAdapterError::Selection)?;
                    let declared_project=declared.projects().find(|p|p.alias()==project).ok_or(NativeAdapterError::Selection)?;
                    let actual=discovered.projects.into_iter().find(|p|p.module==declared_project.module()).ok_or(NativeAdapterError::Selection)?;
                    capture_work=CaptureWork::Requested;
                    let (reply,frames)=host.request(&deadline,request_id,"morphir.model-originals.capture",json!({
                        "contractVersion":"0.1.0-draft.1","source":source_wire,"projectId":actual.id.as_str(),
                        "scope":match requested_scope {CaptureScope::Primary=>"primary",CaptureScope::Complete=>"complete"},"semantic":"none",
                    })).await?;
                    let ready=&reply["result"];
                    let evidence=measurements::capture(ready,capture)?;
                    let id=CaptureId::parse(text(ready,"captureId")?).map_err(|_|NativeAdapterError::Exchange)?;
                    let observer=records.for_capture(&id).map_err(|_|NativeAdapterError::ObservationIncomplete)?;
                    let actual_binding=&ready["binding"];
                    if text(actual_binding,"sessionId")?!=session
                        || actual_binding["source"]!=source_wire || text(actual_binding,"projectId")?!=actual.id.as_str() {
                        return Err(NativeAdapterError::Selection);
                    }
                    let binding=CaptureBinding {
                        connection:discovered.connection, provider:discovered.provider, project:project.clone(),
                        registration:registration.clone(), capture:capture.clone(),id,
                        session:data::SessionId::new(text(actual_binding,"sessionId")?).map_err(|_|NativeAdapterError::Selection)?,
                        source:data::SourceIdentity {
                            provider:data::ProviderId::new(text(&actual_binding["source"],"providerId")?).map_err(|_|NativeAdapterError::Selection)?,
                            locator:data::SourceLocator::new(text(&actual_binding["source"],"locator")?).map_err(|_|NativeAdapterError::Selection)?,
                        },
                        project_id:actual.id,
                    };
                    // The actual worker already hashed its frozen record.
                    // Independent checking verifies that receipt against the
                    // adopted bytes; no precharge-bypassing observer scan.
                    let record=RecordOwnership::InHost {
                        observer,digest:measurements::digest(text(&ready["origin"]["record"],"sha256")?)?,
                        declaration:product::declaration(ready)?,
                    };
                    transcript.push(frames);
                    State::Ready(ReadyCapture {binding,evidence,record})
                }
                (NativeOriginalAction::Checkpoint {name},current) => {
                    let open;
                    let (snapshot,phase)=match &current {
                        State::Closed {snapshot,..}=>(snapshot.as_ref(),SnapshotPhase::Sealed),
                        _=>{
                            open=scope.as_ref().ok_or(NativeAdapterError::Cleanup)?.snapshot();
                            (&open,SnapshotPhase::Open)
                        }
                    };
                    let binding=current.binding()?;
                    checkpoints.push(data::NativeCheckpoint {
                        name:name.clone(),connection:binding.connection.clone(),
                        offer:data::OfferEvidence::Held {provider:binding.provider.clone(),registration:binding.registration.clone()},
                        state:current.measured_state()?,
                        resources:measurements::resources(usage.usage(),current.retained_record_bytes()?)?,
                        source:files.source(snapshot,phase)?,workers:measurements::workers(snapshot.workers(),phase)?,
                        entries:measurements::entries(snapshot),
                    });
                    current.adopt(&mut run)?
                }
                (NativeOriginalAction::Inventory {capture,connection,request_id,start_index,max_entries},State::Ready(current)) => {
                    require_capture(&current.binding,capture,connection)?;
                    let (reply,frames)=host.request(&deadline,request_id,"morphir.model-originals.inventory",json!({
                        "contractVersion":"0.1.0-draft.1","captureId":current.binding.id.as_str(),"startIndex":start_index,"maxEntries":max_entries,
                    })).await?;
                    for entry in reply["result"]["entries"].as_array().ok_or(NativeAdapterError::Exchange)? {
                        if entry["kind"]=="file" {entries.insert(text(entry,"path")?.to_owned(),text(entry,"entryId")?.to_owned());}
                    }
                    transcript.push(frames);
                    State::Ready(current)
                }
                (NativeOriginalAction::ReadSelected {capture,connection,request_id,target,offset,max_bytes},State::Ready(current)) => {
                    require_capture(&current.binding,capture,connection)?;
                    let NativeReadTarget::OriginalEntry {path}=target else {return Err(NativeAdapterError::UnsupportedAction);};
                    let entry=entries.get(path.as_str()).ok_or(NativeAdapterError::Selection)?;
                    let (reply,frames)=host.request(&deadline,request_id,"morphir.model-originals.read",json!({
                        "contractVersion":"0.1.0-draft.1","captureId":current.binding.id.as_str(),
                        "target":{"kind":"original","entryId":entry},"offset":offset,"maxBytes":max_bytes,
                    })).await?;
                    if !reply["result"]["content"].is_string() {return Err(NativeAdapterError::Exchange);}
                    transcript.push(frames);
                    State::Ready(current)
                }
                (NativeOriginalAction::Release {capture,connection,request_id},State::Ready(current)) => {
                    require_capture(&current.binding,capture,connection)?;
                    let (observer,record)=current.record.complete()?;
                    let (reply,frames)=host.request(&deadline,request_id,"morphir.model-originals.release",json!({
                        "contractVersion":"0.1.0-draft.1","captureId":current.binding.id.as_str(),
                    })).await?;
                    if reply["result"]["status"]!="released" {return Err(NativeAdapterError::Exchange);}
                    transcript.push(frames);
                    State::Released(CompletedCapture {binding:current.binding,evidence:current.evidence,observer,record})
                }
                (NativeOriginalAction::Disconnect {connection},State::Released(capture)) => {
                    require_alias(&capture.binding.connection,connection)?;
                    let snapshot=cleanup(&mut host,&mut prepared,&mut scope,limits.shutdown_grace,&mut shutdown,capture_work).await?;
                    disposed_transports+=1;
                    State::Closed {capture,snapshot:Box::new(snapshot)}
                }
                (NativeOriginalAction::Unsupported(_),_) => return Err(NativeAdapterError::UnsupportedAction),
                _=>return Err(NativeAdapterError::Selection),
            };
        }
        Ok(state)
    }.await;
    // All business exits, including cancellation, pass through real cleanup.
    let cleanup_result = if scope.is_some() {
        cleanup(
            &mut host,
            &mut prepared,
            &mut scope,
            limits.shutdown_grace,
            &mut shutdown,
            capture_work,
        )
        .await
        .map(|_| ())
    } else {
        Ok(())
    };
    let State::Closed { capture, snapshot } = reconcile_completion(result, cleanup_result)? else {
        return Err(NativeAdapterError::Cleanup);
    };
    snapshot
        .require_source_complete()
        .map_err(|_| NativeAdapterError::ObservationIncomplete)?;
    let workers = snapshot.workers();
    workers
        .require_joined_cleanup()
        .map_err(|_| NativeAdapterError::Cleanup)?;
    let final_checkpoint = checkpoints
        .last()
        .ok_or(NativeAdapterError::ObservationIncomplete)?
        .name
        .clone();
    Ok(NativeOriginalMeasurements {
        profile: data::MeasurementProfile,
        contract_version: data::MeasurementVersion::current().map_err(data_error)?,
        role: data::OriginalRole,
        resolved_selection: capture.binding.selection()?,
        transcript: data::MeasuredTranscript {
            exchanges: data::Items::new(transcript).map_err(data_error)?,
        },
        captures: data::Items::new(vec![capture.evidence]).map_err(data_error)?,
        private_record: capture.record,
        checkpoints: data::Items::new(checkpoints).map_err(data_error)?,
        outcome: data::ScenarioOutcome::Clean { final_checkpoint },
        teardown: data::HarnessTeardown::Confirmed {
            disposed_transports: data::Natural::new(disposed_transports).map_err(data_error)?,
            held_core_results: data::HarnessTeardownConfirmedHeldCoreResults,
            pending_effects: data::HarnessTeardownConfirmedPendingEffects,
            product_release_inferred: data::HarnessTeardownConfirmedProductReleaseInferred,
            still_owned_workers: data::HarnessTeardownConfirmedStillOwnedWorkers,
            workers_exited: data::Natural::new(
                workers.joined_ok() + workers.joined_panicked() + workers.joined_cancelled(),
            )
            .map_err(data_error)?,
            workers_started: data::Natural::new(workers.started()).map_err(data_error)?,
        },
    })
}
fn require_alias(
    actual: &data::FixtureAlias,
    expected: &data::FixtureAlias,
) -> Result<(), NativeAdapterError> {
    if actual == expected {
        Ok(())
    } else {
        Err(NativeAdapterError::Selection)
    }
}
fn require_capture(
    binding: &CaptureBinding,
    capture: &data::FixtureAlias,
    connection: &data::FixtureAlias,
) -> Result<(), NativeAdapterError> {
    require_alias(&binding.connection, connection)?;
    require_alias(&binding.capture, capture)
}
async fn cleanup(
    host: &mut RunningHost,
    prepared: &mut Option<PreparedNativeUi>,
    scope: &mut Option<HostSourceObservationScope>,
    grace: std::time::Duration,
    shutdown: &mut ShutdownDeadline,
    capture_work: CaptureWork,
) -> Result<HostSourceSnapshot, NativeAdapterError> {
    // Interruption ends business work, not cleanup. Genuine join ownership and
    // eventual Arc recovery, rather than counters alone, establish completion.
    let end = shutdown.begin(grace)?;
    // Drain genuine cancellation/join ownership before trying to prove worker
    // completion or recover source writers. Error keeps the same owner/scope.
    host.stop(end).await?;
    drop(prepared.take());
    let mut owner = scope.take().ok_or(NativeAdapterError::Cleanup)?;
    loop {
        match owner.try_seal() {
            Ok(snapshot) => {
                if matches!(capture_work, CaptureWork::Requested) {
                    snapshot
                        .workers()
                        .require_joined_cleanup()
                        .map_err(|_| NativeAdapterError::Cleanup)?;
                }
                return Ok(snapshot);
            }
            Err(pending) => {
                owner = pending.into_scope();
                if tokio::time::Instant::now() >= end {
                    *scope = Some(owner);
                    return Err(NativeAdapterError::Cleanup);
                }
                retry_ownership(end).await;
            }
        }
    }
}

enum ShutdownDeadline {
    NotStarted,
    Started(tokio::time::Instant),
}
impl ShutdownDeadline {
    fn begin(
        &mut self,
        grace: std::time::Duration,
    ) -> Result<tokio::time::Instant, NativeAdapterError> {
        match self {
            Self::Started(end) => Ok(*end),
            Self::NotStarted => {
                let end = tokio::time::Instant::now()
                    .checked_add(grace)
                    .ok_or(NativeAdapterError::Cleanup)?;
                *self = Self::Started(end);
                Ok(end)
            }
        }
    }
}

async fn retry_ownership(end: tokio::time::Instant) {
    // Existing owners expose synchronous snapshots/seal attempts, not an event
    // receiver. A timer avoids spinning while preserving the caller's deadline.
    let remaining = end.saturating_duration_since(tokio::time::Instant::now());
    tokio::time::sleep(remaining.min(std::time::Duration::from_millis(10))).await;
}
