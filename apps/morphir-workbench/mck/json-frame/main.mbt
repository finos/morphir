///|
/// Transport-specific envelopes share the duplicate-aware parser. Actual HTTP
/// frames retain their production 1-MiB path and trace inputs their own budget.
fn bounded_mck_json(source : String, limit : Int32) -> Json {
  if source.length() > limit || @utf8.encode(source).length() > limit {
    return { "ok": false, "code": "workbench.mck_frame_limit" }
  }
  { "ok": true, "value": @wire.parse(source) } catch {
    _ => { "ok": false, "code": "workbench.invalid_json" }
  }
}

///|
fn mck_json(source : String) -> Json {
  bounded_mck_json(source, 2097152)
}

///|
/// One MiB of hex model source plus the closed JSON envelope needs 3 MiB.
fn model_mck_json(source : String) -> Json {
  bounded_mck_json(source, 3145728)
}

///|
extern "js" fn expose(
  handler : (String) -> String,
  model_handler : (String) -> String,
) =
  #| (handler, modelHandler) => {
  #|   globalThis.morphirWorkbenchMckJson = handler;
  #|   globalThis.morphirWorkbenchModelMckJson = modelHandler;
  #| }

///|
fn main {
  expose(source => mck_json(source).stringify(), source => {
    model_mck_json(source).stringify()
  })
}
