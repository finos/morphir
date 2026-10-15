///|
extern "js" fn expose(
  factory : (String) -> (String) -> String,
  decode : (String) -> String,
) =
  #| (factory, decode) => { globalThis.morphirWorkbenchJobHost = factory; globalThis.morphirWorkbenchDecode = decode; }

///|
fn main {
  expose(
    offer => {
      let host = @jobs.Host::new(offer) catch {
        _ => abort("Invalid host offer")
      }
      command => host.handle(command).stringify()
    },
    source => @jobs.decode_reply(source).stringify(),
  )
}
