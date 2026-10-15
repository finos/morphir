///|
fn metadata_hash_file(path : String, check : () -> Unit raise) -> String raise {
  let digest = @crypto.SHA256::new()
  @platform.file_chunks(path, 536870912, fn(bytes) raise {
    check()
    digest.update(bytes)
  })
  check()
  @crypto.bytes_to_hex_string(digest.finalize())
}

///|
/// Inspect the fixed host helper bundle for an explicit grant document. This
/// reads only named runtime files; it never executes a service or creates trust.
pub fn metadata_helper_bundle_sha256(helper : String) -> String raise {
  metadata_bundle_hash(helper, fn() { () })
}

///|
fn metadata_bundle_hash(
  helper : String,
  check : () -> Unit raise,
) -> String raise {
  if !helper.has_suffix("/metadata.mjs") {
    raise @config.Invalid("metadata.restore_unqualified_helper")
  }
  let directory = helper[:helper.length() - "metadata.mjs".length()].to_owned()
  let entries = [
    "WindowsJob.cs", "metadata.mjs", "supervision.mjs", "windows-job.mjs", "windows-job.ps1",
  ].map(fn(name) raise {
    check()
    let bytes = metadata_read_file(directory + name, 1048576, check)
    if bytes.length() > 1048576 {
      raise @config.Invalid("metadata.restore_helper_limit")
    }
    Json::array([Json::string(name), Json::string(@identity.sha256(bytes))])
  })
  @identity.sha256(@utf8.encode(Json::array(entries).stringify()))
}

///|
fn[T] metadata_observe(
  observer : @observe.Observer,
  operation : String,
  project : String,
  stage : @observe.Stage,
  code : String,
  run : () -> T raise,
  audit? : MetadataAuditContext? = None,
) -> T raise {
  let scoped = {
    ..observer,
    try_record: fn(record) raise {
      (observer.try_record)({
        ..record,
        correlation: Some({
          target: "local-library-mvp",
          lease_id: operation,
          call_id: project,
          attempt_id: code,
        }),
        details: Some({
          entry: project,
          code: code +
          (match record.signal {
            Started => ".started"
            Succeeded => ".succeeded"
            Failed => ".failed"
            Cancelled => ".cancelled"
            Notice => ".notice"
          }),
        }),
      })
    },
  }
  let work = fn() raise {
    scoped
    .scope()
    .observe(stage, fn(_) raise { run() }, is_cancelled=fn(error) {
      error_message(error).contains("Cancelled")
    })
  }
  match audit {
    None => work()
    Some(context) => {
      let phase : MetadataAuditPhase = match code {
        "metadata.acquire" => Acquire
        "metadata.probe" => Probe
        "metadata.restore" => Restore
        "metadata.decode" => Decode
        "metadata.context" => Context
        _ => Cleanup
      }
      context.observe(phase, work)
    }
  }
}

///|
fn metadata_read_file(
  path : String,
  limit : Int,
  check : () -> Unit raise,
) -> Bytes raise {
  let chunks : Array[Bytes] = []
  @platform.file_chunks(path, limit, fn(bytes) raise {
    check()
    chunks.push(bytes)
  })
  Bytes::from_iter(chunks.iter().flat_map(bytes => bytes.iter()))
}
