//! Maintained source0/source1 prefix in the canonical browser callback. The
//! returned facts and cleanup owners are owned; no run token escapes the cut.
use super::*;
use crate::commands::ui::server::controlled_originals::{
    ControlledHostFinish,
    ingress::{DocumentIngressLimits, DocumentSetupFault},
};
use morphir_mck::{
    transport::Limits,
    workbench::{
        BrowserConnectedControlFault, BrowserConnectedObservation, BrowserControllerFiles,
        BrowserControllerFinished, BrowserControllerLaunchFailure, BrowserControllerLaunchFinished,
        BrowserControllerLaunchStage, BrowserControllerPreparation,
        BrowserControllerPreparationFailure, BrowserControllerPreparationFinished,
        BrowserControllerPreparationStage, BrowserControllerRetirement, BrowserFixedController,
        BrowserInspectionPendingReply, BrowserMaterializedController, BrowserOpeningSelectionReply,
        BrowserRowProducer, BrowserUnlaunchedControllerFinished,
        BrowserUnpreparedControllerFinished, PreparedBrowserClientRun,
    },
};
use std::{mem::size_of, sync::atomic::AtomicBool, time::Duration};

pub(super) struct SelectedSourcePrefixInputs<'inputs, 'image> {
    pub(super) application: &'inputs RunObservedApplication,
    pub(super) manifest: &'inputs ApplicationManifest<'image>,
    pub(super) runtime_archive: &'inputs [u8],
    pub(super) files: BrowserControllerFiles<'inputs>,
    pub(super) transport: Limits,
    pub(super) document: DocumentIngressLimits,
    pub(super) original_end: Instant,
}
pub(super) struct SelectedSourcePrefixOutcome {
    fact: PrefixFact,
    observed: PrefixObserved,
    physical: SelectedPhysicalCleanup,
    pub(super) native: SelectedNativeCleanup,
}
/// Earlier observed replies remain DATA even if a later fault stops the run.
enum PrefixObserved {
    None,
    Opening(BrowserOpeningSelectionReply),
    OpeningAndInspection {
        opening: BrowserOpeningSelectionReply,
        inspection: BrowserInspectionPendingReply,
    },
}
enum PrefixFact {
    SetupRefused(SetupFault),
    SourceIssueRetained(SourceIssueStage),
    PreparationRefused(BrowserControllerPreparationStage),
    LaunchRefused(BrowserControllerLaunchStage),
    ListenerRefused {
        gate: Result<BrowserListenerDispatch, BrowserActionIssueError>,
        native: SelectedSourceListenerOutcome,
    },
    HostConstructorRefused,
    Stopped(pump::SelectedSourcePumpStep),
    UnexpectedStep(pump::SelectedSourcePumpStep),
    InspectionPendingObserved,
}
enum SetupFault {
    NoAction,
    NoOpening,
    Input(BrowserInputError),
    Action(BrowserActionIssueError),
    Selected(SelectedSourceFault),
    Native(SelectedSourceStartFault),
    SizeOverflow,
}
enum SourceIssueStage {
    OpeningPreparation,
    OpeningSettlement,
    InspectionPreparation,
    InspectionSettlement,
}
/// Each Err keeps the SAME actual cleanup owner. No branch projects pending
/// cleanup into a join or rewrites an observed refusal into a success.
enum SelectedPhysicalCleanup {
    NotPrepared,
    Unprepared(Result<BrowserUnpreparedControllerFinished, BrowserControllerPreparation>),
    Preparation(Result<BrowserControllerPreparationFinished, BrowserControllerPreparationFailure>),
    Materialized(Result<BrowserUnlaunchedControllerFinished, BrowserMaterializedController>),
    Launch(Result<BrowserControllerLaunchFinished, BrowserControllerLaunchFailure>),
    Running(Result<BrowserControllerFinished, BrowserFixedController>),
}
pub(super) enum SelectedNativeCleanup {
    NotBound,
    /// The constructor was invoked, but returned no native host owner. Its
    /// existing source/debt semantics are retained by the canonical engine.
    BindRefused(DocumentSetupFault),
    Observed(ControlledHostFinish),
}
impl SelectedSourcePrefixOutcome {
    pub(super) fn opening_control_fault(&self) -> Option<BrowserConnectedControlFault> {
        match &self.fact {
            PrefixFact::Stopped(step) | PrefixFact::UnexpectedStep(step) => {
                if let Err(cause) = step.observation {
                    Some(cause)
                } else if let pump::SelectedSourcePumpProgress::Stopped(
                    pump::SelectedSourcePumpStop::Controller(cause),
                ) = &step.progress
                {
                    Some(*cause)
                } else {
                    None
                }
            }
            _ => match &self.physical {
                SelectedPhysicalCleanup::Running(Ok(finished)) => finished.first_control_fault(),
                _ => None,
            },
        }
    }
    pub(super) fn physical_retirement(&self) -> Option<BrowserControllerRetirement> {
        match &self.physical {
            SelectedPhysicalCleanup::Unprepared(Ok(finished)) => Some(finished.retirement()),
            SelectedPhysicalCleanup::Preparation(Ok(finished)) => Some(finished.retirement()),
            SelectedPhysicalCleanup::Materialized(Ok(finished)) => Some(finished.retirement()),
            SelectedPhysicalCleanup::Launch(Ok(finished)) => Some(finished.retirement()),
            SelectedPhysicalCleanup::Running(Ok(finished)) => Some(finished.retirement()),
            _ => None,
        }
    }
}
fn outcome(
    fact: PrefixFact,
    observed: PrefixObserved,
    physical: SelectedPhysicalCleanup,
    native: SelectedNativeCleanup,
) -> SelectedSourcePrefixOutcome {
    SelectedSourcePrefixOutcome {
        fact,
        observed,
        physical,
        native,
    }
}
fn setup(cause: SetupFault) -> SelectedSourcePrefixOutcome {
    outcome(
        PrefixFact::SetupRefused(cause),
        PrefixObserved::None,
        SelectedPhysicalCleanup::NotPrepared,
        SelectedNativeCleanup::NotBound,
    )
}

/// No new deadline is issued. Even after business end, one actual cleanup poll
/// is permitted; an unfinished owner is returned rather than silently dropped.
struct CleanupPolling {
    original_end: Instant,
}
impl CleanupPolling {
    fn pause(&self) -> bool {
        let remaining = self.original_end.saturating_duration_since(Instant::now());
        if remaining.is_zero() {
            return false;
        }
        std::thread::sleep(remaining.min(Duration::from_millis(1)));
        true
    }
}
fn finish_controller(
    mut controller: BrowserFixedController,
    original_end: Instant,
) -> SelectedPhysicalCleanup {
    controller.request_shutdown();
    let polling = CleanupPolling { original_end };
    while !controller.poll_cleanup() {
        if !polling.pause() {
            break;
        }
    }
    SelectedPhysicalCleanup::Running(controller.finish())
}
fn finish_launch(
    mut failure: BrowserControllerLaunchFailure,
    original_end: Instant,
) -> SelectedPhysicalCleanup {
    failure.request_shutdown();
    let polling = CleanupPolling { original_end };
    while !failure.poll_cleanup() {
        if !polling.pause() {
            break;
        }
    }
    SelectedPhysicalCleanup::Launch(failure.finish_cleanup())
}
fn finish_native(
    owner: SelectedSourceHost,
    runtime: &tokio::runtime::Handle,
) -> SelectedNativeCleanup {
    let SelectedSourceHost { host, application } = owner;
    let joined = runtime.block_on(host.finish_joined());
    drop(application);
    SelectedNativeCleanup::Observed(joined)
}
fn release_prepared(native: SelectedSourcePrepared<'_>) -> SelectedSourceHost {
    let SelectedSourcePrepared { launch, runtime } = native;
    let SelectedSourceLaunch { owner, opening } = launch;
    drop(opening);
    drop(runtime);
    owner
}

/// Pay these NEW native wrappers before any host effect or residual cleanup
/// selection. Existing host/controller/pump preparation pays its own backing.
fn reserve_prefix(
    inputs: &SelectedSourcePrefixInputs<'_, '_>,
    loans: &mut BrowserLoans<'_, '_>,
) -> Result<(), SetupFault> {
    let layout = || -> Option<(usize, usize)> {
        let bytes = size_of::<SelectedSourcePrefixOutcome>()
            .checked_add(size_of::<PrefixFact>())?
            .checked_add(size_of::<PrefixObserved>())?
            .checked_add(size_of::<SetupFault>())?
            .checked_add(size_of::<SourceIssueStage>())?
            .checked_add(size_of::<SelectedPhysicalCleanup>())?
            .checked_add(size_of::<SelectedNativeCleanup>())?
            .checked_add(size_of::<SelectedSourcePrefixInputs<'_, '_>>())?
            .checked_add(size_of::<tokio::runtime::EnterGuard<'_>>())?
            .checked_add(size_of::<CleanupPolling>())?
            .checked_add(size_of::<Option<BrowserOpeningSelectionReply>>())?
            .checked_add(size_of::<Option<BrowserInspectionPendingReply>>())?;
        // One initialization and one move into the owned outcome, plus bounded
        // cleanup loop state/current clock/delay/result visits. This is visible
        // requested storage/work, never allocator, RSS or scheduler proof.
        let moves = bytes.checked_add(bytes)?;
        let ticks = usize::try_from(
            inputs
                .original_end
                .min(inputs.application.end)
                .saturating_duration_since(Instant::now())
                .as_nanos()
                .div_ceil(1_000_000),
        )
        .ok()?
        .checked_add(2)?;
        let cleanup_step = size_of::<CleanupPolling>()
            .checked_add(size_of::<Instant>())?
            .checked_add(size_of::<Duration>())?
            .checked_add(size_of::<bool>())?;
        let iterations = ticks.checked_add(inputs.document.records)?.checked_add(2)?;
        let reply_scratch = size_of::<Option<BrowserOpeningSelectionReply>>()
            .checked_add(size_of::<Option<BrowserInspectionPendingReply>>())?;
        Some((
            bytes,
            moves
                .checked_add(cleanup_step.checked_mul(ticks)?)?
                .checked_add(reply_scratch.checked_mul(iterations)?)?,
        ))
    };
    let (bytes, visits) = layout().ok_or(SetupFault::SizeOverflow)?;
    loans
        .reserve_controlled_host_storage(bytes, 12, visits)
        .map_err(SetupFault::Input)
}

pub(super) fn execute_selected_source_prefix<
    'compiled,
    'run,
    'case,
    'sources,
    'raw,
    'supplied,
    'inputs,
    'image,
>(
    run: &PreparedBrowserClientRun<'compiled, 'run, 'case, 'sources, 'raw, 'supplied>,
    loans: &mut BrowserLoans<'_, '_>,
    producer: &mut BrowserRowProducer<'_>,
    inputs: SelectedSourcePrefixInputs<'inputs, 'image>,
    runtime: &tokio::runtime::Handle,
    interrupted: &AtomicBool,
) -> SelectedSourcePrefixOutcome {
    let action = match run.next_action(loans) {
        Ok(Some(action)) => action,
        Ok(None) => return setup(SetupFault::NoAction),
        Err(cause) => return setup(SetupFault::Action(cause)),
    };
    let original_end = inputs.original_end.min(inputs.application.end);
    if let Err(cause) = reserve_prefix(&inputs, loans) {
        return setup(cause);
    }
    let opening = match run.openings(loans) {
        Ok(mut openings) => match openings.next() {
            Some(opening) => opening,
            None => return setup(SetupFault::NoOpening),
        },
        Err(cause) => return setup(SetupFault::Input(cause)),
    };
    let selected = match SelectedSourceApplication::prepare(
        inputs.application,
        inputs.manifest,
        loans,
        original_end,
    ) {
        Ok(selected) => selected,
        Err(cause) => return setup(SetupFault::Selected(cause)),
    };
    let endpoint = match producer.issue(run, &opening, loans) {
        Ok(endpoint) => endpoint,
        Err(cause) => return setup(SetupFault::Input(cause)),
    };
    let stimulus = match run.prepare_controlled_host(&opening, loans) {
        Ok(stimulus) => stimulus,
        Err(cause) => return setup(SetupFault::Input(cause)),
    };
    let host = match runtime.block_on(BoundControlledUiHost::bind_with_engine_observed_document(
        stimulus,
        inputs.application,
        loans,
        inputs.document,
        endpoint,
        original_end,
    )) {
        Ok(host) => host,
        Err(cause) => {
            return outcome(
                PrefixFact::HostConstructorRefused,
                PrefixObserved::None,
                SelectedPhysicalCleanup::NotPrepared,
                SelectedNativeCleanup::BindRefused(cause),
            );
        }
    };
    let (owned, preparation) = match action.prepare_connected_controller(
        host.document_producer
            .as_ref()
            .expect("engine constructor retains its producer"),
        host.state
            .transcript
            .as_ref()
            .expect("engine constructor retains its transcript"),
        &host.state.source,
        loans,
    ) {
        Ok(prepared) => prepared,
        Err(failure) => {
            drop(failure); // Actual first issue remains in the engine cursor.
            return outcome(
                PrefixFact::SourceIssueRetained(SourceIssueStage::OpeningPreparation),
                PrefixObserved::None,
                SelectedPhysicalCleanup::NotPrepared,
                finish_native(
                    SelectedSourceHost {
                        host,
                        application: selected,
                    },
                    runtime,
                ),
            );
        }
    };
    let sdk = match owned.connected_opening(
        host.document_producer.as_ref().expect("engine producer"),
        host.state.transcript.as_ref().expect("engine transcript"),
        &host.state.source,
        loans,
    ) {
        Ok(sdk) => sdk,
        Err(cause) => {
            return outcome(
                PrefixFact::SetupRefused(SetupFault::Action(cause)),
                PrefixObserved::None,
                SelectedPhysicalCleanup::Unprepared(preparation.finish_without_acquisition()),
                finish_native(
                    SelectedSourceHost {
                        host,
                        application: selected,
                    },
                    runtime,
                ),
            );
        }
    };
    let launch = match selected.into_launch(host, inputs.application, sdk, loans) {
        Ok(launch) => launch,
        Err(failure) => {
            let (cause, application, host, sdk) = failure.into_parts();
            drop(sdk);
            return outcome(
                PrefixFact::SetupRefused(SetupFault::Selected(cause)),
                PrefixObserved::None,
                SelectedPhysicalCleanup::Unprepared(preparation.finish_without_acquisition()),
                finish_native(SelectedSourceHost { host, application }, runtime),
            );
        }
    };
    // The actual guard is prepaid above and lives only around synchronous
    // native runtime retention. It is gone before any Handle::block_on call.
    let prepared = {
        let entered = runtime.enter();
        let result = launch.prepare_controller_runtime(loans);
        drop(entered);
        result
    };
    let prepared = match prepared {
        Ok(prepared) => prepared,
        Err(SelectedSourceStartFailure { fault, launch }) => {
            let SelectedSourceLaunch { owner, opening } = launch;
            drop(opening);
            return outcome(
                PrefixFact::SetupRefused(SetupFault::Native(fault)),
                PrefixObserved::None,
                SelectedPhysicalCleanup::Unprepared(preparation.finish_without_acquisition()),
                finish_native(owner, runtime),
            );
        }
    };
    let materialized = match preparation.prepare_runtime(
        inputs.runtime_archive,
        inputs.files,
        inputs.transport,
        loans,
    ) {
        Ok(materialized) => materialized,
        Err(failure) => {
            let stage = failure.stage();
            let physical = SelectedPhysicalCleanup::Preparation(failure.finish_cleanup());
            let owner = release_prepared(prepared.into_native());
            return outcome(
                PrefixFact::PreparationRefused(stage),
                PrefixObserved::None,
                physical,
                finish_native(owner, runtime),
            );
        }
    };
    let staged = match prepared.prepare_controller_launch(materialized, loans) {
        Ok(staged) => staged,
        Err(SelectedSourceControllerPreparationFailure {
            native,
            materialized,
            cause,
        }) => {
            let owner = release_prepared(native);
            return outcome(
                PrefixFact::SetupRefused(SetupFault::Action(cause)),
                PrefixObserved::None,
                SelectedPhysicalCleanup::Materialized(materialized.finish_cleanup()),
                finish_native(owner, runtime),
            );
        }
    };
    let launched = match staged.launch_controller(loans) {
        Ok(launched) => launched,
        Err(SelectedSourceControllerLaunchFailure::BeforeSpawn { staged, cause }) => {
            let SelectedSourceControllerPrepared {
                native,
                materialized,
                listener_credit,
            } = staged;
            drop(listener_credit);
            let owner = release_prepared(native);
            return outcome(
                PrefixFact::SetupRefused(SetupFault::Native(cause)),
                PrefixObserved::None,
                SelectedPhysicalCleanup::Materialized(materialized.finish_cleanup()),
                finish_native(owner, runtime),
            );
        }
        Err(SelectedSourceControllerLaunchFailure::Physical {
            native,
            listener_credit,
            controller,
        }) => {
            let stage = controller.stage();
            drop(listener_credit);
            let owner = release_prepared(native);
            return outcome(
                PrefixFact::LaunchRefused(stage),
                PrefixObserved::None,
                finish_launch(controller, original_end),
                finish_native(owner, runtime),
            );
        }
    };
    let mut running = match launched.start_listener(loans) {
        Ok(running) => running,
        Err(SelectedSourceControllerListenerFailure { native, controller }) => {
            let SelectedSourcePrepaidStartFailure {
                launch,
                gate,
                native,
            } = native;
            let SelectedSourceLaunch { owner, opening } = launch;
            drop(opening);
            return outcome(
                PrefixFact::ListenerRefused { gate, native },
                PrefixObserved::None,
                finish_controller(controller, original_end),
                finish_native(owner, runtime),
            );
        }
    };
    let opening_reply = loop {
        let step = running.step_opening(loans, interrupted);
        let observed = match step.observation {
            Ok(BrowserConnectedObservation::Opening(reply)) => Some(reply),
            _ => None,
        };
        if matches!(&step.progress, pump::SelectedSourcePumpProgress::Stopped(_)) {
            let SelectedSourceControllerRunning { native, controller } = running;
            let SelectedSourceStarted { owner, opening } = native;
            drop(opening);
            return outcome(
                PrefixFact::Stopped(step),
                observed
                    .map(PrefixObserved::Opening)
                    .unwrap_or(PrefixObserved::None),
                finish_controller(controller, original_end),
                finish_native(owner, runtime),
            );
        }
        if !matches!(
            step.observation,
            Ok(BrowserConnectedObservation::Pending | BrowserConnectedObservation::Opening(_))
        ) {
            let SelectedSourceControllerRunning { native, controller } = running;
            let SelectedSourceStarted { owner, opening } = native;
            drop(opening);
            return outcome(
                PrefixFact::UnexpectedStep(step),
                PrefixObserved::None,
                finish_controller(controller, original_end),
                finish_native(owner, runtime),
            );
        }
        // Every nonterminal step, including one carrying a reply, takes the
        // SAME measured cooperative wait before another phase or iteration.
        runtime.block_on(running.wait_for_change());
        if let Some(reply) = observed {
            break reply;
        }
    };
    let SelectedSourceControllerRunning { native, controller } = running;
    let SelectedSourceStarted { mut owner, opening } = native;
    drop(opening); // Release ONLY the short source0 SDK before consuming owned.
    let continuing = match controller.into_continuing(owned, loans) {
        Ok(continuing) => continuing,
        Err(failure) => {
            let (controller, owned) = failure.into_parts();
            drop(owned);
            return outcome(
                PrefixFact::SourceIssueRetained(SourceIssueStage::OpeningSettlement),
                PrefixObserved::Opening(opening_reply),
                finish_controller(controller, original_end),
                finish_native(owner, runtime),
            );
        }
    };
    let action1 = match run.next_action(loans) {
        Ok(Some(action)) => action,
        Ok(None) => {
            return outcome(
                PrefixFact::SetupRefused(SetupFault::NoAction),
                PrefixObserved::Opening(opening_reply),
                finish_controller(continuing.into_cleanup(), original_end),
                finish_native(owner, runtime),
            );
        }
        Err(cause) => {
            return outcome(
                PrefixFact::SetupRefused(SetupFault::Action(cause)),
                PrefixObserved::Opening(opening_reply),
                finish_controller(continuing.into_cleanup(), original_end),
                finish_native(owner, runtime),
            );
        }
    };
    let (boundary, mut controller) = match continuing.prepare_inspection_boundary(action1, loans) {
        Ok(prepared) => prepared,
        Err(failure) => {
            let (continuing, action) = failure.into_parts();
            drop(action);
            return outcome(
                PrefixFact::SourceIssueRetained(SourceIssueStage::InspectionPreparation),
                PrefixObserved::Opening(opening_reply),
                finish_controller(continuing.into_cleanup(), original_end),
                finish_native(owner, runtime),
            );
        }
    };
    let sdk = match controller.inspection_source(&boundary, loans) {
        Ok(sdk) => sdk,
        Err(cause) => {
            return outcome(
                PrefixFact::SetupRefused(SetupFault::Action(cause)),
                PrefixObserved::Opening(opening_reply),
                finish_controller(controller, original_end),
                finish_native(owner, runtime),
            );
        }
    };
    let inspection_reply = loop {
        let step = pump::step(
            &mut owner,
            &mut controller,
            pump::SelectedSourcePumpSource::Inspection(&sdk),
            loans,
            interrupted,
        );
        let observed = match step.observation {
            Ok(BrowserConnectedObservation::InspectionBoundary(reply)) => Some(reply),
            _ => None,
        };
        if matches!(&step.progress, pump::SelectedSourcePumpProgress::Stopped(_)) {
            drop(sdk);
            let observed = observed
                .map(|inspection| PrefixObserved::OpeningAndInspection {
                    opening: opening_reply,
                    inspection,
                })
                .unwrap_or(PrefixObserved::Opening(opening_reply));
            return outcome(
                PrefixFact::Stopped(step),
                observed,
                finish_controller(controller, original_end),
                finish_native(owner, runtime),
            );
        }
        if !matches!(
            step.observation,
            Ok(BrowserConnectedObservation::Pending
                | BrowserConnectedObservation::InspectionBoundary(_))
        ) {
            drop(sdk);
            return outcome(
                PrefixFact::UnexpectedStep(step),
                PrefixObserved::Opening(opening_reply),
                finish_controller(controller, original_end),
                finish_native(owner, runtime),
            );
        }
        runtime.block_on(pump::wait(&owner.host));
        if let Some(reply) = observed {
            break reply;
        }
    };
    drop(sdk);
    let observed = PrefixObserved::OpeningAndInspection {
        opening: opening_reply,
        inspection: inspection_reply,
    };
    match controller.settle_inspection(boundary, loans) {
        Ok(stopped) => outcome(
            PrefixFact::InspectionPendingObserved,
            observed,
            finish_controller(stopped.into_cleanup(), original_end),
            finish_native(owner, runtime),
        ),
        Err(failure) => {
            let (controller, boundary) = failure.into_parts();
            drop(boundary);
            outcome(
                PrefixFact::SourceIssueRetained(SourceIssueStage::InspectionSettlement),
                observed,
                finish_controller(controller, original_end),
                finish_native(owner, runtime),
            )
        }
    }
    // Source2 and every later source action remain untouched. No core command
    // or fabricated Observation/verdict is produced by this prefix.
}
