///|
priv enum FileTransfer {
  Idle
  Download(Int32, Bytes, Int32)
  Upload(Int32, Int32, Array[Bytes], Int32)
  Committed(Int32, Int32)
  Failed(Int32, @filewire.Failure)
}

///|
priv struct FileGrant {
  root : WriteRoot
  mut baseline : FileSnapshot?
  mut revision : Int32
  mut retired : Int32
  mut transfer : FileTransfer
}

///|
/// Page-owned write grants. Only trusted picker completion accepts a native path.
pub struct FileService {
  priv grants : Map[String, FileGrant]
  priv mut next : Int32
  priv mut picker : Int32?
  priv mut closed : Bool
}

///|
pub fn FileService::new() -> FileService {
  { grants: Map([]), next: 0, picker: None, closed: false, }
}

///|
pub fn FileService::close(self : FileService) -> Unit {
  self.closed = true
  self.picker = None
  for _, grant in self.grants {
    grant.root.close()
  }
  self.grants.clear()
}

///|
pub fn FileService::begin_choose(self : FileService) -> Int32 raise {
  guard !self.closed else { raise Rejected("workbench.workspace_revoked") }
  guard self.picker is None else {
    raise Rejected("workbench.workspace_picker_busy")
  }
  guard self.grants.length() < 8 && self.next < 2147483647 else {
    raise Rejected("workbench.workspace_quota")
  }
  self.next += 1
  self.picker = Some(self.next)
  self.next
}

///|
pub fn FileService::cancel_choose(
  self : FileService,
  ticket~ : Int32? = None,
) -> Unit {
  if ticket is None || self.picker == ticket {
    self.picker = None
  }
}

///|
pub fn FileService::finish_choose(
  self : FileService,
  ticket : Int32,
  path : String?,
) -> Json raise {
  guard !self.closed && self.picker == Some(ticket) else {
    raise Rejected("workbench.workspace_discarded")
  }
  self.picker = None
  guard path is Some(path) else { return { "cancelled": true } }
  let root = WriteRoot::open(path)
  errdefer root.close()
  let id = "workspace-files-" + ticket.to_string()
  let name = path
    .trim_end(chars="/")
    .split("/")
    .last()
    .map(s => s.to_owned())
    .unwrap_or("Workspace")
  guard name != "" &&
    name.length() <= 1024 &&
    !name.iter().any(c => c < ' ' || c == '\u007f') else {
    raise Rejected("workbench.workspace_path")
  }
  self.grants[id] = {
    root,
    baseline: None,
    revision: 0,
    retired: 0,
    transfer: Idle,
  }
  { "cancelled": false, "grantId": id, "revision": 0, "name": name }
}

///|
fn transfer_sequence(transfer : FileTransfer) -> Int32? {
  match transfer {
    Idle => None
    Download(n, _, _) | Upload(n, _, _, _) | Committed(n, _) | Failed(n, _) =>
      Some(n)
  }
}

///|
fn inventory(snapshot : FileSnapshot) -> Bytes raise {
  @filewire.Inventory::new(snapshot.files).encode()
}

///|
fn decode_inventory(bytes : Bytes) -> Map[String, Bytes] raise {
  @filewire.Inventory::decode(bytes).files()
}

///|
fn difference(old : FileSnapshot, files : Map[String, Bytes]) -> FileEdit raise {
  let changes = @filewire.Inventory::new(old.files).difference(
    @filewire.Inventory::new(files),
    old.directories,
  )
  {
    writes: changes.writes,
    deletes: changes.deletes,
    directories: changes.create_directories,
    remove_directories: changes.remove_directories,
  }
}

///|
fn failure_reason(error : Error) -> @filewire.Failure {
  match error {
    Uncertain(code) =>
      @filewire.Uncertain(
        code, "The save could not be confirmed. Retain the local draft and reopen the folder after recovery.",
      )
    Rejected(code) =>
      @filewire.Denied(
        code, "The workspace request was refused. Reopen the folder to load current disk contents.",
      )
    _ =>
      @filewire.Denied(
        "workbench.workspace_invalid", "Invalid workspace file request.",
      )
  }
}

///|
pub fn FileService::request(
  self : FileService,
  command : @filewire.Command,
) -> Json raise {
  guard !self.closed else { raise Rejected("workbench.workspace_revoked") }
  let (id, sequence) = match command {
    Snapshot(id, n)
    | Read(id, n, _)
    | BeginEdit(id, n, _, _)
    | Write(id, n, _, _)
    | Commit(id, n)
    | Status(id, n)
    | Release(id, n) => (id.to_string(), n)
    Revoke(id) => {
      if self.grants.get(id.to_string()) is Some(grant) {
        grant.root.close()
        self.grants.remove(id.to_string())
      }
      return {}
    }
    _ => raise Rejected("workbench.workspace_operation")
  }
  guard self.grants.get(id) is Some(grant) else {
    raise Rejected("workbench.workspace_revoked")
  }
  match command {
    Snapshot(_, _) => {
      guard sequence > grant.retired && grant.revision < 2147483647 else {
        raise Rejected("workbench.workspace_sequence")
      }
      guard grant.transfer is Idle ||
        grant.transfer is Committed(_, _) ||
        grant.transfer is Failed(_, _) else {
        raise Rejected("workbench.workspace_busy")
      }
      let snapshot = grant.root.snapshot()
      let bytes = inventory(snapshot)
      grant.retired = sequence
      grant.revision += 1
      grant.baseline = Some(snapshot)
      grant.transfer = Download(sequence, bytes, 0)
      {
        "sequence": sequence,
        "size": bytes.length(),
        "revision": grant.revision,
      }
    }
    Read(_, _, offset) => {
      guard grant.transfer is Download(active, bytes, expected) &&
        active == sequence &&
        offset == expected &&
        offset < bytes.length() else {
        raise Rejected("workbench.workspace_sequence")
      }
      let end = Int32::min(offset + @filewire.CHUNK_LIMIT, bytes.length())
      grant.transfer = Download(sequence, bytes, end)
      {
        "sequence": sequence,
        "offset": offset,
        "content": @base64.encode(bytes[offset:end]),
        "done": end == bytes.length(),
      }
    }
    BeginEdit(_, _, revision, size) => {
      guard sequence > grant.retired &&
        revision == grant.revision &&
        grant.baseline is Some(_) &&
        grant.revision < 2147483647 else {
        raise Rejected("workbench.workspace_revision")
      }
      guard size > 0 && size <= @filewire.TRANSFER_LIMIT else {
        raise Rejected("workbench.workspace_quota")
      }
      guard grant.transfer is Idle ||
        grant.transfer is Committed(_, _) ||
        grant.transfer is Failed(_, @filewire.Denied(_, _)) else {
        raise Rejected("workbench.workspace_busy")
      }
      grant.retired = sequence
      grant.transfer = Upload(sequence, size, [], 0)
      { "sequence": sequence, "offset": 0 }
    }
    Write(_, _, offset, bytes) => {
      guard grant.transfer is Upload(active, size, chunks, expected) &&
        active == sequence &&
        offset == expected &&
        bytes.length() > 0 &&
        bytes.length() <= @filewire.CHUNK_LIMIT &&
        bytes.length() <= size - offset else {
        raise Rejected("workbench.workspace_sequence")
      }
      chunks.push(Bytes::from_array(bytes.iter().collect()))
      grant.transfer = Upload(active, size, chunks, offset + bytes.length())
      { "sequence": sequence, "offset": offset + bytes.length() }
    }
    Commit(_, _) => {
      if grant.transfer is Committed(active, revision) && active == sequence {
        return { "sequence": sequence, "revision": revision }
      }
      guard grant.transfer is Upload(active, size, chunks, offset) &&
        active == sequence &&
        offset == size &&
        grant.baseline is Some(baseline) else {
        raise Rejected("workbench.workspace_sequence")
      }
      try {
        let buffer : FixedArray[Byte] = FixedArray::make(size, 0x00)
        let mut position = 0
        for chunk in chunks {
          for byte in chunk {
            buffer[position] = byte
            position += 1
          }
        }
        let files = decode_inventory(buffer.unsafe_reinterpret_as_bytes())
        let current = grant.root.snapshot()
        guard current.files == baseline.files &&
          current.directories == baseline.directories else {
          raise Rejected("workbench.workspace_changed")
        }
        grant.root.apply(baseline, difference(baseline, files))
        let saved = grant.root.snapshot() catch {
          _ => raise Uncertain("workbench.workspace_save_unconfirmed")
        }
        guard saved.files == files else {
          raise Uncertain("workbench.workspace_changed_after_save")
        }
        grant.baseline = Some(saved)
        grant.revision += 1
        grant.transfer = Committed(sequence, grant.revision)
        { "sequence": sequence, "revision": grant.revision }
      } catch {
        error => {
          grant.transfer = Failed(sequence, failure_reason(error))
          raise error
        }
      }
    }
    Status(_, _) => {
      guard transfer_sequence(grant.transfer) == Some(sequence) ||
        (grant.transfer is Idle && sequence == grant.retired) else {
        raise Rejected("workbench.workspace_sequence")
      }
      match grant.transfer {
        Upload(_, size, _, offset) =>
          {
            "sequence": sequence,
            "state": "uploading",
            "offset": offset,
            "size": size,
          }
        Committed(_, revision) =>
          { "sequence": sequence, "state": "committed", "revision": revision }
        Failed(_, reason) => {
          let (code, message, effect) = match reason {
            Denied(c, m) => (c, m, "none")
            Uncertain(c, m) => (c, m, "unknown")
          }
          {
            "sequence": sequence,
            "state": "failed",
            "error": { "code": code, "message": message, "effect": effect },
          }
        }
        _ => { "sequence": sequence, "state": "idle" }
      }
    }
    Release(_, _) => {
      // A late release cannot retire a newer transfer. Failed uncertain saves
      // remain blocked until an explicit fresh snapshot succeeds.
      guard sequence >= grant.retired else {
        raise Rejected("workbench.workspace_sequence")
      }
      grant.retired = sequence
      if !(grant.transfer is Failed(_, @filewire.Uncertain(_, _))) {
        grant.transfer = Idle
      }
      {}
    }
    _ => raise Rejected("workbench.workspace_operation")
  }
}

///|
pub fn file_failure(error : Error) -> @filewire.Failure {
  failure_reason(error)
}
