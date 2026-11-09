///|
/// Command payloads have distinct types; a sender cannot accept another command.
priv struct RunRequest(Cli)

///|
priv struct ExecuteRequest(Cli)

///|
priv struct VerifyRequest(Cli)

///|
priv struct ConformRequest(Cli)

///|
priv struct EvalRequest(Cli)

///|
priv struct WorksheetRequest(Cli)

///|
priv struct CompileRequest(Cli)

///|
priv struct VersionRequest(Cli)

///|
priv struct GenerateRequest(Cli)

///|
priv struct ModelInspectRequest(Cli)

///|
priv struct ModelExportOriginalRequest(Cli)

///|
priv struct NotebookExportRequest(Cli)

///|
priv struct NotebookImportRequest(Cli)

///|
priv struct ConnectedConnectRequest(Cli)

///|
priv struct ConnectedRunRequest(Cli)

///|
priv struct ConnectedArtifactsRequest(Cli)

///|
priv struct ConnectedOriginalsRequest(Cli)

///|
priv struct WorkspaceRequest(Cli)

///|
priv struct WorkspaceInitRequest(Cli)

///|
priv struct ProjectListRequest(Cli)

///|
priv struct ProjectAddRequest(Cli)

///|
priv struct ProjectRemoveRequest(Cli)

///|
priv struct ToolchainInfoRequest(Cli)

///|
priv struct ToolchainSetupRequest(Cli)

///|
priv struct ToolchainBuildRequest(Cli)

///|
priv struct ToolchainRunRequest(Cli)

///|
priv struct ToolchainExecRequest(Cli)

///|
priv struct MckRequest(Cli)

///|
priv struct ExtensionDescribeRequest(Cli)

///|
priv struct ExtensionCompileRequest(Cli)

///|
priv struct ExtensionGenerateRequest(Cli)

///|
priv struct ExtensionBundleRequest(Cli)

///|
priv struct ExtensionInstallRequest(Cli)

///|
priv struct ExtensionListRequest(Cli)

///|
priv struct ExtensionSearchRequest(Cli)

///|
priv struct ExtensionUpdateRequest(Cli)

///|
priv struct ExtensionUninstallRequest(Cli)

///|
priv struct ExtensionRepositoryInitRequest(Cli)

///|
priv struct ExtensionRepositoryAddRequest(Cli)

///|
priv struct ExtensionRepositoryListRequest(Cli)

///|
priv struct ExtensionRepositoryInspectRequest(Cli)

///|
priv struct ExtensionRepositoryEnableRequest(Cli)

///|
priv struct ExtensionRepositoryDisableRequest(Cli)

///|
priv struct ExtensionRepositoryRemoveRequest(Cli)

///|
priv struct ExtensionRepositoryPublishRequest(Cli)

///|
priv struct ExtensionRepositoryVerifyRequest(Cli)

///|
priv enum CommandRequest {
  RunCommand(RunRequest)
  ExecuteCommand(ExecuteRequest)
  VerifyCommand(VerifyRequest)
  ConformCommand(ConformRequest)
  EvalCommand(EvalRequest)
  WorksheetCommand(WorksheetRequest)
  CompileCommand(CompileRequest)
  VersionCommand(VersionRequest)
  GenerateCommand(GenerateRequest)
  ModelInspectCommand(ModelInspectRequest)
  ModelExportOriginalCommand(ModelExportOriginalRequest)
  NotebookExportCommand(NotebookExportRequest)
  NotebookImportCommand(NotebookImportRequest)
  ConnectedConnectCommand(ConnectedConnectRequest)
  ConnectedRunCommand(ConnectedRunRequest)
  ConnectedArtifactsCommand(ConnectedArtifactsRequest)
  ConnectedOriginalsCommand(ConnectedOriginalsRequest)
  WorkspaceCommand(WorkspaceRequest)
  WorkspaceInitCommand(WorkspaceInitRequest)
  ProjectListCommand(ProjectListRequest)
  ProjectAddCommand(ProjectAddRequest)
  ProjectRemoveCommand(ProjectRemoveRequest)
  ToolchainInfoCommand(ToolchainInfoRequest)
  ToolchainSetupCommand(ToolchainSetupRequest)
  ToolchainBuildCommand(ToolchainBuildRequest)
  ToolchainRunCommand(ToolchainRunRequest)
  ToolchainExecCommand(ToolchainExecRequest)
  MckCommand(MckRequest)
  ExtensionDescribeCommand(ExtensionDescribeRequest)
  ExtensionCompileCommand(ExtensionCompileRequest)
  ExtensionGenerateCommand(ExtensionGenerateRequest)
  ExtensionBundleCommand(ExtensionBundleRequest)
  ExtensionInstallCommand(ExtensionInstallRequest)
  ExtensionListCommand(ExtensionListRequest)
  ExtensionSearchCommand(ExtensionSearchRequest)
  ExtensionUpdateCommand(ExtensionUpdateRequest)
  ExtensionUninstallCommand(ExtensionUninstallRequest)
  ExtensionRepositoryInitCommand(ExtensionRepositoryInitRequest)
  ExtensionRepositoryAddCommand(ExtensionRepositoryAddRequest)
  ExtensionRepositoryListCommand(ExtensionRepositoryListRequest)
  ExtensionRepositoryInspectCommand(ExtensionRepositoryInspectRequest)
  ExtensionRepositoryEnableCommand(ExtensionRepositoryEnableRequest)
  ExtensionRepositoryDisableCommand(ExtensionRepositoryDisableRequest)
  ExtensionRepositoryRemoveCommand(ExtensionRepositoryRemoveRequest)
  ExtensionRepositoryPublishCommand(ExtensionRepositoryPublishRequest)
  ExtensionRepositoryVerifyCommand(ExtensionRepositoryVerifyRequest)
}

///|
fn CommandRequest::decode(cli : Cli) -> CommandRequest raise {
  match cli.command {
    "run" => RunCommand(RunRequest(cli))
    "execute" => ExecuteCommand(ExecuteRequest(cli))
    "verify" => VerifyCommand(VerifyRequest(cli))
    "conform" => ConformCommand(ConformRequest(cli))
    "eval" => EvalCommand(EvalRequest(cli))
    "worksheet" => WorksheetCommand(WorksheetRequest(cli))
    "compile" => CompileCommand(CompileRequest(cli))
    "version" => VersionCommand(VersionRequest(cli))
    "generate" => GenerateCommand(GenerateRequest(cli))
    "model inspect" => ModelInspectCommand(ModelInspectRequest(cli))
    "model export-original" =>
      ModelExportOriginalCommand(ModelExportOriginalRequest(cli))
    "notebook export" => NotebookExportCommand(NotebookExportRequest(cli))
    "notebook import" => NotebookImportCommand(NotebookImportRequest(cli))
    "connected connect" => ConnectedConnectCommand(ConnectedConnectRequest(cli))
    "connected run" => ConnectedRunCommand(ConnectedRunRequest(cli))
    "connected artifacts" =>
      ConnectedArtifactsCommand(ConnectedArtifactsRequest(cli))
    "connected originals" =>
      ConnectedOriginalsCommand(ConnectedOriginalsRequest(cli))
    "workspace" => WorkspaceCommand(WorkspaceRequest(cli))
    "workspace init" => WorkspaceInitCommand(WorkspaceInitRequest(cli))
    "project list" => ProjectListCommand(ProjectListRequest(cli))
    "project add" => ProjectAddCommand(ProjectAddRequest(cli))
    "project remove" => ProjectRemoveCommand(ProjectRemoveRequest(cli))
    "toolchain info" => ToolchainInfoCommand(ToolchainInfoRequest(cli))
    "toolchain setup" => ToolchainSetupCommand(ToolchainSetupRequest(cli))
    "toolchain build" => ToolchainBuildCommand(ToolchainBuildRequest(cli))
    "toolchain run" => ToolchainRunCommand(ToolchainRunRequest(cli))
    "toolchain exec" => ToolchainExecCommand(ToolchainExecRequest(cli))
    "mck" => MckCommand(MckRequest(cli))
    "extension describe" =>
      ExtensionDescribeCommand(ExtensionDescribeRequest(cli))
    "extension compile" => ExtensionCompileCommand(ExtensionCompileRequest(cli))
    "extension generate" =>
      ExtensionGenerateCommand(ExtensionGenerateRequest(cli))
    "extension bundle" => ExtensionBundleCommand(ExtensionBundleRequest(cli))
    "extension install" => ExtensionInstallCommand(ExtensionInstallRequest(cli))
    "extension list" => ExtensionListCommand(ExtensionListRequest(cli))
    "extension search" => ExtensionSearchCommand(ExtensionSearchRequest(cli))
    "extension update" => ExtensionUpdateCommand(ExtensionUpdateRequest(cli))
    "extension uninstall" =>
      ExtensionUninstallCommand(ExtensionUninstallRequest(cli))
    "extension repository init" =>
      ExtensionRepositoryInitCommand(ExtensionRepositoryInitRequest(cli))
    "extension repository add" =>
      ExtensionRepositoryAddCommand(ExtensionRepositoryAddRequest(cli))
    "extension repository list" =>
      ExtensionRepositoryListCommand(ExtensionRepositoryListRequest(cli))
    "extension repository inspect" =>
      ExtensionRepositoryInspectCommand(ExtensionRepositoryInspectRequest(cli))
    "extension repository enable" =>
      ExtensionRepositoryEnableCommand(ExtensionRepositoryEnableRequest(cli))
    "extension repository disable" =>
      ExtensionRepositoryDisableCommand(ExtensionRepositoryDisableRequest(cli))
    "extension repository remove" =>
      ExtensionRepositoryRemoveCommand(ExtensionRepositoryRemoveRequest(cli))
    "extension repository publish" =>
      ExtensionRepositoryPublishCommand(ExtensionRepositoryPublishRequest(cli))
    "extension repository verify" =>
      ExtensionRepositoryVerifyCommand(ExtensionRepositoryVerifyRequest(cli))
    _ => raise @config.Invalid("Unknown command: " + cli.command)
  }
}

///|
let run_sender : @mediator_async.Sender[CommandContext, RunRequest, Int32] = command_sender(
  "run",
  (context, request) => {
    let RunRequest(cli) = request
    pipeline_command(cli, context.mode, PipelineRun)
  },
)

///|
let execute_sender : @mediator_async.Sender[
  CommandContext,
  ExecuteRequest,
  Int32,
] = command_sender("execute", (context, request) => {
  let ExecuteRequest(cli) = request
  execution_command(cli, context.mode)
})

///|
let verify_sender : @mediator_async.Sender[CommandContext, VerifyRequest, Int32] = command_sender(
  "verify",
  (context, request) => {
    let VerifyRequest(cli) = request
    execution_command(cli, context.mode)
  },
)

///|
let conform_sender : @mediator_async.Sender[
  CommandContext,
  ConformRequest,
  Int32,
] = command_sender("conform", (context, request) => {
  let ConformRequest(cli) = request
  execution_command(cli, context.mode)
})

///|
let eval_sender : @mediator_async.Sender[CommandContext, EvalRequest, Int32] = command_sender(
  "eval",
  (context, request) => {
    let EvalRequest(cli) = request
    evaluation_command(cli, context.mode)
  },
)

///|
let worksheet_sender : @mediator_async.Sender[
  CommandContext,
  WorksheetRequest,
  Int32,
] = command_sender("worksheet", (context, request) => {
  let WorksheetRequest(cli) = request
  worksheet_command(cli, context.mode)
})

///|
let compile_sender : @mediator_async.Sender[
  CommandContext,
  CompileRequest,
  Int32,
] = command_sender("compile", (context, request) => {
  let CompileRequest(cli) = request
  pipeline_command(compilation_cli(cli), context.mode, PipelineCompile)
})

///|
let version_sender : @mediator_async.Sender[
  CommandContext,
  VersionRequest,
  Int32,
] = command_sender("version", (context, request) => {
  let VersionRequest(_) = request
  version_command(context.mode)
})

///|
let generate_sender : @mediator_async.Sender[
  CommandContext,
  GenerateRequest,
  Int32,
] = command_sender("generate", (context, request) => {
  let GenerateRequest(cli) = request
  generation_command(cli, context.mode)
})

///|
let model_inspect_sender : @mediator_async.Sender[
  CommandContext,
  ModelInspectRequest,
  Int32,
] = command_sender("model inspect", (context, request) => {
  let ModelInspectRequest(cli) = request
  model_command(cli, context.mode)
})

///|
let model_export_original_sender : @mediator_async.Sender[
  CommandContext,
  ModelExportOriginalRequest,
  Int32,
] = command_sender("model export-original", (context, request) => {
  let ModelExportOriginalRequest(cli) = request
  model_command(cli, context.mode)
})

///|
let notebook_export_sender : @mediator_async.Sender[
  CommandContext,
  NotebookExportRequest,
  Int32,
] = command_sender("notebook export", (context, request) => {
  let NotebookExportRequest(cli) = request
  notebook_command(cli, context.mode)
})

///|
let notebook_import_sender : @mediator_async.Sender[
  CommandContext,
  NotebookImportRequest,
  Int32,
] = command_sender("notebook import", (context, request) => {
  let NotebookImportRequest(cli) = request
  notebook_command(cli, context.mode)
})

///|
let connected_connect_sender : @mediator_async.Sender[
  CommandContext,
  ConnectedConnectRequest,
  Int32,
] = command_sender("connected connect", (context, request) => {
  let ConnectedConnectRequest(cli) = request
  connected_command(cli, context.mode)
})

///|
let connected_run_sender : @mediator_async.Sender[
  CommandContext,
  ConnectedRunRequest,
  Int32,
] = command_sender("connected run", (context, request) => {
  let ConnectedRunRequest(cli) = request
  connected_command(cli, context.mode)
})

///|
let connected_artifacts_sender : @mediator_async.Sender[
  CommandContext,
  ConnectedArtifactsRequest,
  Int32,
] = command_sender("connected artifacts", (context, request) => {
  let ConnectedArtifactsRequest(cli) = request
  transfer_command(cli, context.mode)
})

///|
let connected_originals_sender : @mediator_async.Sender[
  CommandContext,
  ConnectedOriginalsRequest,
  Int32,
] = command_sender("connected originals", (context, request) => {
  let ConnectedOriginalsRequest(cli) = request
  originals_command(cli, context.mode)
})

///|
let workspace_sender : @mediator_async.Sender[
  CommandContext,
  WorkspaceRequest,
  Int32,
] = command_sender("workspace", (context, request) => {
  let WorkspaceRequest(cli) = request
  pipeline_command(cli, context.mode, WorkspaceOverview)
})

///|
let workspace_init_sender : @mediator_async.Sender[
  CommandContext,
  WorkspaceInitRequest,
  Int32,
] = command_sender("workspace init", (context, request) => {
  let WorkspaceInitRequest(cli) = request
  scaffolding_command(cli, context.mode)
})

///|
let project_list_sender : @mediator_async.Sender[
  CommandContext,
  ProjectListRequest,
  Int32,
] = command_sender("project list", (context, request) => {
  let ProjectListRequest(cli) = request
  pipeline_command(cli, context.mode, ListProjects)
})

///|
let project_add_sender : @mediator_async.Sender[
  CommandContext,
  ProjectAddRequest,
  Int32,
] = command_sender("project add", (context, request) => {
  let ProjectAddRequest(cli) = request
  scaffolding_command(cli, context.mode)
})

///|
let project_remove_sender : @mediator_async.Sender[
  CommandContext,
  ProjectRemoveRequest,
  Int32,
] = command_sender("project remove", (context, request) => {
  let ProjectRemoveRequest(cli) = request
  scaffolding_command(cli, context.mode)
})

///|
let toolchain_info_sender : @mediator_async.Sender[
  CommandContext,
  ToolchainInfoRequest,
  Int32,
] = command_sender("toolchain info", (context, request) => {
  let ToolchainInfoRequest(cli) = request
  toolchain_command(cli, context.mode)
})

///|
let toolchain_setup_sender : @mediator_async.Sender[
  CommandContext,
  ToolchainSetupRequest,
  Int32,
] = command_sender("toolchain setup", (context, request) => {
  let ToolchainSetupRequest(cli) = request
  toolchain_command(cli, context.mode)
})

///|
let toolchain_build_sender : @mediator_async.Sender[
  CommandContext,
  ToolchainBuildRequest,
  Int32,
] = command_sender("toolchain build", (context, request) => {
  let ToolchainBuildRequest(cli) = request
  toolchain_command(cli, context.mode)
})

///|
let toolchain_run_sender : @mediator_async.Sender[
  CommandContext,
  ToolchainRunRequest,
  Int32,
] = command_sender("toolchain run", (context, request) => {
  let ToolchainRunRequest(cli) = request
  toolchain_command(cli, context.mode)
})

///|
let toolchain_exec_sender : @mediator_async.Sender[
  CommandContext,
  ToolchainExecRequest,
  Int32,
] = command_sender("toolchain exec", (context, request) => {
  let ToolchainExecRequest(cli) = request
  toolchain_command(cli, context.mode)
})

///|
let mck_sender : @mediator_async.Sender[CommandContext, MckRequest, Int32] = command_sender(
  "mck",
  (context, request) => {
    let MckRequest(cli) = request
    mck_command(cli, context.mode)
  },
)

///|
let extension_describe_sender : @mediator_async.Sender[
  CommandContext,
  ExtensionDescribeRequest,
  Int32,
] = async_command_sender("extension describe", (context, request) => {
  let ExtensionDescribeRequest(cli) = request
  extension_command(cli, context)
})

///|
let extension_compile_sender : @mediator_async.Sender[
  CommandContext,
  ExtensionCompileRequest,
  Int32,
] = async_command_sender("extension compile", (context, request) => {
  let ExtensionCompileRequest(cli) = request
  extension_command(cli, context)
})

///|
let extension_generate_sender : @mediator_async.Sender[
  CommandContext,
  ExtensionGenerateRequest,
  Int32,
] = async_command_sender("extension generate", (context, request) => {
  let ExtensionGenerateRequest(cli) = request
  extension_command(cli, context)
})

///|
let extension_bundle_sender : @mediator_async.Sender[
  CommandContext,
  ExtensionBundleRequest,
  Int32,
] = command_sender("extension bundle", (context, request) => {
  let ExtensionBundleRequest(cli) = request
  catalog_command(cli, context.mode)
})

///|
let extension_install_sender : @mediator_async.Sender[
  CommandContext,
  ExtensionInstallRequest,
  Int32,
] = command_sender("extension install", (context, request) => {
  let ExtensionInstallRequest(cli) = request
  catalog_command(cli, context.mode)
})

///|
let extension_list_sender : @mediator_async.Sender[
  CommandContext,
  ExtensionListRequest,
  Int32,
] = command_sender("extension list", (context, request) => {
  let ExtensionListRequest(cli) = request
  catalog_command(cli, context.mode)
})

///|
let extension_search_sender : @mediator_async.Sender[
  CommandContext,
  ExtensionSearchRequest,
  Int32,
] = command_sender("extension search", (context, request) => {
  let ExtensionSearchRequest(cli) = request
  catalog_command(cli, context.mode)
})

///|
let extension_update_sender : @mediator_async.Sender[
  CommandContext,
  ExtensionUpdateRequest,
  Int32,
] = command_sender("extension update", (context, request) => {
  let ExtensionUpdateRequest(cli) = request
  catalog_command(cli, context.mode)
})

///|
let extension_uninstall_sender : @mediator_async.Sender[
  CommandContext,
  ExtensionUninstallRequest,
  Int32,
] = command_sender("extension uninstall", (context, request) => {
  let ExtensionUninstallRequest(cli) = request
  catalog_command(cli, context.mode)
})

///|
let extension_repository_init_sender : @mediator_async.Sender[
  CommandContext,
  ExtensionRepositoryInitRequest,
  Int32,
] = command_sender("extension repository init", (context, request) => {
  let ExtensionRepositoryInitRequest(cli) = request
  catalog_command(cli, context.mode)
})

///|
let extension_repository_add_sender : @mediator_async.Sender[
  CommandContext,
  ExtensionRepositoryAddRequest,
  Int32,
] = command_sender("extension repository add", (context, request) => {
  let ExtensionRepositoryAddRequest(cli) = request
  catalog_command(cli, context.mode)
})

///|
let extension_repository_list_sender : @mediator_async.Sender[
  CommandContext,
  ExtensionRepositoryListRequest,
  Int32,
] = command_sender("extension repository list", (context, request) => {
  let ExtensionRepositoryListRequest(cli) = request
  catalog_command(cli, context.mode)
})

///|
let extension_repository_inspect_sender : @mediator_async.Sender[
  CommandContext,
  ExtensionRepositoryInspectRequest,
  Int32,
] = command_sender("extension repository inspect", (context, request) => {
  let ExtensionRepositoryInspectRequest(cli) = request
  catalog_command(cli, context.mode)
})

///|
let extension_repository_enable_sender : @mediator_async.Sender[
  CommandContext,
  ExtensionRepositoryEnableRequest,
  Int32,
] = command_sender("extension repository enable", (context, request) => {
  let ExtensionRepositoryEnableRequest(cli) = request
  catalog_command(cli, context.mode)
})

///|
let extension_repository_disable_sender : @mediator_async.Sender[
  CommandContext,
  ExtensionRepositoryDisableRequest,
  Int32,
] = command_sender("extension repository disable", (context, request) => {
  let ExtensionRepositoryDisableRequest(cli) = request
  catalog_command(cli, context.mode)
})

///|
let extension_repository_remove_sender : @mediator_async.Sender[
  CommandContext,
  ExtensionRepositoryRemoveRequest,
  Int32,
] = command_sender("extension repository remove", (context, request) => {
  let ExtensionRepositoryRemoveRequest(cli) = request
  catalog_command(cli, context.mode)
})

///|
let extension_repository_publish_sender : @mediator_async.Sender[
  CommandContext,
  ExtensionRepositoryPublishRequest,
  Int32,
] = command_sender("extension repository publish", (context, request) => {
  let ExtensionRepositoryPublishRequest(cli) = request
  catalog_command(cli, context.mode)
})

///|
let extension_repository_verify_sender : @mediator_async.Sender[
  CommandContext,
  ExtensionRepositoryVerifyRequest,
  Int32,
] = command_sender("extension repository verify", (context, request) => {
  let ExtensionRepositoryVerifyRequest(cli) = request
  catalog_command(cli, context.mode)
})

///|
async fn dispatch_cli(cli : Cli, context : CommandContext) -> Int32 {
  match CommandRequest::decode(cli) {
    RunCommand(request) => run_sender.send(context, request)
    ExecuteCommand(request) => execute_sender.send(context, request)
    VerifyCommand(request) => verify_sender.send(context, request)
    ConformCommand(request) => conform_sender.send(context, request)
    EvalCommand(request) => eval_sender.send(context, request)
    WorksheetCommand(request) => worksheet_sender.send(context, request)
    CompileCommand(request) => compile_sender.send(context, request)
    VersionCommand(request) => version_sender.send(context, request)
    GenerateCommand(request) => generate_sender.send(context, request)
    ModelInspectCommand(request) => model_inspect_sender.send(context, request)
    ModelExportOriginalCommand(request) =>
      model_export_original_sender.send(context, request)
    NotebookExportCommand(request) =>
      notebook_export_sender.send(context, request)
    NotebookImportCommand(request) =>
      notebook_import_sender.send(context, request)
    ConnectedConnectCommand(request) =>
      connected_connect_sender.send(context, request)
    ConnectedRunCommand(request) => connected_run_sender.send(context, request)
    ConnectedArtifactsCommand(request) =>
      connected_artifacts_sender.send(context, request)
    ConnectedOriginalsCommand(request) =>
      connected_originals_sender.send(context, request)
    WorkspaceCommand(request) => workspace_sender.send(context, request)
    WorkspaceInitCommand(request) =>
      workspace_init_sender.send(context, request)
    ProjectListCommand(request) => project_list_sender.send(context, request)
    ProjectAddCommand(request) => project_add_sender.send(context, request)
    ProjectRemoveCommand(request) =>
      project_remove_sender.send(context, request)
    ToolchainInfoCommand(request) =>
      toolchain_info_sender.send(context, request)
    ToolchainSetupCommand(request) =>
      toolchain_setup_sender.send(context, request)
    ToolchainBuildCommand(request) =>
      toolchain_build_sender.send(context, request)
    ToolchainRunCommand(request) => toolchain_run_sender.send(context, request)
    ToolchainExecCommand(request) =>
      toolchain_exec_sender.send(context, request)
    MckCommand(request) => mck_sender.send(context, request)
    ExtensionDescribeCommand(request) =>
      extension_describe_sender.send(context, request)
    ExtensionCompileCommand(request) =>
      extension_compile_sender.send(context, request)
    ExtensionGenerateCommand(request) =>
      extension_generate_sender.send(context, request)
    ExtensionBundleCommand(request) =>
      extension_bundle_sender.send(context, request)
    ExtensionInstallCommand(request) =>
      extension_install_sender.send(context, request)
    ExtensionListCommand(request) =>
      extension_list_sender.send(context, request)
    ExtensionSearchCommand(request) =>
      extension_search_sender.send(context, request)
    ExtensionUpdateCommand(request) =>
      extension_update_sender.send(context, request)
    ExtensionUninstallCommand(request) =>
      extension_uninstall_sender.send(context, request)
    ExtensionRepositoryInitCommand(request) =>
      extension_repository_init_sender.send(context, request)
    ExtensionRepositoryAddCommand(request) =>
      extension_repository_add_sender.send(context, request)
    ExtensionRepositoryListCommand(request) =>
      extension_repository_list_sender.send(context, request)
    ExtensionRepositoryInspectCommand(request) =>
      extension_repository_inspect_sender.send(context, request)
    ExtensionRepositoryEnableCommand(request) =>
      extension_repository_enable_sender.send(context, request)
    ExtensionRepositoryDisableCommand(request) =>
      extension_repository_disable_sender.send(context, request)
    ExtensionRepositoryRemoveCommand(request) =>
      extension_repository_remove_sender.send(context, request)
    ExtensionRepositoryPublishCommand(request) =>
      extension_repository_publish_sender.send(context, request)
    ExtensionRepositoryVerifyCommand(request) =>
      extension_repository_verify_sender.send(context, request)
  }
}
