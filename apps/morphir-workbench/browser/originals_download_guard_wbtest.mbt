///|
/// OFFGRAPH application unit controls. The intercepted download port qualifies
/// dispatch/refusal only, never a real browser download or completed archive.
#external
type OriginalDownloadProbe

///|
extern "js" fn original_download_probe() -> OriginalDownloadProbe =
  #| () => {
  #|   const previous = globalThis.morphirWorkbench;
  #|   const calls = [];
  #|   globalThis.morphirWorkbench = {...previous,
  #|     downloadArtifacts(value, project) { calls.push({value, project}); return ''; }};
  #|   return {calls, restore() { if (previous === undefined) delete globalThis.morphirWorkbench; else globalThis.morphirWorkbench = previous; }};
  #| }

///|
extern "js" fn original_download_calls(probe : OriginalDownloadProbe) -> Int32 =
  #| probe => probe.calls.length

///|
extern "js" fn restore_original_download_probe(probe : OriginalDownloadProbe) =
  #| probe => probe.restore()

///|
fn download_guard_inventory(bytes : Bytes) -> @document.OriginalInventory {
  @document.OriginalInventory::from_connected(
    Map([("opaque.bin", bytes)]),
    ["empty"],
    NotReported,
  ) catch {
    _ => abort("bounded unit inventory")
  }
}

///|
fn download_guard_retain(
  state : @document.State,
  bytes : Bytes,
) -> @document.State {
  let (opening, attempt) = match state.begin(Idle) {
    Started(opening, attempt) => (opening, attempt)
    _ => abort("actual domain begin must accept idle test state")
  }
  opening.finish_originals(attempt, download_guard_inventory(bytes)) catch {
    _ => abort("bounded unit inventory retention")
  }
}

///|
test "failed opening retains Both revisions and cancelled opening uses the same application rejection" {
  let base = lifecycle_model()
  let document = download_guard_retain(base.document, b"prior")
  let before = { ..base, document, mode: ConnectedOriginals, }
  let (opening, attempt) = match document.begin(Idle) {
    Started(opening, attempt) => (opening, attempt)
    _ => abort("begin retry")
  }
  // Pure failed-opening projection, already implemented by State.reject.
  // Real failed receive -> OriginalsChanged is separately existing source and
  // receiver coverage; this control does not fabricate a successful callback.
  let rejected = opening.reject(attempt)
  assert_eq(rejected.document(), document.document())
  assert_eq(rejected.current_revision(), document.current_revision())
  assert_eq(rejected.original_inventory(), document.original_inventory())
  assert_eq(rejected.inventory_revision(), document.inventory_revision())
  let (cancelled, _) = update(
    { ..before, document: opening, busy: true, },
    Cancel,
    quiet(),
  )
  assert_eq(cancelled.document, rejected)
  assert_eq(cancelled.pane, before.pane)
  assert_eq(cancelled.output, before.output)
  assert_eq(cancelled.open_outputs, before.open_outputs)
}

///|
test "stale inventory file messages cannot download replacement or closed bytes" {
  let probe = original_download_probe()
  defer restore_original_download_probe(probe)
  let base = lifecycle_model()
  let document = download_guard_retain(base.document, b"prior")
  let revision = document.inventory_revision().unwrap()
  let path = @document.OriginalPath::parse("opaque.bin", profile=Connected)
  let before = { ..base, document, mode: ConnectedOriginals, }
  let (calibrated, _) = update(
    before,
    DownloadInventoryFile(revision, path),
    quiet(),
  )
  assert_eq(original_download_calls(probe), 1)
  let replacement = {
    ..calibrated,
    document: download_guard_retain(document, b"replacement"),
  }
  let (stale, _) = update(
    replacement,
    DownloadInventoryFile(revision, path),
    quiet(),
  )
  assert_eq(original_download_calls(probe), 1)
  assert_eq(stale.document, replacement.document)
  let current = replacement.document.inventory_revision().unwrap()
  let (current_model, _) = update(
    replacement,
    DownloadInventoryFile(current, path),
    quiet(),
  )
  assert_eq(original_download_calls(probe), 2)
  let (closed, _) = update(current_model, CloseModel, quiet())
  let (after, _) = update(closed, DownloadInventoryFile(current, path), quiet())
  assert_eq(original_download_calls(probe), 2)
  assert_eq(after.document, closed.document)
  assert_eq(after.document.original_inventory(), None)
  assert_eq(after.document.document(), None)
}
