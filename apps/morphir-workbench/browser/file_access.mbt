///|
enum FileSaveState {
  Idle
  Saving(Int32)
  Blocked(String)
} derive(Eq)

///|
enum FileLocation {
  DesktopFolder
  ConnectedRoot
} derive(Eq)

///|
struct FileAuthority {
  location : FileLocation
  grant : @filewire.GrantId
  revision : Int32
  saved_revision : Int32
  name : String
  state : FileSaveState
} derive(Eq)

///|
enum FileAccess {
  Memory
  Detached(String)
  ReadOnly(String)
  Writable(FileAuthority)
} derive(Eq)

///|
fn workspace_writable(model : Model) -> Bool {
  match model.file_access {
    Memory | Detached(_) => !model.connected
    ReadOnly(_) => false
    Writable(_) => true
  }
}

///|
fn uses_file_projects(model : Model) -> Bool {
  !model.connected || model.file_access is Writable(_)
}

///|
fn workspace_status(model : Model) -> String {
  let location = match model.file_access {
    Memory => ""
    Detached(name) => name + " · local draft; reopen the folder to reconnect"
    ReadOnly(_) => "Folder · read only"
    Writable(authority) =>
      match authority.state {
        Saving(_) => "Folder · saving"
        Blocked(_) => "Folder · save blocked; local draft retained"
        Idle =>
          if authority.saved_revision == model.revision {
            "Folder · saved"
          } else {
            "Folder · unsaved"
          }
      }
  }
  if location == "" {
    model.status
  } else if model.status == "" {
    location
  } else {
    location + " · " + model.status
  }
}

///|
extern "js" fn save_workspace_files(
  grant : String,
  files : String,
  receive : (String) -> Unit,
) =
  #| (grant, files, receive) => globalThis.morphirWorkbench.saveWorkspace(grant, JSON.parse(files), receive)

///|
extern "js" fn revoke_workspace_files(grant : String) =
  #| grant => { Promise.resolve(globalThis.morphirWorkbench.revokeWorkspace(grant)).catch(() => {}); }

///|
fn close_workspace(
  model : Model,
  id : @workspace.WorkspaceId,
  emit : @cmd.Emit[Msg],
) -> (Model, @cmd.Cmd) {
  let access = viewing(model, id).map(m => m.file_access)
  let (closed, command) = close_workspace_here(model, id, emit)
  if access is Some(Writable(authority)) && viewing(closed, id) is None {
    (
      closed,
      @cmd.batch([
        command,
        @cmd.custom_cmd(_ => revoke_workspace_files(authority.grant.to_string())),
      ]),
    )
  } else {
    (closed, command)
  }
}

///|
fn open_file_workspace(model : Model, result : Json) -> (Model, @cmd.Cmd) {
  try {
    let authority = field(result, "fileAuthority")
    let location = match text(authority, "kind") {
      "native-write" if !model.connected => DesktopFolder
      "connected-write" if model.connected => ConnectedRoot
      _ => raise @config.Invalid("Invalid workspace authority")
    }
    let grant = @filewire.GrantId::parse(text(authority, "grantId"))
    guard field(authority, "revision") is Number(revision, ..) &&
      revision >= 0 &&
      revision < 2147483647 &&
      revision == revision.to_int().to_double() else {
      raise @config.Invalid("Invalid workspace revision")
    }
    let files = @workspace_files.Files::from_json(
      field(result, "workspaceFiles"),
    )
    let opened = with_workspace_files(model, files)
    (
      {
        ..opened,
        busy: false,
        projects: [],
        file_access: Writable({
          location,
          grant,
          revision: revision.to_int(),
          saved_revision: opened.revision,
          name: text(authority, "name"),
          state: Idle,
        }),
        status: text(result, "message"),
      },
      @cmd.none,
    )
  } catch {
    _ =>
      (
        {
          ..model,
          busy: false,
          status: "The host returned an invalid workspace file tree. The previous workspace was retained.",
        },
        @cmd.none,
      )
  }
}

///|
fn save_files(
  model : Model,
  revision : Int32,
  emit : @cmd.Emit[Msg],
) -> (Model, @cmd.Cmd) {
  if revision != model.revision || !workspace_writable(model) {
    return (model, @cmd.none)
  }
  let saved = if model.connected || model.dirty.is_empty() {
    model
  } else {
    write_projects(model)
  }
  guard saved.file_access is Writable(authority) &&
    authority.state is Idle &&
    authority.saved_revision != saved.revision else {
    return (saved, @cmd.none)
  }
  let files = saved.workspace_files.to_json().stringify()
  (
    {
      ..saved,
      file_access: Writable({ ..authority, state: Saving(revision), }),
      status: "Saving workspace folder…",
    },
    @cmd.custom_cmd(scheduler => {
      save_workspace_files(authority.grant.to_string(), files, reply => {
        scheduler.add(emit(FilesSaved(authority.grant, revision, reply)))
      })
    }),
  )
}

///|
fn files_saved(
  model : Model,
  grant : @filewire.GrantId,
  source_revision : Int32,
  source : String,
  emit : @cmd.Emit[Msg],
) -> (Model, @cmd.Cmd) {
  guard model.file_access is Writable(authority) &&
    authority.grant == grant &&
    authority.state is Saving(active) &&
    active == source_revision else {
    return (model, @cmd.none)
  }
  let reply = @json.parse(source) catch { _ => Json::null() }
  if field(reply, "success") == Json::boolean(true) &&
    field(reply, "revision") is Number(revision, ..) &&
    revision == (authority.revision + 1).to_double() {
    let saved = {
      ..model,
      file_access: Writable({
        ..authority,
        revision: revision.to_int(),
        saved_revision: source_revision,
        state: Idle,
      }),
      dirty: if source_revision == model.revision {
        []
      } else {
        model.dirty
      },
      status: "Workspace folder saved",
    }
    (
      saved,
      if source_revision != model.revision {
        @cmd.delay(emit(SaveProject(model.revision)), 0)
      } else {
        @cmd.none
      },
    )
  } else {
    let message = match text(reply, "message") {
      "" =>
        "The folder save could not be confirmed. Keep the local draft and reopen the folder."
      message => message
    }
    (
      {
        ..model,
        file_access: Writable({ ..authority, state: Blocked(message), }),
        status: message,
      },
      @cmd.none,
    )
  }
}
