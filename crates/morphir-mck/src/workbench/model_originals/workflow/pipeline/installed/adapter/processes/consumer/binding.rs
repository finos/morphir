//! Projection of existing association DATA onto the SAME actual launch spec.
//! This checks coherence, never source authenticity or executable immutability.
use super::*;
use crate::workbench::model_originals::workflow::pipeline::installed::adapter::data;
use std::os::unix::ffi::OsStrExt;

pub(super) enum ConsumerBinding {
    Raw,
    Observed(ObservedLaunch),
}
pub(super) enum ObservedLaunch {
    NodePackage {
        runtime: OsString,
        helper: OsString,
        directory: OsString,
    },
    NativeExecutable {
        runtime: OsString,
        helper: OsString,
        directory: OsString,
    },
}
impl ObservedLaunch {
    pub(super) fn helper_matches(
        &self,
        launch: &wire::Launch,
        owner: &mut crate::workbench::model_originals::workflow::Decoder,
    ) -> Result<bool, crate::workbench::model_originals::workflow::DecodeError> {
        let Self::NativeExecutable {
            runtime,
            helper,
            directory,
        } = self
        else {
            return Ok(false);
        };
        if !launch.program.matches(runtime, owner)?
            || !launch.directory.matches(directory, owner)?
            || launch.arguments.as_slice().len() != 3
        {
            return Ok(false);
        }
        let args = launch.arguments.as_slice();
        if !args[0].matches(helper, owner)?
            || !args[1].matches(OsStr::new("--morphir-originals-v1"), owner)?
        {
            return Ok(false);
        }
        // The config filename is genuinely dynamic producer DATA. It is not a
        // new source operand or a claim that a particular temp file was read.
        args[2].absolute(owner)
    }
}
pub(super) fn operand(value: &data::OsOperand) -> Result<&OsStr, InstalledAdapterError> {
    match value {
        data::OsOperand::UnixBytes { bytes } => Ok(OsStr::from_bytes(bytes.as_bytes())),
        _ => Err(InstalledAdapterError::ObservationIncomplete),
    }
}
impl InstalledClientRun<'_> {
    fn consumer_same(
        &mut self,
        left: &OsStr,
        right: &OsStr,
    ) -> Result<bool, InstalledAdapterError> {
        let length = left
            .len()
            .checked_add(right.len())
            .ok_or_else(|| self.overflow_failure())?;
        self.visit_observation_bytes(length)?;
        Ok(left == right)
    }
    pub(in crate::workbench::model_originals::workflow::pipeline::installed::adapter) fn prepare_observed_consumer_process(
        &mut self,
        command: ConsumerProcessCommand<'_>,
        end: Instant,
        implementation: &data::ImplementationObservation,
    ) -> Result<(PreparedInstalledConsumerProcess, InstalledConsumerPorts), InstalledAdapterError>
    {
        let binding = self.observed_consumer_binding(&command, implementation)?;
        self.prepare_consumer_bound(
            command,
            end,
            ConsumerBinding::Observed(binding),
            export::PreparedClock::Unlaunched,
        )
    }
    pub(super) fn observed_consumer_binding(
        &mut self,
        command: &ConsumerProcessCommand<'_>,
        implementation: &data::ImplementationObservation,
    ) -> Result<ObservedLaunch, InstalledAdapterError> {
        self.work_ready()?;
        let fail =
            |run: &mut Self| run.observation_failure(InstalledObservationError::LayoutMismatch);
        let data::ImplementationObservation::Observed {
            launch,
            runtime,
            command_paths: paths,
            package,
            source,
            ..
        } = implementation
        else {
            return Err(fail(self));
        };
        let runtime_program = operand(&runtime.program).map_err(|_| fail(self))?;
        let package_root = Path::new(operand(&package.root).map_err(|_| fail(self))?);
        let source_root = Path::new(operand(&source.root).map_err(|_| fail(self))?);
        for path in [
            command.program,
            command.directory,
            Path::new(runtime_program),
            package_root,
            source_root,
        ] {
            self.visit_observation_bytes(path.as_os_str().len())?;
            if !path.is_absolute() {
                return Err(fail(self));
            }
        }
        let destination = operand(&paths.destination).map_err(|_| fail(self))?;
        self.visit_observation_bytes(destination.len())?;
        if destination.is_empty()
            || Path::new(destination)
                .components()
                .any(|part| !matches!(part, std::path::Component::Normal(_)))
        {
            return Err(fail(self));
        }
        let helper = self.command_path(package_root, "build-provider/originals.mjs")?;
        let entry = match launch {
            data::LaunchObservation::NodePackage { entry } => {
                if !self.consumer_same(command.program.as_os_str(), runtime_program)? {
                    return Err(fail(self));
                }
                let entry = operand(entry).map_err(|_| fail(self))?;
                let expected = self.command_path(package_root, "bin/morphir.js")?;
                if !self.consumer_same(entry, expected.as_os_str())? {
                    return Err(fail(self));
                }
                Some(entry)
            }
            data::LaunchObservation::NativeExecutable { program, .. } => {
                let program = operand(program).map_err(|_| fail(self))?;
                if !self.consumer_same(command.program.as_os_str(), program)? {
                    return Err(fail(self));
                };
                None
            }
        };
        let InstalledProcessPurpose::Canonical {
            action_index,
            command: InstalledCommand::Publish,
        } = command.purpose
        else {
            return Err(fail(self));
        };
        let Some(InstalledClientAction::Run {
            command: InstalledCommand::Publish,
            arguments,
        }) = self.actions().nth(action_index)
        else {
            return Err(fail(self));
        };
        let expected = arguments
            .len()
            .checked_add(usize::from(entry.is_some()))
            .and_then(|n| n.checked_add(2))
            .ok_or_else(|| self.overflow_failure())?;
        if command.arguments.len() != expected {
            return Err(fail(self));
        }
        let prefix = usize::from(entry.is_some());
        if let Some(entry) = entry
            && !self.consumer_same(&command.arguments[0], entry)?
        {
            return Err(fail(self));
        }
        for (index, value) in arguments.iter().enumerate() {
            self.visit_observation_bytes(value.as_str().len())?;
            let expected = match value.as_str() {
                "$launchFile" => operand(&paths.launch_file),
                "$connectionFile" => operand(&paths.connection_file),
                "$sourceSelectionFile" => operand(&paths.source_selection_file),
                "$projectSelectionFile" => operand(&paths.project_selection_file),
                "$destination" => Ok(destination),
                "$verifiedNodeRuntime" => Ok(runtime_program),
                literal if !literal.starts_with('$') => Ok(OsStr::new(literal)),
                _ => return Err(fail(self)),
            }
            .map_err(|_| fail(self))?;
            if !self.consumer_same(&command.arguments[prefix + index], expected)? {
                return Err(fail(self));
            }
        }
        if !self.consumer_same(
            &command.arguments[expected - 2],
            OsStr::new("--originals-helper"),
        )? || !self.consumer_same(&command.arguments[expected - 1], helper.as_os_str())?
        {
            return Err(fail(self));
        }
        let runtime = self.copy_command_operand(runtime_program)?;
        let helper = self.copy_command_operand(helper.as_os_str())?;
        let directory = self.copy_command_operand(command.directory.as_os_str())?;
        let binding = match launch {
            data::LaunchObservation::NodePackage { .. } => ObservedLaunch::NodePackage {
                runtime,
                helper,
                directory,
            },
            data::LaunchObservation::NativeExecutable { .. } => ObservedLaunch::NativeExecutable {
                runtime,
                helper,
                directory,
            },
        };
        Ok(binding)
    }
}
