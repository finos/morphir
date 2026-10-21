//! Pure lexical launch selection. Paths are caller inputs, not inspected
//! artifacts, source provenance, filesystem grants or successful measurements.
use super::{RunArgs, adapter_selection::WorkbenchAdapter};
use clap::ValueEnum;
use morphir_mck::transport::process::{CommandSpec, CommandSpecError};
use morphir_mck::workbench::WorkbenchExecutionMode;
use morphir_mck::workbench::model_originals::installed::{InstalledClientAction, InstalledCommand};
use std::ffi::{OsStr, OsString};
use std::path::{Path, PathBuf};

#[derive(Debug, Clone, Copy, ValueEnum)]
pub(super) enum InstalledTarget {
    Node,
    Native,
}
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(in crate::commands) enum LaunchSelectionError {
    BuiltinArguments,
    WrongMode,
    MissingTarget,
    MissingPackage,
    MissingNode,
    MissingSourceCheckout,
    MissingProgram,
    ForbiddenProgram,
    RelativePath,
    NotCommand,
    UnknownPlaceholder,
    OutputBinding,
}
impl std::fmt::Display for LaunchSelectionError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(match self {
            Self::BuiltinArguments => "builtin:morphir-workbench does not accept --adapter-arg",
            Self::WrongMode => {
                "adapter and installed-client options require the matching explicit checker policy"
            }
            Self::MissingTarget => "installed client requires --installed-client-target",
            Self::MissingPackage => "installed client requires --installed-client-package",
            Self::MissingNode => "installed client requires --installed-client-node",
            Self::MissingSourceCheckout => {
                "installed client requires --installed-client-source-checkout"
            }
            Self::MissingProgram => "native installed client requires --installed-client-program",
            Self::ForbiddenProgram => "node installed client forbids --installed-client-program",
            Self::RelativePath => "installed launch paths must be absolute",
            Self::NotCommand => "compiled action is not an installed command",
            Self::UnknownPlaceholder => "compiled installed command has an unknown placeholder",
            Self::OutputBinding => {
                "installed output must be confined under the actual command directory"
            }
        })
    }
}
pub(in crate::commands) struct AbsoluteLaunchPath(PathBuf);
impl AbsoluteLaunchPath {
    pub(super) fn parse(path: PathBuf) -> Result<Self, LaunchSelectionError> {
        if !path.is_absolute() {
            return Err(LaunchSelectionError::RelativePath);
        }
        Ok(Self(path))
    }
    pub(in crate::commands) fn as_path(&self) -> &Path {
        &self.0
    }
}
pub(in crate::commands) enum InstalledLaunch {
    NodePackage {
        package: AbsoluteLaunchPath,
        node: AbsoluteLaunchPath,
        source_checkout: AbsoluteLaunchPath,
    },
    NativeExecutable {
        program: AbsoluteLaunchPath,
        package: AbsoluteLaunchPath,
        node: AbsoluteLaunchPath,
        source_checkout: AbsoluteLaunchPath,
    },
}
pub(super) enum WorkbenchLaunch<'a> {
    External {
        program: &'a OsStr,
        arguments: &'a [OsString],
    },
    NativeHost,
    InstalledClient(InstalledLaunch),
}
impl<'a> WorkbenchLaunch<'a> {
    pub(super) fn select(
        args: &'a RunArgs,
        mode: WorkbenchExecutionMode,
    ) -> Result<Self, LaunchSelectionError> {
        let adapter = WorkbenchAdapter::parse(&args.adapter, &args.adapter_args)
            .map_err(|_| LaunchSelectionError::BuiltinArguments)?;
        let any_installed = args.installed_client_target.is_some()
            || args.installed_client_package.is_some()
            || args.installed_client_node.is_some()
            || args.installed_client_program.is_some()
            || args.installed_client_source_checkout.is_some();
        if any_installed && mode != WorkbenchExecutionMode::InstalledOriginals {
            return Err(LaunchSelectionError::WrongMode);
        }
        match (adapter, mode) {
            (
                WorkbenchAdapter::External { program, arguments },
                WorkbenchExecutionMode::Historical | WorkbenchExecutionMode::ModelOriginals,
            ) => Ok(Self::External { program, arguments }),
            (WorkbenchAdapter::BuiltinNativeWorkbench, WorkbenchExecutionMode::NativeOriginals) => {
                Ok(Self::NativeHost)
            }
            (
                WorkbenchAdapter::BuiltinNativeWorkbench,
                WorkbenchExecutionMode::InstalledOriginals,
            ) => {
                let target = args
                    .installed_client_target
                    .ok_or(LaunchSelectionError::MissingTarget)?;
                let package = required(
                    args.installed_client_package.as_ref(),
                    LaunchSelectionError::MissingPackage,
                )?;
                let node = required(
                    args.installed_client_node.as_ref(),
                    LaunchSelectionError::MissingNode,
                )?;
                let source_checkout = required(
                    args.installed_client_source_checkout.as_ref(),
                    LaunchSelectionError::MissingSourceCheckout,
                )?;
                let launch = match target {
                    InstalledTarget::Node => {
                        if args.installed_client_program.is_some() {
                            return Err(LaunchSelectionError::ForbiddenProgram);
                        }
                        InstalledLaunch::NodePackage {
                            package,
                            node,
                            source_checkout,
                        }
                    }
                    InstalledTarget::Native => InstalledLaunch::NativeExecutable {
                        program: required(
                            args.installed_client_program.as_ref(),
                            LaunchSelectionError::MissingProgram,
                        )?,
                        package,
                        node,
                        source_checkout,
                    },
                };
                Ok(Self::InstalledClient(launch))
            }
            _ => Err(LaunchSelectionError::WrongMode),
        }
    }
}
fn required(
    path: Option<&PathBuf>,
    missing: LaunchSelectionError,
) -> Result<AbsoluteLaunchPath, LaunchSelectionError> {
    AbsoluteLaunchPath::parse(path.ok_or(missing)?.clone())
}
/// Caller-selected process settings, borrowed until the SAME funded spec is built.
pub(in crate::commands) struct InstalledInvocationSettings<'a> {
    directory: &'a Path,
    environment: &'a [(OsString, OsString)],
    limits: morphir_mck::transport::Limits,
}
impl<'a> InstalledInvocationSettings<'a> {
    pub(in crate::commands) fn new(
        directory: &'a Path,
        environment: &'a [(OsString, OsString)],
        limits: morphir_mck::transport::Limits,
    ) -> Self {
        Self {
            directory,
            environment,
            limits,
        }
    }
}
pub(in crate::commands) struct InstalledCommandPaths {
    launch: AbsoluteLaunchPath,
    connection: AbsoluteLaunchPath,
    source: AbsoluteLaunchPath,
    project: AbsoluteLaunchPath,
    destination: Destination,
}
enum Destination {
    LexicalAbsolute(AbsoluteLaunchPath),
    Confined {
        directory: AbsoluteLaunchPath,
        relative: PathBuf,
        target: AbsoluteLaunchPath,
    },
}
impl InstalledCommandPaths {
    pub(in crate::commands) fn launch_file(&self) -> &Path {
        self.launch.as_path()
    }
    pub(in crate::commands) fn connection_file(&self) -> &Path {
        self.connection.as_path()
    }
    pub(in crate::commands) fn source_file(&self) -> &Path {
        self.source.as_path()
    }
    pub(in crate::commands) fn project_file(&self) -> &Path {
        self.project.as_path()
    }
    pub(in crate::commands) fn destination(&self) -> &Path {
        match &self.destination {
            Destination::LexicalAbsolute(path) => path.as_path(),
            Destination::Confined { target, .. } => target.as_path(),
        }
    }
    pub(in crate::commands) fn destination_argument(&self) -> &OsStr {
        match &self.destination {
            Destination::LexicalAbsolute(path) => path.as_path().as_os_str(),
            Destination::Confined { relative, .. } => relative.as_os_str(),
        }
    }
    pub(in crate::commands) fn new_confined(
        launch: PathBuf,
        connection: PathBuf,
        source: PathBuf,
        project: PathBuf,
        directory: PathBuf,
        relative: PathBuf,
        target: PathBuf,
    ) -> Result<Self, LaunchSelectionError> {
        let directory = AbsoluteLaunchPath::parse(directory)?;
        let target = AbsoluteLaunchPath::parse(target)?;
        if relative.as_os_str().is_empty()
            || relative
                .components()
                .any(|part| !matches!(part, std::path::Component::Normal(_)))
            || target.as_path().strip_prefix(directory.as_path()).ok() != Some(relative.as_path())
        {
            return Err(LaunchSelectionError::OutputBinding);
        }
        Ok(Self {
            launch: AbsoluteLaunchPath::parse(launch)?,
            connection: AbsoluteLaunchPath::parse(connection)?,
            source: AbsoluteLaunchPath::parse(source)?,
            project: AbsoluteLaunchPath::parse(project)?,
            destination: Destination::Confined {
                directory,
                relative,
                target,
            },
        })
    }
    fn borrowed_operand<'a>(
        &'a self,
        argument: &'a str,
        node: &'a Path,
    ) -> Result<&'a OsStr, LaunchSelectionError> {
        Ok(match argument {
            "$launchFile" => self.launch.as_path().as_os_str(),
            "$connectionFile" => self.connection.as_path().as_os_str(),
            "$sourceSelectionFile" => self.source.as_path().as_os_str(),
            "$projectSelectionFile" => self.project.as_path().as_os_str(),
            "$destination" => self.destination_argument(),
            "$verifiedNodeRuntime" => node.as_os_str(),
            literal if !literal.starts_with('$') => OsStr::new(literal),
            _ => return Err(LaunchSelectionError::UnknownPlaceholder),
        })
    }
    pub(in crate::commands) fn new(
        launch: PathBuf,
        connection: PathBuf,
        source: PathBuf,
        project: PathBuf,
        destination: PathBuf,
    ) -> Result<Self, LaunchSelectionError> {
        Ok(Self {
            launch: AbsoluteLaunchPath::parse(launch)?,
            connection: AbsoluteLaunchPath::parse(connection)?,
            source: AbsoluteLaunchPath::parse(source)?,
            project: AbsoluteLaunchPath::parse(project)?,
            destination: Destination::LexicalAbsolute(AbsoluteLaunchPath::parse(destination)?),
        })
    }
    fn operand(
        &self,
        argument: &str,
        node: &AbsoluteLaunchPath,
    ) -> Result<OsString, LaunchSelectionError> {
        Ok(self.borrowed_operand(argument, node.as_path())?.to_owned())
    }
}
pub(super) struct CanonicalInstalledCommand {
    program: PathBuf,
    arguments: Vec<OsString>,
}
impl CanonicalInstalledCommand {
    pub(super) fn program(&self) -> &Path {
        &self.program
    }
    pub(super) fn arguments(&self) -> &[OsString] {
        &self.arguments
    }
    pub(super) fn into_spec(
        self,
        directory: PathBuf,
        environment: Vec<(OsString, OsString)>,
    ) -> Result<CommandSpec, CommandSpecError> {
        CommandSpec::new(self.program, self.arguments, directory, environment)
    }
}
impl InstalledLaunch {
    pub(in crate::commands) fn package(&self) -> &Path {
        match self {
            Self::NodePackage { package, .. } | Self::NativeExecutable { package, .. } => {
                package.as_path()
            }
        }
    }
    pub(in crate::commands) fn node(&self) -> &Path {
        match self {
            Self::NodePackage { node, .. } | Self::NativeExecutable { node, .. } => node.as_path(),
        }
    }
    pub(in crate::commands) fn source_checkout(&self) -> &Path {
        match self {
            Self::NodePackage {
                source_checkout, ..
            }
            | Self::NativeExecutable {
                source_checkout, ..
            } => source_checkout.as_path(),
        }
    }
    pub(in crate::commands) fn spawn(
        &self,
        index: usize,
        action: InstalledClientAction<'_>,
        paths: &InstalledCommandPaths,
        run: &mut morphir_mck::workbench::model_originals::installed::InstalledClientRun<'_>,
        invocation: InstalledInvocationSettings<'_>,
    ) -> Result<
        morphir_mck::workbench::model_originals::installed::RunningInstalledProcess,
        morphir_mck::workbench::model_originals::installed::InstalledAdapterError,
    > {
        use morphir_mck::workbench::model_originals::installed::{
            InstalledAdapterError, InstalledProcessPurpose,
        };
        let InstalledInvocationSettings {
            directory,
            environment,
            limits,
        } = invocation;
        let Destination::Confined {
            directory: expected,
            ..
        } = &paths.destination
        else {
            return Err(InstalledAdapterError::ObservationIncomplete);
        };
        run.visit_observation_bytes(
            directory
                .as_os_str()
                .len()
                .saturating_add(expected.as_path().as_os_str().len()),
        )?;
        if directory != expected.as_path() {
            return Err(InstalledAdapterError::ObservationIncomplete);
        }
        let InstalledClientAction::Run { command, arguments } = action else {
            return Err(InstalledAdapterError::ObservationIncomplete);
        };
        // Validate every source operand before constructing the actual spec.
        for argument in arguments {
            paths
                .borrowed_operand(argument.as_str(), self.node())
                .map_err(|_| InstalledAdapterError::ObservationIncomplete)?;
        }
        let entry = match self {
            Self::NodePackage { .. } => Some(run.command_path(self.package(), "bin/morphir.js")?),
            Self::NativeExecutable { .. } => None,
        };
        let (flag, member) = match command {
            InstalledCommand::Connect => ("--connected-helper", "build-provider/connected.mjs"),
            InstalledCommand::List | InstalledCommand::Publish => {
                ("--originals-helper", "build-provider/originals.mjs")
            }
        };
        let helper = run.command_path(self.package(), member)?;
        let prefix = usize::from(entry.is_some());
        let values = (0..arguments.len() + prefix + 2).map(|position| {
            if let Some(entry) = entry.as_ref().filter(|_| position == 0) {
                return entry.as_os_str();
            }
            let offset = position - prefix;
            if offset < arguments.len() {
                // The exact same lexical resolver was checked above; unknown
                // placeholders cannot reach this infallible borrowed iterator.
                paths
                    .borrowed_operand(arguments[offset].as_str(), self.node())
                    .expect("immutable source operand was validated before spec construction")
            } else if offset == arguments.len() {
                OsStr::new(flag)
            } else {
                helper.as_os_str()
            }
        });
        let program = match self {
            Self::NodePackage { node, .. } => node.as_path(),
            Self::NativeExecutable { program, .. } => program.as_path(),
        };
        run.spawn_process(
            InstalledProcessPurpose::Canonical {
                action_index: index,
                command,
            },
            program,
            values,
            directory,
            environment,
            limits,
        )
    }
    pub(in crate::commands) fn spawn_observed_publish(
        &self,
        index: usize,
        paths: &InstalledCommandPaths,
        run: &mut morphir_mck::workbench::model_originals::installed::InstalledClientRun<'_>,
        invocation: InstalledInvocationSettings<'_>,
        implementation: morphir_mck::workbench::model_originals::installed::data::ImplementationObservation,
        end: std::time::Instant,
    ) -> Result<
        (
            morphir_mck::workbench::model_originals::installed::RunningInstalledProcess,
            morphir_mck::workbench::model_originals::installed::InstalledConsumerPorts,
        ),
        morphir_mck::workbench::model_originals::installed::InstalledAdapterError,
    > {
        use morphir_mck::workbench::model_originals::installed::{
            ConsumerProcessCommand, InstalledAdapterError, InstalledProcessPurpose,
        };
        let InstalledInvocationSettings {
            directory,
            environment,
            limits,
        } = invocation;
        let Destination::Confined {
            directory: expected,
            ..
        } = &paths.destination
        else {
            return Err(InstalledAdapterError::ObservationIncomplete);
        };
        run.visit_observation_bytes(
            directory
                .as_os_str()
                .len()
                .saturating_add(expected.as_path().as_os_str().len()),
        )?;
        if directory != expected.as_path() {
            return Err(InstalledAdapterError::ObservationIncomplete);
        }
        let Some(InstalledClientAction::Run {
            command: InstalledCommand::Publish,
            arguments,
        }) = run.actions().nth(index)
        else {
            return Err(InstalledAdapterError::ObservationIncomplete);
        };
        // The same borrowed resolver validates every operand before allocation.
        for argument in arguments {
            paths
                .borrowed_operand(argument.as_str(), self.node())
                .map_err(|_| InstalledAdapterError::ObservationIncomplete)?;
        }
        let entry = match self {
            Self::NodePackage { .. } => Some(run.command_path(self.package(), "bin/morphir.js")?),
            Self::NativeExecutable { .. } => None,
        };
        let helper = run.command_path(self.package(), "build-provider/originals.mjs")?;
        let prefix = usize::from(entry.is_some());
        let values = (0..arguments.len() + prefix + 2).map(|position| {
            if let Some(entry) = entry.as_ref().filter(|_| position == 0) {
                return entry.as_os_str();
            }
            let offset = position - prefix;
            if offset < arguments.len() {
                paths
                    .borrowed_operand(arguments[offset].as_str(), self.node())
                    .expect("immutable source operand was validated before spec construction")
            } else if offset == arguments.len() {
                OsStr::new("--originals-helper")
            } else {
                helper.as_os_str()
            }
        });
        let arguments = run.copy_command_arguments(values)?;
        let program = match self {
            Self::NodePackage { node, .. } => node.as_path(),
            Self::NativeExecutable { program, .. } => program.as_path(),
        };
        let (prepared, ports) = run.prepare_retained_consumer_operation(
            ConsumerProcessCommand {
                purpose: InstalledProcessPurpose::Canonical {
                    action_index: index,
                    command: InstalledCommand::Publish,
                },
                program,
                arguments: &arguments,
                directory,
                environment,
                limits,
            },
            end,
            implementation,
        )?;
        let process = run.spawn_prepared_consumer_process(prepared)?;
        Ok((process, ports))
    }
    pub(super) fn command(
        &self,
        action: InstalledClientAction<'_>,
        paths: &InstalledCommandPaths,
    ) -> Result<CanonicalInstalledCommand, LaunchSelectionError> {
        let InstalledClientAction::Run { command, arguments } = action else {
            return Err(LaunchSelectionError::NotCommand);
        };
        let (program, package, node, mut resolved) = match self {
            Self::NodePackage { package, node, .. } => (
                node.as_path(),
                package,
                node,
                vec![package.as_path().join("bin/morphir.js").into_os_string()],
            ),
            Self::NativeExecutable {
                program,
                package,
                node,
                ..
            } => (program.as_path(), package, node, Vec::new()),
        };
        for argument in arguments {
            resolved.push(paths.operand(argument.as_str(), node)?);
        }
        let (flag, member) = match command {
            InstalledCommand::Connect => ("--connected-helper", "build-provider/connected.mjs"),
            InstalledCommand::List | InstalledCommand::Publish => {
                ("--originals-helper", "build-provider/originals.mjs")
            }
        };
        resolved.push(flag.into());
        resolved.push(package.as_path().join(member).into_os_string());
        Ok(CanonicalInstalledCommand {
            program: program.to_owned(),
            arguments: resolved,
        })
    }
}
