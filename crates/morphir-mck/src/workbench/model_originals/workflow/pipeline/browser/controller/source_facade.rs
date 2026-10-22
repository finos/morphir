//! Actual selected runtime and fixed controller ownership. Descriptive inputs
//! cannot construct source identity, measured replies, joins or completion.
pub(in super::super) use super::super::adapter::execution_loans::SourceControllerLifetime as BrowserControllerPreparation;
use super::super::adapter::{BrowserInputError, BrowserLoans, BrowserSourceFault};
use super::acquisition::{
    AcquisitionFailureCleanupEvidence, ControllerAcquisitionFailure, ControllerAcquisitionFault,
    SourceControllerFileOutcome, SourceFileRelease, SourceUnlaunchedFileOutcome,
};
use super::source_inputs::{RuntimeAssociationFault, SelectedRuntimePackage};
use super::source_operation::SourceOperationPrepayment;
use super::*;
mod launch_storage;
use super::super::adapter::execution_loans::{BrowserActionIssueError, BrowserConnectedOpening};
use super::super::funded_workflow::BrowserPhysicalParts;
use super::BrowserControllerBusinessCredit;
use super::source_business::SourceBusinessOperation;
use crate::transport::process::{
    CommandSpecError, ProcessError, interactive::InteractiveSpawnError,
};
pub(super) use launch_storage::{
    SOURCE_ENDPOINT_BYTES, SourcePreparedDriverCommand, before_effect, fill_decimal, fill_os,
};
use launch_storage::{SourceLaunchStorage, StorageFault};

/// Explicit filesystem DATA. Actual source/held identity checks remain required.
pub struct BrowserControllerFile<'a> {
    pub path: &'a Path,
    pub byte_length: u64,
}
pub struct BrowserControllerFiles<'a> {
    pub chromium: BrowserControllerFile<'a>,
    pub node: BrowserControllerFile<'a>,
    pub root: &'a Path,
}
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BrowserControllerPreparationStage {
    RuntimeSelection,
    ControlStorage,
    AcquisitionPreparation,
    Acquisition,
}
enum PreparationRefusal {
    Runtime {
        preparation: BrowserControllerPreparation,
        cause: RuntimeAssociationFault,
    },
    Storage {
        preparation: BrowserControllerPreparation,
        package: SelectedRuntimePackage,
        storage: SourceLaunchStorage,
        cause: StorageFault,
    },
    Acquisition {
        stage: BrowserControllerPreparationStage,
        owner: ControllerAcquisitionFailure,
        storage: SourceLaunchStorage,
    },
}
pub struct BrowserControllerPreparationFailure(PreparationRefusal);
impl BrowserControllerPreparationFailure {
    pub fn stage(&self) -> BrowserControllerPreparationStage {
        match &self.0 {
            PreparationRefusal::Runtime { .. } => {
                BrowserControllerPreparationStage::RuntimeSelection
            }
            PreparationRefusal::Storage { .. } => BrowserControllerPreparationStage::ControlStorage,
            PreparationRefusal::Acquisition { stage, .. } => *stage,
        }
    }
    pub fn input_error(&self) -> Option<&BrowserInputError> {
        match &self.0 {
            PreparationRefusal::Runtime {
                cause: RuntimeAssociationFault::Input(error),
                ..
            } => Some(error),
            PreparationRefusal::Storage {
                cause: StorageFault::Input(error),
                ..
            } => Some(error),
            PreparationRefusal::Acquisition { owner, .. } => match owner.fault() {
                ControllerAcquisitionFault::Input(error) => Some(error),
                _ => None,
            },
            _ => None,
        }
    }
    /// Consume only actual retained owners. This requires no new business
    /// permission after source revocation/end and never manufactures a process.
    pub fn finish_cleanup(self) -> Result<BrowserControllerPreparationFinished, Self> {
        let stage = self.stage();
        match self.0 {
            PreparationRefusal::Runtime {
                mut preparation,
                cause,
            } => {
                let retirement = retire(&mut preparation);
                Ok(BrowserControllerPreparationFinished {
                    stage,
                    retirement,
                    evidence: PreparationFinishedEvidence::Runtime(cause),
                    release: SourceFileRelease::HandlesReleasedUnverified { handles: 0 },
                })
            }
            PreparationRefusal::Storage {
                mut preparation,
                package,
                storage,
                cause,
            } => {
                drop((package, storage));
                let retirement = retire(&mut preparation);
                Ok(BrowserControllerPreparationFinished {
                    stage,
                    retirement,
                    evidence: PreparationFinishedEvidence::Storage(cause),
                    release: SourceFileRelease::HandlesReleasedUnverified { handles: 0 },
                })
            }
            PreparationRefusal::Acquisition { owner, storage, .. } => {
                match owner.finish_cleanup() {
                    Err(owner) => Err(Self(PreparationRefusal::Acquisition {
                        stage,
                        owner,
                        storage,
                    })),
                    Ok(cleaned) => {
                        drop(storage);
                        let release = cleaned.release();
                        let (mut preparation, evidence) = cleaned.into_parts();
                        let retirement = retire(&mut preparation);
                        Ok(BrowserControllerPreparationFinished {
                            stage,
                            retirement,
                            release,
                            evidence: PreparationFinishedEvidence::Acquisition(evidence),
                        })
                    }
                }
            }
        }
    }
}
impl std::fmt::Debug for BrowserControllerPreparationFailure {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        let mut debug = f.debug_struct("BrowserControllerPreparationFailure");
        debug.field("stage", &self.stage());
        match &self.0 {
            PreparationRefusal::Runtime { cause, .. } => debug.field("cause", cause),
            PreparationRefusal::Storage { cause, .. } => debug.field("cause", cause),
            PreparationRefusal::Acquisition { owner, .. } => debug.field("cause", owner.fault()),
        }
        .finish_non_exhaustive()
    }
}
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BrowserControllerRetirement {
    Returned,
    Refused(BrowserSourceFault),
}
fn retire(preparation: &mut BrowserControllerPreparation) -> BrowserControllerRetirement {
    match preparation.retire_after_join_in_place() {
        Ok(()) => BrowserControllerRetirement::Returned,
        Err(cause) => BrowserControllerRetirement::Refused(cause),
    }
}
enum PreparationFinishedEvidence {
    Runtime(RuntimeAssociationFault),
    Storage(StorageFault),
    Acquisition(AcquisitionFailureCleanupEvidence),
}
/// Factual owned teardown only. File destructors do not prove OS-close success;
/// this retires no native host and settles no logical source operation.
pub struct BrowserControllerPreparationFinished {
    stage: BrowserControllerPreparationStage,
    retirement: BrowserControllerRetirement,
    release: SourceFileRelease,
    evidence: PreparationFinishedEvidence,
}
impl BrowserControllerPreparationFinished {
    pub fn stage(&self) -> BrowserControllerPreparationStage {
        self.stage
    }
    pub fn retirement(&self) -> BrowserControllerRetirement {
        self.retirement
    }
}
pub struct BrowserMaterializedController {
    target: MaterializedControllerTarget,
    storage: SourceLaunchStorage,
}
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BrowserControllerLaunchStage {
    Association,
    Preparation,
    PreChildSpawn,
    Started,
}
#[derive(Debug)]
enum LaunchCause {
    Association(BrowserActionIssueError),
    Input(BrowserInputError),
    Control(ControllerFault),
    Command(CommandSpecError),
    Spawn(InteractiveSpawnError),
}
struct SourceUnspawnedController {
    target: AcquiredTarget,
    buffers: BrowserPhysicalParts,
    storage: SourceLaunchStorage,
    variant: ControllerVariant,
    clock: clock::deadline::DarwinContinuousDeadline,
    lifetime: BrowserControllerPreparation,
    prepayment: SourceOperationPrepayment,
}
enum LaunchRefusal {
    Materialized {
        owner: BrowserMaterializedController,
        cause: LaunchCause,
    },
    Unspawned {
        owner: SourceUnspawnedController,
        cause: LaunchCause,
    },
    Started {
        owner: SourceControllerPhysical,
        cause: LaunchCause,
    },
}
pub struct BrowserControllerLaunchFailure(LaunchRefusal);
enum LaunchFinishedEvidence {
    Unlaunched {
        files: SourceUnlaunchedFileOutcome,
        cause: LaunchCause,
    },
    Started {
        finished: SourceControllerFinished,
        cause: LaunchCause,
    },
}
pub struct BrowserControllerLaunchFinished {
    stage: BrowserControllerLaunchStage,
    retirement: BrowserControllerRetirement,
    evidence: LaunchFinishedEvidence,
}
impl BrowserControllerLaunchFinished {
    pub fn stage(&self) -> BrowserControllerLaunchStage {
        self.stage
    }
    pub fn retirement(&self) -> BrowserControllerRetirement {
        self.retirement
    }
}
impl BrowserControllerLaunchFailure {
    pub fn stage(&self) -> BrowserControllerLaunchStage {
        match &self.0 {
            LaunchRefusal::Materialized {
                cause: LaunchCause::Association(_),
                ..
            } => BrowserControllerLaunchStage::Association,
            LaunchRefusal::Materialized { .. } => BrowserControllerLaunchStage::Preparation,
            LaunchRefusal::Unspawned {
                cause: LaunchCause::Spawn(_),
                ..
            } => BrowserControllerLaunchStage::PreChildSpawn,
            LaunchRefusal::Unspawned { .. } => BrowserControllerLaunchStage::Preparation,
            LaunchRefusal::Started { .. } => BrowserControllerLaunchStage::Started,
        }
    }
    pub fn spawn_error(&self) -> Option<&std::io::Error> {
        let cause = match &self.0 {
            LaunchRefusal::Materialized { cause, .. }
            | LaunchRefusal::Unspawned { cause, .. }
            | LaunchRefusal::Started { cause, .. } => cause,
        };
        match cause {
            LaunchCause::Spawn(InteractiveSpawnError::Process(ProcessError::Spawn(error))) => {
                Some(error)
            }
            _ => None,
        }
    }
    pub fn request_shutdown(&mut self) {
        if let LaunchRefusal::Started { owner, .. } = &mut self.0 {
            owner.controller.request_shutdown();
        }
    }
    pub fn poll_cleanup(&mut self) -> bool {
        match &mut self.0 {
            LaunchRefusal::Started { owner, .. } => owner.controller.poll_cleanup(),
            _ => true,
        }
    }
    pub fn finish_cleanup(self) -> Result<BrowserControllerLaunchFinished, Self> {
        let stage = self.stage();
        match self.0 {
            LaunchRefusal::Materialized { owner, cause } => {
                let BrowserMaterializedController { target, storage } = owner;
                match target.finish_unlaunched() {
                    Err(target) => Err(Self(LaunchRefusal::Materialized {
                        owner: BrowserMaterializedController { target, storage },
                        cause,
                    })),
                    Ok((mut lifetime, files)) => {
                        drop(storage);
                        let retirement = retire(&mut lifetime);
                        Ok(BrowserControllerLaunchFinished {
                            stage,
                            retirement,
                            evidence: LaunchFinishedEvidence::Unlaunched { files, cause },
                        })
                    }
                }
            }
            LaunchRefusal::Unspawned { owner, cause } => {
                let SourceUnspawnedController {
                    target,
                    buffers,
                    storage,
                    variant,
                    clock,
                    mut lifetime,
                    prepayment,
                } = owner;
                match target.finish_unlaunched() {
                    Err(target) => Err(Self(LaunchRefusal::Unspawned {
                        owner: SourceUnspawnedController {
                            target,
                            buffers,
                            storage,
                            variant,
                            clock,
                            lifetime,
                            prepayment,
                        },
                        cause,
                    })),
                    Ok(files) => {
                        drop((buffers, storage, variant, clock, prepayment));
                        let retirement = retire(&mut lifetime);
                        Ok(BrowserControllerLaunchFinished {
                            stage,
                            retirement,
                            evidence: LaunchFinishedEvidence::Unlaunched { files, cause },
                        })
                    }
                }
            }
            LaunchRefusal::Started { owner, cause } => match owner.finish() {
                Err(owner) => Err(Self(LaunchRefusal::Started { owner, cause })),
                Ok(finished) => Ok(BrowserControllerLaunchFinished {
                    stage,
                    retirement: finished.retirement,
                    evidence: LaunchFinishedEvidence::Started { finished, cause },
                }),
            },
        }
    }
}
impl std::fmt::Debug for BrowserControllerLaunchFailure {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        let cause = match &self.0 {
            LaunchRefusal::Materialized { cause, .. }
            | LaunchRefusal::Unspawned { cause, .. }
            | LaunchRefusal::Started { cause, .. } => cause,
        };
        f.debug_struct("BrowserControllerLaunchFailure")
            .field("stage", &self.stage())
            .field("cause", cause)
            .finish_non_exhaustive()
    }
}
impl BrowserMaterializedController {
    /// Move the sole already-funded listener allowance. This grants neither
    /// source authority nor a successful native listener; its actual consumer
    /// still validates the same opening/host and records its real effects.
    pub fn listener_start_credit(
        &mut self,
        loans: &BrowserLoans<'_, '_>,
    ) -> Result<BrowserControllerBusinessCredit, BrowserActionIssueError> {
        self.target
            .take_business(SourceBusinessOperation::ListenerStart, loans)
    }
    #[cfg(test)]
    pub(super) fn take_dispatch_credit(
        &mut self,
        loans: &BrowserLoans<'_, '_>,
    ) -> Result<BrowserControllerBusinessCredit, BrowserActionIssueError> {
        self.target
            .take_business(SourceBusinessOperation::ControllerDispatch, loans)
    }
    pub fn launch(
        mut self,
        launch_uri: &str,
        opening: &BrowserConnectedOpening<'_>,
        loans: &mut BrowserLoans<'_, '_>,
    ) -> Result<super::source_progress::BrowserFixedController, BrowserControllerLaunchFailure>
    {
        let prepared = (|| {
            let credit = self
                .target
                .take_business(SourceBusinessOperation::LaunchValidation, loans)
                .map_err(LaunchCause::Association)?;
            let (target, lifetime, prepayment, limits) = self.target.launch_parts();
            lifetime
                .validate_opening_prepaid(opening, credit, loans)
                .map_err(LaunchCause::Association)?;
            prepayment
                .validate(lifetime, limits, loans)
                .map_err(LaunchCause::Input)?;
            lifetime
                .while_business_active(|| {
                    let end = lifetime.end();
                    target
                        .chromium
                        .validate_source(end)
                        .map_err(LaunchCause::Control)?;
                    target
                        .node
                        .validate_source(end)
                        .map_err(LaunchCause::Control)?;
                    before_effect(end).map_err(LaunchCause::Control)?;
                    let (before, ticks, after, ratio) = clock::sample()
                        .map_err(|_| LaunchCause::Control(ControllerFault::Clock))?;
                    before_effect(end).map_err(LaunchCause::Control)?;
                    let clock = clock::deadline::export(end, before, ticks, after, ratio)
                        .map_err(|_| LaunchCause::Control(ControllerFault::Clock))?;
                    // These descriptive values fill only already-funded backing.
                    // The nominal source/action association above is separate.
                    if !self.storage.uri.is_empty()
                        || launch_uri.len() > self.storage.uri.capacity()
                    {
                        return Err(LaunchCause::Control(ControllerFault::Shape));
                    }
                    before_effect(end).map_err(LaunchCause::Control)?;
                    self.storage.uri.push_str(launch_uri);
                    fill_os(
                        &mut self.storage.driver.arguments[9],
                        launch_uri.as_ref(),
                        end,
                    )
                    .map_err(LaunchCause::Control)?;
                    for ((copy, arg), source) in self
                        .storage
                        .selection
                        .iter_mut()
                        .zip(&mut self.storage.driver.arguments[10..13])
                        .zip([
                            opening.provider_id(),
                            opening.locator(),
                            opening.project_id(),
                        ])
                    {
                        if !copy.is_empty() || source.len() > copy.capacity() {
                            return Err(LaunchCause::Control(ControllerFault::Output));
                        }
                        before_effect(end).map_err(LaunchCause::Control)?;
                        copy.push_str(source);
                        fill_os(arg, source.as_ref(), end).map_err(LaunchCause::Control)?;
                    }
                    // The parser consumes the funded URI. It establishes spelling,
                    // never source authority or actual host liveness.
                    let launch = ObservedLaunch::parse(std::mem::take(&mut self.storage.uri))
                        .map_err(LaunchCause::Control)?;
                    let selection = std::mem::replace(
                        &mut self.storage.selection,
                        std::array::from_fn(|_| String::new()),
                    );
                    Ok((
                        clock,
                        ControllerVariant::SourceObserved { launch, selection },
                    ))
                })
                .map_err(LaunchCause::Input)?
        })();
        let (clock, variant) = match prepared {
            Ok(value) => value,
            Err(cause) => {
                return Err(BrowserControllerLaunchFailure(
                    LaunchRefusal::Materialized { owner: self, cause },
                ));
            }
        };
        let (target, buffers, lifetime, prepayment) = self.target.into_parts();
        let mut pending = Some((target, buffers, self.storage, variant, clock));
        // If the source gate refuses, the closure never takes the physical
        // owners. If it runs, all actual spawn outcomes remain owned below.
        let spawned = lifetime.while_business_active(|| {
            let (target, mut buffers, mut storage, variant, clock) =
                pending.take().expect("exclusive source launch");
            let result = (|| {
                before_effect(lifetime.end()).map_err(LaunchCause::Control)?;
                let spec = CommandSpec::new(
                    std::mem::take(&mut storage.chromium_program),
                    std::mem::take(&mut storage.chromium_arguments),
                    std::mem::take(&mut storage.chromium_directory),
                    Vec::new(),
                )
                .map_err(LaunchCause::Command)?;
                before_effect(lifetime.end()).map_err(LaunchCause::Control)?;
                let captured = std::mem::replace(
                    &mut buffers.chromium,
                    FixedCaptureBuffers::new(Vec::new(), Vec::new()),
                );
                match OneShotProcess::spawn_fixed_capture_retained(spec, buffers.limits, captured) {
                    Ok(chromium) => Ok(chromium),
                    Err(failure) => {
                        let (cause, capture) = failure.into_parts();
                        buffers.chromium = capture;
                        Err(LaunchCause::Spawn(cause))
                    }
                }
            })();
            match result {
                Err(cause) => Err(((target, buffers, storage, variant, clock), cause)),
                Ok(chromium) => {
                    let controller = BrowserController {
                        target,
                        variant,
                        limits: buffers.limits,
                        end: lifetime.end(),
                        clock,
                        chromium: Chromium::Running(chromium),
                        driver: Driver::Prepared {
                            command: storage.driver,
                            capture: buffers.driver,
                        },
                        conversation: Conversation::Launching,
                        first_fault: None,
                        capture: buffers.control_prefix,
                        cursor: 0,
                        frame_start: 0,
                    };
                    // window0 was deliberately prepared for this no-download
                    // slice. It is not evidence of a downloaded artifact.
                    drop(buffers.download_window);
                    Ok(controller)
                }
            }
        });
        match spawned {
            Err(error) => {
                let (target, buffers, storage, variant, clock) =
                    pending.expect("gate refused before taking owners");
                Err(BrowserControllerLaunchFailure(LaunchRefusal::Unspawned {
                    owner: SourceUnspawnedController {
                        target,
                        buffers,
                        storage,
                        variant,
                        clock,
                        lifetime,
                        prepayment,
                    },
                    cause: LaunchCause::Input(error),
                }))
            }
            Ok(Err(((target, buffers, storage, variant, clock), cause))) => {
                Err(BrowserControllerLaunchFailure(LaunchRefusal::Unspawned {
                    owner: SourceUnspawnedController {
                        target,
                        buffers,
                        storage,
                        variant,
                        clock,
                        lifetime,
                        prepayment,
                    },
                    cause,
                }))
            }
            Ok(Ok(mut controller)) => {
                if let Err(fault) = before_effect(lifetime.end()) {
                    controller.fail(fault);
                    return Err(BrowserControllerLaunchFailure(LaunchRefusal::Started {
                        owner: SourceControllerPhysical {
                            controller,
                            lifetime,
                            prepayment,
                        },
                        cause: LaunchCause::Control(fault),
                    }));
                }
                Ok(
                    super::source_progress::BrowserFixedController::from_physical(
                        SourceControllerPhysical {
                            controller,
                            lifetime,
                            prepayment,
                        },
                    ),
                )
            }
        }
    }
}
impl BrowserControllerPreparation {
    pub fn prepare_runtime(
        self,
        archive: &[u8],
        files: BrowserControllerFiles<'_>,
        limits: Limits,
        loans: &mut BrowserLoans<'_, '_>,
    ) -> Result<BrowserMaterializedController, BrowserControllerPreparationFailure> {
        let selected = (|| {
            self.validate(loans)
                .map_err(RuntimeAssociationFault::Input)?;
            let headers = std::mem::size_of::<BrowserControllerPreparationFailure>()
                .checked_add(std::mem::size_of::<BrowserMaterializedController>())
                .and_then(|n| {
                    n.checked_add(std::mem::size_of::<BrowserControllerPreparationFinished>())
                })
                .and_then(|n| n.checked_add(std::mem::size_of::<SourceControllerPhysical>()))
                .and_then(|n| n.checked_add(std::mem::size_of::<SourceControllerFinished>()))
                .and_then(|n| n.checked_add(std::mem::size_of::<BrowserControllerLaunchFailure>()))
                .and_then(|n| n.checked_add(std::mem::size_of::<BrowserControllerLaunchFinished>()))
                .and_then(|n| n.checked_add(std::mem::size_of::<SourceUnspawnedController>()))
                .ok_or(RuntimeAssociationFault::Overflow)?;
            loans
                .reserve_controlled_host_storage(headers, 8, headers)
                .map_err(RuntimeAssociationFault::Input)?;
            SelectedRuntimePackage::prepare(archive, &self, loans)
        })();
        let package = match selected {
            Ok(package) => package,
            Err(cause) => {
                return Err(BrowserControllerPreparationFailure(
                    PreparationRefusal::Runtime {
                        preparation: self,
                        cause,
                    },
                ));
            }
        };
        let mut storage = SourceLaunchStorage::empty();
        if let Err(cause) = storage.prepare(&files, &self, loans) {
            return Err(BrowserControllerPreparationFailure(
                PreparationRefusal::Storage {
                    preparation: self,
                    package,
                    storage,
                    cause,
                },
            ));
        }
        let prepared = FundedControllerAcquisition::prepare_selected(
            SelectedControllerTargetInput {
                chromium: ControllerFileInput {
                    path: files.chromium.path,
                    byte_length: files.chromium.byte_length,
                },
                node: ControllerFileInput {
                    path: files.node.path,
                    byte_length: files.node.byte_length,
                },
                root: files.root,
            },
            limits,
            self,
            package,
            loans,
        );
        let prepared = match prepared {
            Ok(prepared) => prepared,
            Err(owner) => {
                return Err(BrowserControllerPreparationFailure(
                    PreparationRefusal::Acquisition {
                        stage: BrowserControllerPreparationStage::AcquisitionPreparation,
                        owner,
                        storage,
                    },
                ));
            }
        };
        let target = match prepared.acquire_selected(loans) {
            Ok(target) => target,
            Err(owner) => {
                return Err(BrowserControllerPreparationFailure(
                    PreparationRefusal::Acquisition {
                        stage: BrowserControllerPreparationStage::Acquisition,
                        owner,
                        storage,
                    },
                ));
            }
        };
        Ok(BrowserMaterializedController { target, storage })
    }
}

pub(super) struct SourceControllerPhysical {
    pub(super) controller: BrowserController,
    pub(super) lifetime: BrowserControllerPreparation,
    pub(super) prepayment: SourceOperationPrepayment,
}
pub(super) struct SourceControllerFinished {
    pub(super) files: SourceControllerFileOutcome,
    pub(super) retirement: BrowserControllerRetirement,
}
impl SourceControllerPhysical {
    pub(super) fn finish(self) -> Result<SourceControllerFinished, Self> {
        let Self {
            controller,
            mut lifetime,
            prepayment,
        } = self;
        let outcome = match controller.into_finished() {
            ControllerFinish::Pending(controller) => {
                return Err(Self {
                    controller,
                    lifetime,
                    prepayment,
                });
            }
            ControllerFinish::Finished(outcome) => outcome,
        };
        match outcome.finish_source_files() {
            Err(outcome) => Err(Self {
                controller: outcome.0,
                lifetime,
                prepayment,
            }),
            Ok(files) => {
                let retirement = retire(&mut lifetime);
                Ok(SourceControllerFinished { files, retirement })
            }
        }
    }
}

#[cfg(test)]
mod tests;
