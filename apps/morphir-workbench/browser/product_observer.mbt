///|
/// Observations run only in returned Cmds. Rabbita stores new_model before Cmd execution.
#module("@morphir/moonbit-workbench/product-observer")
extern "js" fn observe_opening_stored(
  owner : ConnectedOpening,
  workspace : String,
  opening : Int32,
  attempt : String,
) = "openingStored"

///|
#module("@morphir/moonbit-workbench/product-observer")
extern "js" fn observe_inventory_adopted(
  owner : ConnectedOpening,
  workspace : String,
  opening : Int32,
  attempt : String,
  revision : String,
) = "inventoryAdopted"

///|
#module("@morphir/moonbit-workbench/product-observer")
extern "js" fn observe_archive_stored(
  owner : OriginalArchiveOperation,
  workspace : String,
  opening : Int32,
  revision : String,
) = "archiveStored"

///|
#module("@morphir/moonbit-workbench/product-observer")
extern "js" fn observe_model_closed(workspace : String, opening : Int32) = "modelClosed"

///|
#module("@morphir/moonbit-workbench/product-observer")
extern "js" fn observe_workspace_closed(workspace : String, opening : Int32) = "workspaceClosed"

///|
#module("@morphir/moonbit-workbench/product-observer")
extern "js" fn observe_download_call(
  operation : OriginalArchiveOperation,
  actual : ReadyOriginalArchive,
) -> ArchiveDownloadEffect = "requestObservedDownload"

///|
#external
type ArchiveDownloadEffect

///|
/// Pure projection of accepted next state; no observer effect during update.
fn product_observation_cmd(
  before : Model,
  msg : Msg,
  after : Model,
) -> @cmd.Cmd {
  guard visit_of(after) is Some(visit) && visit_of(before) == Some(visit) else {
    return @cmd.none
  }
  let commands : Array[@cmd.Cmd] = []
  if after.originals is OriginalOpening(attempt, owner) &&
    after.originals != before.originals {
    commands.push(
      @cmd.custom_cmd(_ => {
        observe_opening_stored(
          owner,
          visit.workspace.to_string(),
          visit.opening,
          attempt.to_string(),
        )
      }),
    )
  }
  if after.document.inventory_revision() is Some(revision) &&
    before.document.inventory_revision() != Some(revision) &&
    before.originals is OriginalOpening(attempt, owner) {
    commands.push(
      @cmd.custom_cmd(_ => {
        observe_inventory_adopted(
          owner,
          visit.workspace.to_string(),
          visit.opening,
          attempt.to_string(),
          revision.to_string(),
        )
      }),
    )
  }
  if after.originals_archive is PreparedArchive(revision, owner) &&
    before.originals_archive != after.originals_archive {
    commands.push(
      @cmd.custom_cmd(_ => {
        observe_archive_stored(
          owner,
          visit.workspace.to_string(),
          visit.opening,
          revision.to_string(),
        )
      }),
    )
  }
  if msg is CloseModel &&
    (
      before.document.original_inventory() is Some(_) ||
      before.document.document() is Some(_)
    ) &&
    after.document.original_inventory() is None &&
    after.document.document() is None {
    commands.push(
      @cmd.custom_cmd(_ => {
        observe_model_closed(visit.workspace.to_string(), visit.opening)
      }),
    )
  }
  @cmd.batch(commands)
}

///|
fn product_workspace_close_cmd(
  before : Model,
  msg : Msg,
  after : Model,
) -> @cmd.Cmd {
  if msg is CloseWorkspace(id) &&
    viewing(before, id) is Some(view) &&
    viewing(after, id) is None &&
    visit_of(view) is Some(visit) {
    @cmd.custom_cmd(_ => {
      observe_workspace_closed(visit.workspace.to_string(), visit.opening)
    })
  } else {
    @cmd.none
  }
}
