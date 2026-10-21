///|
extern "js" fn expose(handler : (String) -> String) =
  #| handler => { globalThis.morphirWorkbenchExecutions = handler; }

///|
extern "js" fn expose_worksheet(handler : (String) -> String) =
  #| handler => { globalThis.morphirWorkbenchWorksheet = handler; }

///|
extern "js" fn expose_files(handler : (String) -> String) =
  #| handler => { globalThis.morphirWorkbenchExecutions.workspaceFiles = handler; }

///|
fn main {
  let client = @executions.Client::new()
  expose(command => client.handle(command).stringify())
  expose_worksheet(command => @worksheet.browser_command(command).stringify())
  expose_files(source => {
    let result : Json = try {
      ignore(@files.Inventory::decode(@utf8.encode(source)))
      { "ok": true, "value": true }
    } catch {
      @files.Invalid(code) => { "ok": false, "code": code }
    }
    result.stringify()
  })
}
