///|
/// Only the MCK transport envelope has a 2-MiB budget. Actual HTTP frames retain
/// their production 1-MiB validation path and the trace input has its own budget.
fn mck_json(source : String) -> Json {
  if source.length() > 2097152 || @utf8.encode(source).length() > 2097152 {
    return { "ok": false, "code": "workbench.mck_frame_limit" }
  }
  { "ok": true, "value": @wire.parse(source) } catch {
    _ => { "ok": false, "code": "workbench.invalid_json" }
  }
}

///|
extern "js" fn expose(handler : (String) -> String) =
  #| handler => { globalThis.morphirWorkbenchMckJson = handler; }

///|
fn main {
  expose(source => mck_json(source).stringify())
}
