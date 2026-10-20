//! Actual installed process/host effects for the SAME shared MCK invocation.
mod association;
mod fixture;
mod processes;
mod snapshots;

use super::{
    installed_observation::InstalledHostObservation,
    model_originals::{
        PendingCaptureCleanup,
        observation::{HostObservationLimits, HostSourceObservationScope, WorkerObservationLimits},
    },
    native_mck::measurements::{self, SnapshotPhase},
    native_startup::{PreparedNativeUi, prepare_native_ui_observed},
    server::BoundUiHost,
};
use crate::commands::{
    mck::workbench::installed_launch::InstalledLaunch, out_context::OutOverrides,
};
use cap_std::fs::Dir;
use morphir_common::config::observation::ReadLimits;
use morphir_devkit::ConfigLoadOptions;
use morphir_mck::{
    transport::Limits,
    workbench::model_originals::installed::{
        InstalledAdapterError, InstalledClientAction, InstalledClientAdapter,
        InstalledClientMeasurements, InstalledClientRun, InstalledSnapshot,
        RunningInstalledProcess, data,
    },
};
use std::{
    ffi::OsStr,
    sync::{
        Arc,
        atomic::{AtomicBool, Ordering},
    },
};
use tokio::time::Instant;

pub(in crate::commands) struct InstalledWorkbenchAdapter {
    launch: InstalledLaunch,
    limits: Limits,
    interrupted: Arc<AtomicBool>,
}
impl InstalledWorkbenchAdapter {
    pub(in crate::commands) fn new(
        launch: InstalledLaunch,
        limits: Limits,
        interrupted: Arc<AtomicBool>,
    ) -> Self {
        Self {
            launch,
            limits,
            interrupted,
        }
    }
}
impl InstalledClientAdapter for InstalledWorkbenchAdapter {
    fn observe(
        &mut self,
        run: InstalledClientRun<'_>,
    ) -> Result<InstalledClientMeasurements, InstalledAdapterError> {
        let runtime = tokio::runtime::Handle::try_current().map_err(incomplete)?;
        runtime.block_on(observe(
            run,
            &self.launch,
            self.limits,
            self.interrupted.clone(),
        ))
    }
}
fn incomplete<T>(_: T) -> InstalledAdapterError {
    InstalledAdapterError::ObservationIncomplete
}
fn check(end: Instant, interrupted: &AtomicBool) -> Result<(), InstalledAdapterError> {
    if interrupted.load(Ordering::Acquire) {
        return Err(InstalledAdapterError::Cancelled);
    }
    if Instant::now() >= end {
        return Err(InstalledAdapterError::ObservationIncomplete);
    }
    Ok(())
}
fn end(limits: Limits) -> Result<Instant, InstalledAdapterError> {
    Instant::now()
        .checked_add(limits.session_timeout)
        .ok_or(InstalledAdapterError::ObservationIncomplete)
}

struct RunningHost {
    scope: HostSourceObservationScope,
    _startup: PreparedNativeUi,
    events: InstalledHostObservation,
    launch_url: String,
    listener: Option<tokio::task::JoinHandle<Result<(), crate::error::CliError>>>,
    cleanup: PendingCaptureCleanup,
    socket_cleanup: super::socket_tasks::SocketCleanup,
}
impl RunningHost {
    async fn start(
        run: &mut InstalledClientRun<'_>,
        fixture: &fixture::Fixture,
        end: Instant,
        interrupted: &AtomicBool,
    ) -> Result<Self, InstalledAdapterError> {
        check(end, interrupted)?;
        let held = Dir::open_ambient_dir(&fixture.root, cap_std::ambient_authority())
            .map_err(incomplete)?;
        let limits = run.observation_limits();
        let scope = HostSourceObservationScope::bind_native_ui(
            &held,
            &fixture.root,
            ReadLimits::new(
                limits.source_attempts(),
                limits.source_read_calls(),
                limits.source_returned_bytes(),
                limits.source_files(),
            )
            .map_err(incomplete)?,
            WorkerObservationLimits::new(limits.worker_attempts(), limits.worker_updates())
                .map_err(incomplete)?,
            HostObservationLimits::new(limits.host_updates()).map_err(incomplete)?,
        )
        .map_err(incomplete)?;
        // The canonical outside-callback guard owns revocation. Issue against
        // this actual scope BEFORE DEFAULT discovery, auth, bind or spawn.
        let token = run
            .issue_host_observation(scope.invocation_projection())
            .map_err(incomplete)?;
        let session = uuid::Uuid::new_v4().to_string();
        let startup = prepare_native_ui_observed(
            held,
            &fixture.root,
            &session,
            crate::home::MorphirHome::resolve().map_err(incomplete)?,
            ConfigLoadOptions::default(),
            OutOverrides::from_process(None),
            &scope,
        )
        .map_err(incomplete)?;
        check(end, interrupted)?;
        let (mut host, events) = tokio::time::timeout_at(
            end,
            BoundUiHost::bind_installed_observed(
                session,
                startup.capabilities(),
                Some(startup.originals_provider()),
                &scope,
                token,
            ),
        )
        .await
        .map_err(incomplete)?
        .map_err(incomplete)?;
        let cleanup = host
            .take_capture_cleanup()
            .map_err(incomplete)?
            .into_pending();
        let socket_cleanup = host
            .take_socket_cleanup()
            .ok_or(InstalledAdapterError::ObservationIncomplete)?;
        let launch_url = host.launch_url();
        Ok(Self {
            scope,
            _startup: startup,
            events,
            launch_url,
            listener: Some(tokio::spawn(host.serve())),
            cleanup,
            socket_cleanup: super::socket_tasks::SocketCleanup::Pending(socket_cleanup),
        })
    }
    async fn stop(&mut self, end: Instant) -> Result<(), InstalledAdapterError> {
        self.socket_cleanup.stop_accepting_upgrades();
        self.events.close();
        let listener_result = if let Some(listener) = self.listener.as_mut() {
            listener.abort();
            match tokio::time::timeout_at(end, listener).await {
                Err(_) => Err(InstalledAdapterError::ObservationIncomplete),
                Ok(result) => {
                    // Retire every terminal handle. Only deadline retains it.
                    self.listener = None;
                    match result {
                        Ok(Ok(())) => Ok(()),
                        Err(error) if error.is_cancelled() => Ok(()),
                        Ok(Err(_)) | Err(_) => Err(InstalledAdapterError::ObservationIncomplete),
                    }
                }
            }
        } else {
            Ok(())
        };
        let socket_result = match self.socket_cleanup.drain(end).await {
            super::socket_tasks::SocketDrainOutcome::Joined => Ok(()),
            _ => Err(InstalledAdapterError::ObservationIncomplete),
        };
        // Attempt genuine capture drain even after listener/socket error/deadline.
        let capture_result = self.cleanup.drain_retained(end).await.map_err(incomplete);
        listener_result.and(socket_result).and(capture_result)
    }
}
impl Drop for RunningHost {
    fn drop(&mut self) {
        self.socket_cleanup.stop_accepting_upgrades();
        self.events.close();
        if let Some(listener) = self.listener.as_ref() {
            listener.abort();
        }
        // No detached reaper. If bounded explicit cleanup failed, owner Drop
        // remains abandonment and no joined/source-complete DATA is emitted.
    }
}

async fn observe(
    mut run: InstalledClientRun<'_>,
    launch: &InstalledLaunch,
    limits: Limits,
    interrupted: Arc<AtomicBool>,
) -> Result<InstalledClientMeasurements, InstalledAdapterError> {
    let end = end(limits)?;
    check(end, &interrupted)?;
    let fixture = fixture::Fixture::materialize(&mut run, end, &interrupted)?;
    // Stack array metadata is fixed. Every owned OS operand is paid by SAME
    // run before allocation; child env only, never process-global mutation.
    let environment = [
        (
            run.copy_command_operand(OsStr::new("TMPDIR"))?,
            run.copy_command_operand(fixture.scratch.as_os_str())?,
        ),
        (
            run.copy_command_operand(OsStr::new("TMP"))?,
            run.copy_command_operand(fixture.scratch.as_os_str())?,
        ),
        (
            run.copy_command_operand(OsStr::new("TEMP"))?,
            run.copy_command_operand(fixture.scratch.as_os_str())?,
        ),
    ];
    let mut host = None;
    let mut pending: Option<RunningInstalledProcess> = None;
    let mut implementation = None;
    let result = async {
        for (index, action) in run.actions().enumerate() {
            check(end, &interrupted)?;
            match action {
                InstalledClientAction::PrepareFixture if index == 0 => {}
                InstalledClientAction::StartObservedHost if index == 1 => {
                    host = Some(RunningHost::start(&mut run, &fixture, end, &interrupted).await?);
                    let active = host
                        .as_mut()
                        .ok_or(InstalledAdapterError::ObservationIncomplete)?;
                    // Store the live owner before either fallible retention
                    // or write, so the ordinary error path attempts cleanup.
                    let launch_text =
                        run.observation_text::<1, { usize::MAX }>(&active.launch_url)?;
                    fixture::Fixture::write_private(
                        fixture.paths.launch_file(),
                        launch_text.as_str().as_bytes(),
                    )?;
                    implementation = Some(
                        association::observe(
                            launch,
                            &fixture.paths,
                            &mut run,
                            &mut active.events,
                            limits,
                            end,
                            interrupted.clone(),
                        )
                        .await?,
                    );
                }
                InstalledClientAction::Run { .. } => {
                    let active = host
                        .as_mut()
                        .ok_or(InstalledAdapterError::ObservationIncomplete)?;
                    let command_end = end.min(
                        Instant::now()
                            .checked_add(limits.request_timeout)
                            .ok_or(InstalledAdapterError::ObservationIncomplete)?,
                    );
                    check(command_end, &interrupted)?;
                    pending = Some(launch.spawn(
                        index,
                        action,
                        &fixture.paths,
                        &mut run,
                        &fixture.base,
                        &environment,
                        limits,
                    )?);
                    let finished = processes::execute(
                        &mut run,
                        &mut active.events,
                        &mut pending,
                        command_end,
                        &interrupted,
                    )
                    .await?;
                    run.record_finished_process(finished)?;
                    if index == 8 {
                        snapshots::census(
                            &mut run,
                            InstalledSnapshot::Destination,
                            fixture.paths.destination(),
                            &fixture.destination_directory,
                            end,
                            &interrupted,
                        )?;
                        snapshots::census(
                            &mut run,
                            InstalledSnapshot::Scratch,
                            &fixture.scratch,
                            &fixture.scratch_directory,
                            end,
                            &interrupted,
                        )?;
                    }
                }
                InstalledClientAction::WriteSourceSelection => {
                    let body = run.source_selection_json()?;
                    fixture::Fixture::write_private(
                        fixture.paths.source_file(),
                        body.as_str().as_bytes(),
                    )?;
                }
                InstalledClientAction::WriteProjectSelection => {
                    let body = run.project_selection_json()?;
                    fixture::Fixture::write_private(
                        fixture.paths.project_file(),
                        body.as_str().as_bytes(),
                    )?;
                }
                InstalledClientAction::StopAndJoin => {
                    host.as_mut()
                        .ok_or(InstalledAdapterError::ObservationIncomplete)?
                        .stop(end)
                        .await?;
                }
                InstalledClientAction::Checkpoint { .. } => {
                    // Source cursor only. No invented UI checkpoint, commit,
                    // release acceptance or upgraded socket-task join event.
                }
                _ => return Err(InstalledAdapterError::ObservationIncomplete),
            }
        }
        Ok::<(), InstalledAdapterError>(())
    }
    .await;
    if let Err(error) = result {
        let cleanup_end = Instant::now()
            .checked_add(limits.session_timeout)
            .unwrap_or(end);
        if let Some(active) = host.as_mut() {
            active.events.close();
        }
        let _process_cleanup = processes::terminate(&mut pending, cleanup_end).await;
        let _host_cleanup = match host.as_mut() {
            Some(active) => active.stop(cleanup_end).await,
            None => Ok(()),
        };
        // Cleanup failure remains incomplete, but cannot replace the earlier
        // actual action failure, including observed cancellation.
        return Err(error);
    }
    let host = host
        .as_ref()
        .ok_or(InstalledAdapterError::ObservationIncomplete)?;
    let snapshot = host.scope.snapshot();
    let source = data::SourceMeasurements::OpenPrefix {
        counts: measurements::prefix(snapshot.reads()),
    };
    let workers =
        measurements::workers(snapshot.workers(), SnapshotPhase::Open).map_err(incomplete)?;
    let published = run.copy_published_path()?;
    let reported = std::path::Path::new(published.as_str());
    if reported.as_os_str().is_empty() {
        return Err(InstalledAdapterError::ObservationIncomplete);
    }
    let resolved;
    let absolute = if reported.is_absolute() {
        // This path only binds already observed stdout to an independently
        // held census. It never supplies a filesystem read/open authority.
        if reported.components().any(|c| {
            matches!(
                c,
                std::path::Component::ParentDir | std::path::Component::CurDir
            )
        }) {
            return Err(InstalledAdapterError::ObservationIncomplete);
        }
        reported
    } else {
        // Pinned CLI returns its confined relative destination. Join actual
        // Normal components against SAME held canonical requested cwd.
        if reported
            .components()
            .any(|c| !matches!(c, std::path::Component::Normal(_)))
        {
            return Err(InstalledAdapterError::ObservationIncomplete);
        }
        resolved = run.command_path(&fixture.base, published.as_str())?;
        resolved.as_path()
    };
    let relative = absolute
        .strip_prefix(fixture.paths.destination())
        .map_err(incomplete)?;
    if relative.as_os_str().is_empty() {
        return Err(InstalledAdapterError::ObservationIncomplete);
    }
    let relative = snapshots::portable_relative(&mut run, relative)?;
    run.finish_measurements(
        implementation.ok_or(InstalledAdapterError::ObservationIncomplete)?,
        &relative,
        source,
        workers,
    )
}
