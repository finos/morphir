///|
extern "js" fn expose(handler : (String) -> String) =
  #| handler => { globalThis.morphirWorkbenchExecutions = handler; }

///|
extern "js" fn expose_worksheet(handler : (String) -> String) =
  #| handler => { globalThis.morphirWorkbenchWorksheet = handler; }

///|
fn main {
  let client = @executions.Client::new()
  expose(command => client.handle(command).stringify())
  expose_worksheet(command => @worksheet.browser_command(command).stringify())
}
