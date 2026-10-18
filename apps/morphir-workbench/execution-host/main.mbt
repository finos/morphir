///|
extern "js" fn expose(
  factory : (String) -> (String) -> String,
  decode : (String) -> String,
) =
  #| (factory, decode) => { globalThis.morphirWorkbenchExecutionHost = factory; globalThis.morphirWorkbenchDecode = decode; }

///|
fn main {
  expose(
    offer => {
      let host = @executions.Host::new(offer) catch {
        _ => abort("Invalid host offer")
      }
      command => host.handle(command).stringify()
    },
    source => @executions.decode_reply(source).stringify(),
  )
}
