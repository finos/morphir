///|
fn transfer_field(value : Json, name : String) -> Json {
  match value {
    Object(fields) => fields.get(name).unwrap_or(Json::null())
    _ => Json::null()
  }
}

///|
fn choose_files(
  service : FileService,
  path : String,
) -> @filewire.GrantId raise {
  let ticket = service.begin_choose()
  let value = service.finish_choose(ticket, Some(path))
  guard transfer_field(value, "grantId") is String(id) else { abort("grant") }
  @filewire.GrantId::parse(id)
}

///|
fn load_files(
  service : FileService,
  id : @filewire.GrantId,
  sequence : Int32,
) -> Int32 raise {
  let opened = service.request(@filewire.Snapshot(id, sequence))
  guard transfer_field(opened, "revision") is Number(revision, ..) &&
    transfer_field(opened, "size") is Number(size, ..) else {
    abort("snapshot")
  }
  let mut offset = 0
  while offset < size.to_int() {
    let reply = service.request(@filewire.Read(id, sequence, offset))
    guard transfer_field(reply, "content") is String(content) else {
      abort("chunk")
    }
    offset += @base64.decode(content).length()
  }
  ignore(service.request(@filewire.Release(id, sequence)))
  revision.to_int()
}

///|
fn upload_files(
  service : FileService,
  id : @filewire.GrantId,
  sequence : Int32,
  revision : Int32,
  files : Json,
) -> Unit raise {
  let bytes = @utf8.encode(
    ({ "version": 1, "files": files } : Json).stringify(),
  )
  ignore(
    service.request(@filewire.BeginEdit(id, sequence, revision, bytes.length())),
  )
  let mut offset = 0
  while offset < bytes.length() {
    let end = Int32::min(offset + @filewire.CHUNK_LIMIT, bytes.length())
    ignore(
      service.request(
        @filewire.Write(id, sequence, offset, bytes[offset:end].to_owned()),
      ),
    )
    offset = end
  }
}

///|
async test "file grants save complete bytes and reconcile a committed sequence without writing twice" {
  if !supported() {
    return
  }
  let base = write_fixture("transfer")
  defer @fs.rmdir(base, recursive=true)
  @fs.mkdir(base + "/root/one/src", recursive=true)
  @fs.mkdir(base + "/root/empty")
  @fs.write_file(base + "/root/one/src/main.scm", "11")
  let service = FileService::new()
  defer service.close()
  let id = choose_files(service, base + "/root")
  let revision = load_files(service, id, 1)
  upload_files(service, id, 2, revision, {
    "models/node_modules/raw": { "encoding": "base64", "content": "AP+A" },
    "morphir.toml": "[workspace]\nmembers=[]\n",
  })
  let committed = service.request(@filewire.Commit(id, 2))
  assert_eq(
    transfer_field(committed, "revision"),
    Json::number((revision + 1).to_double()),
  )
  assert_eq(
    transfer_field(service.request(@filewire.Status(id, 2)), "state"),
    Json::string("committed"),
  )
  @fs.write_file(base + "/root/morphir.toml", "external")
  assert_eq(service.request(@filewire.Commit(id, 2)), committed)
  assert_eq(disk_bytes(base + "/root/morphir.toml"), b"external")
  assert_eq(disk_bytes(base + "/root/models/node_modules/raw"), b"\x00\xff\x80")
  let disk = WriteRoot::open(base + "/root")
  defer disk.close()
  assert_true(disk.snapshot().directories.contains("empty"))
  assert_false(disk.snapshot().directories.contains("one"))
}

///|
async test "stale full inventory refuses deletion of external files and status records no effect" {
  if !supported() {
    return
  }
  let base = write_fixture("stale-transfer")
  defer @fs.rmdir(base, recursive=true)
  @fs.write_file(base + "/root/main.scm", "11")
  let service = FileService::new()
  defer service.close()
  let id = choose_files(service, base + "/root")
  let revision = load_files(service, id, 1)
  upload_files(service, id, 2, revision, { "main.scm": "22" })
  @fs.write_file(base + "/root/external.scm", "outside edit")
  write_denied(fn() raise { ignore(service.request(@filewire.Commit(id, 2))) })
  let status = service.request(@filewire.Status(id, 2))
  assert_eq(transfer_field(status, "state"), Json::string("failed"))
  assert_eq(
    transfer_field(transfer_field(status, "error"), "effect"),
    Json::string("none"),
  )
  assert_eq(disk_bytes(base + "/root/main.scm"), b"11")
  assert_eq(disk_bytes(base + "/root/external.scm"), b"outside edit")
  ignore(load_files(service, id, 3))
  write_denied(fn() raise {
    ignore(service.request(@filewire.BeginEdit(id, 4, revision, 5)))
  })
}

///|
async test "transfers fence cancelled picker stale offsets releases and revoked grants" {
  if !supported() {
    return
  }
  let base = write_fixture("fenced-transfer")
  defer @fs.rmdir(base, recursive=true)
  let service = FileService::new()
  defer service.close()
  let cancelled = service.begin_choose()
  service.cancel_choose()
  let current = service.begin_choose()
  write_denied(fn() raise {
    ignore(service.finish_choose(cancelled, Some(base + "/root")))
  })
  service.cancel_choose(ticket=Some(cancelled))
  ignore(service.finish_choose(current, None))
  let id = choose_files(service, base + "/root")
  let revision = load_files(service, id, 1)
  ignore(service.request(@filewire.BeginEdit(id, 2, revision, 4)))
  write_denied(fn() raise {
    ignore(service.request(@filewire.Write(id, 2, 1, b"x")))
  })
  ignore(service.request(@filewire.Write(id, 2, 0, b"{}")))
  write_denied(fn() raise {
    ignore(service.request(@filewire.Write(id, 2, 0, b"{}")))
  })
  write_denied(fn() raise { ignore(service.request(@filewire.Commit(id, 2))) })
  write_denied(fn() raise { ignore(service.request(@filewire.Release(id, 1))) })
  assert_eq(
    transfer_field(service.request(@filewire.Status(id, 2)), "offset"),
    Json::number(2),
  )
  ignore(service.request(@filewire.Revoke(id)))
  write_denied(fn() raise { ignore(service.request(@filewire.Status(id, 2))) })
}
