///|
extern "js" fn expose(handler : (String) -> String) =
  #| handler => { globalThis.morphirWorkbenchExecutions = handler; }

///|
fn main {
  let client = @executions.Client::new()
  expose(command => client.handle(command).stringify())
}
