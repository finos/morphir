///|
extern "js" fn expose(factory : () -> (String) -> String) =
  #| factory => { globalThis.__morphirConnectedCore = factory; }

///|
fn main {
  expose(fn() {
    let client = @connected.Client::new()
    fn(source) { client.handle(source).stringify() }
  })
}
