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
pub(super) enum LaunchSelectionError {
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
        })
    }
}
pub(super) struct AbsoluteLaunchPath(PathBuf);
impl AbsoluteLaunchPath {
    pub(super) fn parse(path: PathBuf) -> Result<Self, LaunchSelectionError> {
        if !path.is_absolute() {
            return Err(LaunchSelectionError::RelativePath);
        }
        Ok(Self(path))
    }
    pub(super) fn as_path(&self) -> &Path {
        &self.0
    }
}
pub(super) enum InstalledLaunch {
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
pub(super) struct InstalledCommandPaths {
    launch: AbsoluteLaunchPath,
    connection: AbsoluteLaunchPath,
    source: AbsoluteLaunchPath,
    project: AbsoluteLaunchPath,
    destination: AbsoluteLaunchPath,
}
impl InstalledCommandPaths {
    pub(super) fn new(
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
            destination: AbsoluteLaunchPath::parse(destination)?,
        })
    }
    fn operand(
        &self,
        argument: &str,
        node: &AbsoluteLaunchPath,
    ) -> Result<OsString, LaunchSelectionError> {
        let path = match argument {
            "$launchFile" => &self.launch,
            "$connectionFile" => &self.connection,
            "$sourceSelectionFile" => &self.source,
            "$projectSelectionFile" => &self.project,
            "$destination" => &self.destination,
            "$verifiedNodeRuntime" => node,
            literal if !literal.starts_with('$') => return Ok(literal.into()),
            _ => return Err(LaunchSelectionError::UnknownPlaceholder),
        };
        Ok(path.as_path().as_os_str().to_owned())
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
