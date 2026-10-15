///|
extern "js" fn expose(handler : (String) -> String) =
  #| handler => { globalThis.morphirWorkbenchJobs = handler; }

///|
fn main {
  let client = @jobs.Client::new()
  expose(command => client.handle(command).stringify())
}
