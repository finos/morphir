///|
#external
type OriginalArchiveOperation

///|
#external
type OriginalArchiveEvent

///|
#external
type ReadyOriginalArchive

///|
#external
type OriginalArchiveInput

///|
#external
type OriginalArchiveMetadataSink

///|
#external
type OriginalArchiveSnapshotSink

///|
enum OriginalsArchive {
  NoArchive
  PreparedArchive(@document.InventoryRevision, OriginalArchiveOperation)
} derive(Eq)

///|
impl Eq for OriginalArchiveOperation with fn equal(self, other) {
  same_originals_archive(self, other)
}

///|
enum ArchiveFailure {
  InvalidArchiveInventory(String)
  ArchiveSizeFailure(String)
  ArchiveAllocationFailure(String)
  ArchiveEncodingFailure(String)
  RetiredArchive(String)
  IncompatibleArchiveBridge
}

///|
fn archive_failure(kind : String, message : String) -> ArchiveFailure {
  match kind {
    "inventory" => InvalidArchiveInventory(message)
    "size" => ArchiveSizeFailure(message)
    "allocation" => ArchiveAllocationFailure(message)
    "encoding" => ArchiveEncodingFailure(message)
    "retired" => RetiredArchive(message)
    _ => IncompatibleArchiveBridge
  }
}

///|
fn ArchiveFailure::message(self : ArchiveFailure) -> String {
  match self {
    InvalidArchiveInventory(message)
    | ArchiveSizeFailure(message)
    | ArchiveAllocationFailure(message)
    | ArchiveEncodingFailure(message)
    | RetiredArchive(message) => message
    IncompatibleArchiveBridge => "Incompatible originals archive bridge"
  }
}

///|
enum ArchiveStart {
  ArchivePrepared(OriginalArchiveOperation)
  ArchiveRefused(ArchiveFailure)
}

///|
enum ArchiveDownloadResult {
  DownloadRequested
  DownloadRetired
  DownloadFailed(ArchiveFailure)
}

///|
/// Canonical decimal scalar FFIs avoid UInt64/Int32 compiler representation assumptions.
extern "js" fn archive_input(
  entries : String,
  raw : String,
  names : String,
  describe : (OriginalArchiveMetadataSink) -> Unit,
  copy_files : (OriginalArchiveSnapshotSink) -> Unit,
) -> OriginalArchiveInput =
  #| (entries, raw, names, describe, copyFiles) => {
  #|   const exact = text => {
  #|     if (!/^(0|[1-9][0-9]*)$/.test(text)) throw new RangeError('Invalid archive scalar');
  #|     const value = BigInt(text);
  #|     if (value > BigInt(Number.MAX_SAFE_INTEGER)) throw new RangeError('Unsafe archive scalar');
  #|     return Number(value);
  #|   };
  #|   return {kind: 'connected', entries: exact(entries), rawBytes: exact(raw), archiveNameBytes: exact(names), describe, copyFiles};
  #| }

///|
extern "js" fn archive_file_metadata(
  sink : OriginalArchiveMetadataSink,
  path : String,
  length : String,
) =
  #| (sink, path, length) => {
  #|   if (!/^(0|[1-9][0-9]*)$/.test(length)) throw new RangeError('Invalid original length');
  #|   const value = BigInt(length);
  #|   if (value > BigInt(Number.MAX_SAFE_INTEGER)) throw new RangeError('Unsafe original length');
  #|   sink.file(path, Number(value));
  #| }

///|
extern "js" fn archive_directory_metadata(
  sink : OriginalArchiveMetadataSink,
  path : String,
) =
  #| (sink, path) => sink.directory(path)

///|
extern "js" fn archive_file_copy(
  sink : OriginalArchiveSnapshotSink,
  path : String,
  bytes : Bytes,
) =
  #| (sink, path, bytes) => sink.file(path, bytes)

///|
extern "js" fn create_originals_archive(
  input : OriginalArchiveInput,
  prepared : (OriginalArchiveOperation) -> ArchiveStart,
  refused : (String, String) -> ArchiveStart,
) -> ArchiveStart =
  #| (input, prepared, refused) => {
  #|   const result = globalThis.morphirWorkbench.createOriginalsArchive(input);
  #|   return result.kind === 'prepared' ? prepared(result.operation) : refused(result.failure.kind, result.failure.message);
  #| }

///|
extern "js" fn prepare_originals_archive(
  operation : OriginalArchiveOperation,
  receive : (OriginalArchiveEvent) -> Unit,
) =
  #| (operation, receive) => globalThis.morphirWorkbench.prepareOriginalsArchive(operation, receive)

///|
extern "js" fn same_originals_archive(
  left : OriginalArchiveOperation,
  right : OriginalArchiveOperation,
) -> Bool =
  #| (left, right) => left === right

///|
extern "js" fn retire_originals_archive(operation : OriginalArchiveOperation) =
  #| operation => operation.retire()

///|
extern "js" fn archive_event_kind(event : OriginalArchiveEvent) -> String =
  #| event => event.kind

///|
extern "js" fn archive_event_owner(
  event : OriginalArchiveEvent,
) -> OriginalArchiveOperation =
  #| event => event.operation

///|
extern "js" fn archive_event_ready(
  event : OriginalArchiveEvent,
) -> ReadyOriginalArchive =
  #| event => event.archive

///|
extern "js" fn archive_event_failure(
  event : OriginalArchiveEvent,
  failed : (String, String) -> ArchiveFailure,
) -> ArchiveFailure =
  #| (event, failed) => failed(event.failure.kind, event.failure.message)

///|
extern "js" fn dispose_ready_originals_archive(archive : ReadyOriginalArchive) =
  #| archive => archive.dispose()

///|
extern "js" fn request_originals_archive_download(
  request : (OriginalArchiveOperation, ReadyOriginalArchive) -> ArchiveDownloadEffect,
  operation : OriginalArchiveOperation,
  archive : ReadyOriginalArchive,
  requested : () -> ArchiveDownloadResult,
  retired : () -> ArchiveDownloadResult,
  failed : (String, String) -> ArchiveDownloadResult,
) -> ArchiveDownloadResult =
  #| (request, operation, archive, requested, retired, failed) => {
  #|   const result = request(operation, archive);
  #|   switch (result.kind) {
  #|     case 'download-requested': return requested();
  #|     case 'retired': return retired();
  #|     case 'failed': return failed(result.failure.kind, result.failure.message);
  #|     default: return failed('incompatible', 'Incompatible archive bridge');
  #|   }
  #| }

///|
fn retire_archive(state : OriginalsArchive) -> Unit {
  if state is PreparedArchive(_, operation) {
    retire_originals_archive(operation)
  }
}

///|
fn dispose_archive_message(msg : Msg) -> Unit {
  if msg is InventoryArchiveChanged(_, event) &&
    archive_event_kind(event) == "ready" {
    dispose_ready_originals_archive(archive_event_ready(event))
  }
}

///|
/// Preserve parked work; successful document replacement/Close retires synchronously.
fn follow_original_archive(before : Model, after : Model) -> Model {
  if before.active != after.active || before.opening != after.opening {
    return after
  }
  if before.originals_archive is PreparedArchive(revision, _) &&
    after.document.inventory_revision() != Some(revision) {
    retire_archive(before.originals_archive)
    if after.originals_archive == before.originals_archive {
      return { ..after, originals_archive: NoArchive, }
    }
  }
  after
}

///|
fn update_original_archive(
  model : Model,
  msg : Msg,
  emit : @cmd.Emit[Msg],
) -> (Model, @cmd.Cmd) {
  match msg {
    DownloadInventoryArchive(revision) => {
      guard model.originals_archive is NoArchive &&
        model.document.original_inventory_for(revision) is Some(inventory) else {
        return (model, @cmd.none)
      }
      let sizes = inventory.archive_sizes() catch {
        _ =>
          return (
            { ..model, status: "Original archive metadata is invalid", },
            @cmd.none,
          )
      }
      let input = archive_input(
        sizes.entry_count().to_string(),
        sizes.file_bytes().to_string(),
        sizes.archive_name_bytes().to_string(),
        sink => {
          for index = 0; index < inventory.entry_count(); index = index + 1 {
            match inventory.entry(index) {
              Some(File(path)) =>
                archive_file_metadata(
                  sink,
                  path.to_string(),
                  inventory.file_byte_length(path).unwrap().to_string(),
                )
              Some(Directory(path)) =>
                archive_directory_metadata(sink, path.to_string())
              None => ()
            }
          }
        },
        sink => {
          for path, bytes in inventory.copy_files() {
            archive_file_copy(sink, path, bytes)
          }
        },
      )
      match
        create_originals_archive(
          input,
          operation => ArchivePrepared(operation),
          (kind, message) => ArchiveRefused(archive_failure(kind, message)),
        ) {
        ArchiveRefused(failure) =>
          ({ ..model, status: failure.message(), }, @cmd.none)
        ArchivePrepared(operation) =>
          (
            {
              ..model,
              originals_archive: PreparedArchive(revision, operation),
              status: "Preparing originals archive…",
            },
            @cmd.custom_cmd(scheduler => {
              prepare_originals_archive(operation, event => {
                scheduler.add(emit(InventoryArchiveChanged(revision, event)))
              })
            }),
          )
      }
    }
    InventoryArchiveChanged(revision, event) => {
      let operation = archive_event_owner(event)
      guard model.originals_archive is PreparedArchive(actual_revision, actual) &&
        actual_revision == revision &&
        same_originals_archive(actual, operation) &&
        model.document.inventory_revision() == Some(revision) else {
        dispose_archive_message(msg)
        return (model, @cmd.none)
      }
      let status = match archive_event_kind(event) {
        "ready" =>
          match
            request_originals_archive_download(
              observe_download_call,
              operation,
              archive_event_ready(event),
              () => DownloadRequested,
              () => DownloadRetired,
              (kind, message) => DownloadFailed(archive_failure(kind, message)),
            ) {
            DownloadRequested => "Original archive download started"
            DownloadRetired => "Original archive was retired"
            DownloadFailed(failure) => failure.message()
          }
        "failed" => archive_event_failure(event, archive_failure).message()
        _ => {
          retire_originals_archive(operation)
          "Incompatible originals archive bridge"
        }
      }
      ({ ..model, originals_archive: NoArchive, status, }, @cmd.none)
    }
    _ => (model, @cmd.none)
  }
}
