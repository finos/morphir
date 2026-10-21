//! Actual installed process/host effects for the SAME shared MCK invocation.
mod association;
mod fixture;
mod processes;
mod snapshots;
mod source_witnesses;

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
    mck::workbench::installed_launch::{InstalledInvocationSettings, InstalledLaunch},
    out_context::OutOverrides,
};
use cap_std::fs::Dir;
use morphir_common::config::observation::ReadLimits;
use morphir_devkit::ConfigLoadOptions;
use morphir_mck::{
    transport::Limits,
    workbench::ConsumerObservationSelection,
    workbench::model_originals::installed::{
        InstalledAdapterError, InstalledClientAction, InstalledClientAdapter,
        InstalledClientMeasurements, InstalledClientRun, InstalledSnapshot, data,
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
    controls: TestControls,
}
#[derive(Default)]
struct TestControls {
    #[cfg(test)]
    cutoff: Option<TestConsumerAckCutoff>,
    #[cfg(test)]
    cuts: usize,
    #[cfg(test)]
    usage: Option<TestConsumerTerminalUsage>,
}
#[cfg(test)]
#[derive(Clone, Copy)]
pub(in crate::commands) enum TestConsumerAckCutoff {
    Release,
    Commit,
}
#[cfg(test)]
#[derive(Clone, Copy)]
pub(in crate::commands) struct TestConsumerTerminalUsage {
    pub(in crate::commands) receiving_before:
        morphir_mck::workbench::model_originals::installed::InstalledObservationUsage,
    pub(in crate::commands) receiving_after:
        morphir_mck::workbench::model_originals::installed::InstalledObservationUsage,
    pub(in crate::commands) decoder_before: [usize; 4],
    pub(in crate::commands) decoder_after: [usize; 4],
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
            controls: TestControls::default(),
        }
    }
    #[cfg(test)]
    pub(in crate::commands) fn test_with_consumer_ack_cutoff(
        mut self,
        cutoff: TestConsumerAckCutoff,
    ) -> Self {
        self.controls.cutoff = Some(cutoff);
        self
    }
    #[cfg(test)]
    pub(in crate::commands) fn test_consumer_ack_cut_count(&self) -> usize {
        self.controls.cuts
    }
    #[cfg(test)]
    pub(in crate::commands) fn test_consumer_terminal_usage(
        &self,
    ) -> Option<TestConsumerTerminalUsage> {
        self.controls.usage
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
            &mut self.controls,
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

struct RunningHost<'source> {
    // Raw containment/destruction runs before the final source owner drops.
    runtime: RunningHostRuntime,
    witnesses: source_witnesses::Witnesses<'source>,
    scope: HostSourceObservationScope,
}
struct RunningHostRuntime {
    _startup: PreparedNativeUi,
    events: InstalledHostObservation,
    launch_url: String,
    listener: Option<tokio::task::JoinHandle<Result<(), crate::error::CliError>>>,
    cleanup: PendingCaptureCleanup,
    socket_cleanup: super::socket_tasks::SocketCleanup,
}
impl<'source> RunningHost<'source> {
    async fn start(
        run: &mut InstalledClientRun<'source>,
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
        let witnesses = source_witnesses::Witnesses::register(run, &scope, &held)?;
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
            runtime: RunningHostRuntime {
                _startup: startup,
                events,
                launch_url,
                listener: Some(tokio::spawn(host.serve())),
                cleanup,
                socket_cleanup: super::socket_tasks::SocketCleanup::Pending(socket_cleanup),
            },
            witnesses,
            scope,
        })
    }
    async fn stop(&mut self, end: Instant) -> Result<(), InstalledAdapterError> {
        self.runtime.stop(end).await
    }
    async fn complete(
        &mut self,
        run: &mut InstalledClientRun<'_>,
        end: Instant,
    ) -> Result<(), InstalledAdapterError> {
        self.runtime.complete(run, end).await
    }
    #[cfg(test)]
    async fn stop_listener(&mut self, end: Instant) -> Result<(), InstalledAdapterError> {
        self.runtime.stop_listener(end).await
    }
    #[cfg(test)]
    fn into_source_scope(self) -> Result<HostSourceObservationScope, InstalledAdapterError> {
        self.into_source_parts().map(|(scope, _)| scope)
    }
    fn into_source_parts(
        self,
    ) -> Result<
        (
            HostSourceObservationScope,
            source_witnesses::Witnesses<'source>,
        ),
        InstalledAdapterError,
    > {
        let Self {
            runtime,
            scope,
            witnesses,
        } = self;
        let joined = runtime.listener.is_none()
            && matches!(
                runtime.socket_cleanup,
                super::socket_tasks::SocketCleanup::Joined
            )
            && runtime.cleanup.retained_handles() == 0;
        // Preserve raw containment order even when extraction is refused.
        drop(runtime);
        if joined {
            Ok((scope, witnesses))
        } else {
            Err(InstalledAdapterError::ObservationIncomplete)
        }
    }
}
impl RunningHostRuntime {
    async fn stop(&mut self, end: Instant) -> Result<(), InstalledAdapterError> {
        self.socket_cleanup.stop_accepting_upgrades();
        self.events.close();
        let listener_result = self.stop_listener(end).await;
        let socket_result = match self.socket_cleanup.drain(end).await {
            super::socket_tasks::SocketDrainOutcome::Joined => Ok(()),
            _ => Err(InstalledAdapterError::ObservationIncomplete),
        };
        // Attempt genuine capture drain even after listener/socket error/deadline.
        let capture_result = self.cleanup.drain_retained(end).await.map_err(incomplete);
        listener_result.and(socket_result).and(capture_result)
    }
    async fn stop_listener(&mut self, end: Instant) -> Result<(), InstalledAdapterError> {
        if let Some(listener) = self.listener.as_mut() {
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
        }
    }
    async fn complete(
        &mut self,
        run: &mut InstalledClientRun<'_>,
        end: Instant,
    ) -> Result<(), InstalledAdapterError> {
        self.socket_cleanup.stop_accepting_upgrades();
        let result = async {
            self.stop_listener(end).await?;
            loop {
                // Losing this borrowed wait restores the SAME checked-out
                // handles. Publishers stay live until their events are cached.
                tokio::select! {
                    outcome = self.socket_cleanup.wait_naturally(end) => {
                        match outcome {
                            super::socket_tasks::SocketDrainOutcome::Joined => break,
                            _ => return Err(InstalledAdapterError::ObservationIncomplete),
                        }
                    }
                    event = self.events.next() => {
                        event.ok_or(InstalledAdapterError::ObservationIncomplete)?
                            .collect(run).map_err(incomplete)?;
                    }
                }
            }
            self.events.close();
            self.cleanup.drain_retained(end).await.map_err(incomplete)
        }
        .await;
        if let Err(error) = result {
            // Real cleanup remains required after a producer/work/task fault.
            // The original failure wins; an expired end retains pending owners.
            let _cleanup = self.stop(end).await;
            return Err(error);
        }
        Ok(())
    }
}
impl Drop for RunningHostRuntime {
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
    _controls: &mut TestControls,
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
    let mut pending: Option<processes::Command> = None;
    let operation_mode = matches!(
        run.consumer_observation(),
        ConsumerObservationSelection::OperationPort(_)
    );
    let mut implementation = None;
    let result = async {
        for (index, action) in run.actions().enumerate() {
            check(end, &interrupted)?;
            match action {
                InstalledClientAction::PrepareFixture if index == 0 => {}
                InstalledClientAction::StartObservedHost if index == 1 => {
                    host = Some(RunningHost::start(&mut run, &fixture, end, &interrupted).await?);
                    if operation_mode {
                        // UI owns this already-created whole-run end. Bind it
                        // once on SAME active invocation, never a fresh window.
                        run.bind_consumer_window(end.into_std())?;
                    }
                    let active = host
                        .as_mut()
                        .ok_or(InstalledAdapterError::ObservationIncomplete)?;
                    // Store the live owner before either fallible retention
                    // or write, so the ordinary error path attempts cleanup.
                    let launch_text =
                        run.observation_text::<1, { usize::MAX }>(&active.runtime.launch_url)?;
                    fixture::Fixture::write_private(
                        fixture.paths.launch_file(),
                        launch_text.as_str().as_bytes(),
                    )?;
                    implementation = Some(
                        association::observe(
                            launch,
                            &fixture.paths,
                            &mut run,
                            &mut active.runtime.events,
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
                    let command_end = if operation_mode && index == 8 {
                        let (process, ports) = launch.spawn_observed_publish(
                            index,
                            &fixture.paths,
                            &mut run,
                            InstalledInvocationSettings::new(&fixture.base, &environment, limits),
                            implementation
                                .take()
                                .ok_or(InstalledAdapterError::ObservationIncomplete)?,
                            end.into_std(),
                        )?;
                        pending = Some(processes::Command::operation(process, ports));
                        #[cfg(test)]
                        if let Some(command) = pending.as_mut() {
                            command.configure_test_cutoff(_controls.cutoff);
                        }
                        end
                    } else {
                        pending = Some(processes::Command::Ordinary(Some(launch.spawn(
                            index,
                            action,
                            &fixture.paths,
                            &mut run,
                            InstalledInvocationSettings::new(&fixture.base, &environment, limits),
                        )?)));
                        command_end
                    };
                    pending
                        .as_mut()
                        .ok_or(InstalledAdapterError::ObservationIncomplete)?
                        .execute(
                            &mut run,
                            &mut active.runtime.events,
                            command_end,
                            &interrupted,
                        )
                        .await?;
                    let settled = pending
                        .take()
                        .ok_or(InstalledAdapterError::ObservationIncomplete)?;
                    #[cfg(test)]
                    let before = run.test_consumer_usage();
                    #[cfg(test)]
                    {
                        _controls.cuts += settled.test_cut_count();
                    }
                    if let Err(rejected) = settled.record_terminal(&mut run) {
                        pending = Some(rejected);
                        return Err(InstalledAdapterError::ObservationIncomplete);
                    }
                    #[cfg(test)]
                    {
                        let after = run.test_consumer_usage();
                        _controls.usage = Some(TestConsumerTerminalUsage {
                            receiving_before: before.receiving,
                            receiving_after: after.receiving,
                            decoder_before: before.decoder,
                            decoder_after: after.decoder,
                        });
                    }
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
                        .complete(&mut run, end)
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
        let cleanup_end = if operation_mode {
            end
        } else {
            Instant::now()
                .checked_add(limits.session_timeout)
                .unwrap_or(end)
        };
        if let Some(active) = host.as_mut() {
            active.runtime.events.close();
        }
        let _process_cleanup = match pending.as_mut() {
            Some(command) => command.terminate(cleanup_end).await,
            None => Ok(()),
        };
        // Export only an actual settled owner. A rejected pair stays together
        // for ordinary disposal; no raw Drop is relabeled as a record.
        if _process_cleanup.is_ok()
            && let Some(settled) = pending.take()
        {
            #[cfg(test)]
            let before = run.test_consumer_usage();
            #[cfg(test)]
            {
                _controls.cuts += settled.test_cut_count();
            }
            if let Err(rejected) = settled.record_terminal(&mut run) {
                pending = Some(rejected);
            }
            #[cfg(test)]
            {
                let after = run.test_consumer_usage();
                _controls.usage = Some(TestConsumerTerminalUsage {
                    receiving_before: before.receiving,
                    receiving_after: after.receiving,
                    decoder_before: before.decoder,
                    decoder_after: after.decoder,
                });
            }
        }
        let _host_cleanup = match host.as_mut() {
            Some(active) => active.stop(cleanup_end).await,
            None => Ok(()),
        };
        // The actual rejected ownerpair stays alive through host cleanup,
        // then is explicitly disposed at this unsuccessful public boundary.
        drop(pending);
        // Cleanup failure remains incomplete, but cannot replace the earlier
        // actual action failure, including observed cancellation.
        return Err(error);
    }
    let host = host
        .take()
        .ok_or(InstalledAdapterError::ObservationIncomplete)?;
    let (mut scope, witnesses) = host.into_source_parts()?;
    let snapshot = loop {
        match scope.try_seal() {
            Ok(snapshot) => break snapshot,
            Err(pending) => {
                scope = pending.into_scope();
                check(end, &interrupted)?;
                tokio::task::yield_now().await;
            }
        }
    };
    let source = witnesses.measurements(&mut run, &snapshot)?;
    let workers =
        measurements::workers(snapshot.workers(), SnapshotPhase::Sealed).map_err(incomplete)?;
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
    if operation_mode {
        return run.finish_consumer_measurements(&relative, source, workers);
    }
    run.finish_measurements(
        implementation.ok_or(InstalledAdapterError::ObservationIncomplete)?,
        &relative,
        source,
        workers,
    )
}

#[cfg(test)]
mod tail_tests;
