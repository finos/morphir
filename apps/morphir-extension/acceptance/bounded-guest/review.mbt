///|
priv enum ReviewMode {
  Orders
  SlowClose
  IgnoreExit
  ArtifactBatch(String)
  LeasePause(String, String)
  Diagnostics
  InventoryWork
  InlineModule
  Scratch(String)
}

///|
fn review_mode(args : Array[String]) -> ReviewMode raise {
  match args[:] {
    [_] => Orders
    [_, "deadline"] => SlowClose
    [_, "exit-deadline"] => IgnoreExit
    [_, "batch", scenario] => ArtifactBatch(scenario)
    [_, "lease", scenario, root] => LeasePause(scenario, root)
    [_, "diagnostics"] => Diagnostics
    [_, "inventory"] => InventoryWork
    [_, "module"] => InlineModule
    [_, "cleanup", root] => Scratch(root)
    _ => fail("unexpected bounded guest fixture mode")
  }
}

///|
fn review_before_final_read(message : Json) -> Bool raise {
  let deliveries = @wire.field(@wire.field(message, "params"), "deliveries")
  deliveries is Array([Object({ "documentId": String(id), .. })]) &&
  id.has_suffix("/total-in-_usd.value")
}

///|
async fn review_before_message(
  mode : ReviewMode,
  message : Json,
  started : Ref[Bool],
) -> Unit {
  guard message is Object({ "method": String(method_name), .. }) else { return }
  if method_name == @access.START {
    started.val = true
  }
  match mode {
    IgnoreExit if started.val && method_name == "morphir.exit" => {
      @stdio.stderr.write(
        "fixture received exit after shutdown acknowledgement\n",
      )
      @async.sleep(10000)
    }
    LeasePause("force", root) if started.val && method_name == "morphir.exit" => {
      @fs.write_file(root + "/exiting", "")
      @async.sleep(10000)
    }
    LeasePause(_, root) if method_name == @access.ADVANCE &&
      review_before_final_read(message) => {
      @fs.write_file(root + "/paused", "")
      while !@fs.exists(root + "/resume") {
        @async.sleep(10)
      }
    }
    SlowClose if method_name == "morphir.shutdown" => @async.sleep(2200)
    Scratch(root) if method_name == @access.START => {
      let siblings = @fs.readdir(root, include_hidden=true)
      let mut injected = 0
      for name in siblings {
        if name.has_prefix(".morphir-bounded-") ||
          name.has_prefix(".morphir-source-") {
          let extra = root + "/" + name + "/extra"
          @fs.mkdir(extra)
          @fs.write_file(extra + "/probe.txt", "cleanup fixture")
          injected += 1
        }
      }
      guard injected == 2 else { fail("expected both private directories") }
    }
    _ => ()
  }
}

///|
fn review_support(mode : ReviewMode) -> @access.Support raise {
  let offer = orders_support().to_json()
  let limits = @wire.object(@wire.field(offer, "limits"))
  match mode {
    SlowClose | IgnoreExit =>
      limits["maxSessionMilliseconds"] = Json::number(300)
    LeasePause(scenario, _) => {
      let duration = if scenario == "force" { 1600 } else { 8000 }
      limits["maxCallMilliseconds"] = Json::number(
        if scenario == "force" {
          1400
        } else {
          4500
        },
      )
      limits["maxSessionMilliseconds"] = Json::number(duration.to_double())
    }
    ArtifactBatch(scenario) => {
      limits["maxEncodedBytesPerExchange"] = Json::number(
        if scenario == "encoded" || scenario == "before-decode" {
          7
        } else {
          8
        },
      )
      limits["maxDecodedBytesPerExchange"] = Json::number(
        if scenario == "decoded" || scenario == "forged-over" {
          5
        } else {
          6
        },
      )
    }
    Diagnostics => limits["maxHostCacheBytes"] = Json::number(32768)
    InventoryWork => limits["maxSessionWorkUnits"] = Json::number(240)
    _ => ()
  }
  @access.Support::from_json(offer)
}

///|
fn review_inventory(
  round : Int32,
  selection : String,
  size : Int32,
) -> @access.ReadRequest {
  Inventory(
    request_id="review-\{round}",
    selection~,
    page_size=size,
    cursor=None,
  )
}

///|
fn review_diagnostics() -> Array[Json] {
  [
    {
      "severity": "info",
      "code": "fixture.retained",
      "message": "x".repeat(9000),
    },
  ]
}

///|
fn review_artifacts(scenario : String) -> Array[@access.ArtifactChunk] raise {
  ["first.txt", "second.txt"].map(path => {
    let bytes = if path == "first.txt" { b"abc" } else { b"xyz" }
    let sha256 = if path == "first.txt" && scenario == "before-decode" {
      "0".repeat(64)
    } else {
      @crypto.bytes_to_hex_string(@crypto.sha256(bytes))
    }
    let forged = path == "second.txt" &&
      (scenario == "forged-over" || scenario == "forged-in")
    @access.ArtifactChunk::from_json({
      "path": Json::string(path),
      "offset": 0,
      "decodedByteLength": if forged {
        Json::number(2)
      } else {
        Json::number(3)
      },
      "sha256": Json::string(sha256),
      "content": @base64.encode(bytes[:]),
      "end": true,
    })
  })
}

///|
fn review_backend(mode : ReviewMode) -> @mep.BoundedBackend raise {
  let artifacts = match mode {
    ArtifactBatch(scenario) => review_artifacts(scenario)
    _ => []
  }
  @mep.BoundedBackend::new(review_support(mode), start => {
    let complete = () => {
      @access.GenerationStep::Complete(
        session_id=start.session_id,
        artifacts=[],
        diagnostics=[],
      )
    }
    let selection = Ref("")
    let first = match mode {
      SlowClose | IgnoreExit | Scratch(_) => complete()
      ArtifactBatch("decoded")
      | ArtifactBatch("exact-complete")
      | ArtifactBatch("forged-over") =>
        Complete(session_id=start.session_id, artifacts~, diagnostics=[])
      ArtifactBatch(_) =>
        Continue(
          session_id=start.session_id,
          round=1,
          requests=[review_inventory(1, "root", 1)],
          artifacts~,
          diagnostics=[],
        )
      Diagnostics =>
        Continue(
          session_id=start.session_id,
          round=1,
          requests=[review_inventory(1, "root", 1)],
          artifacts=[],
          diagnostics=review_diagnostics(),
        )
      _ => orders_pending(start.session_id, 1, review_inventory(1, "root", 8))
    }
    let operation = @mep.BoundedOperation::new(
      advance=request => {
        let round = request.round + 1
        match mode {
          Diagnostics if round <= 6 =>
            Continue(
              session_id=start.session_id,
              round~,
              requests=[review_inventory(round, "root", 1)],
              artifacts=[],
              diagnostics=review_diagnostics(),
            )
          InventoryWork | InlineModule if request.round == 1 => {
            guard request.deliveries is [Inventory(page)] &&
              page.entries
              .iter()
              .find_first(entry => {
                entry is Module(identity, ..) &&
                identity.module_path == "domain"
              })
              is Some(Module(identity, member_selection=Some(member_selection))) else {
              abort("fixture expected the domain module in root inventory")
            }
            selection.val = member_selection
            let read : @access.ReadRequest = if mode is InlineModule {
              Document(
                request_id="review-module",
                document_id=identity.document_id,
              )
            } else {
              review_inventory(round, member_selection, 1)
            }
            orders_pending(start.session_id, round, read)
          }
          InventoryWork if round <= 7 =>
            orders_pending(
              start.session_id,
              round,
              review_inventory(round, selection.val, 1),
            )
          InlineModule => {
            guard request.deliveries is [Document(document)] &&
              document.document_id.has_suffix("/domain/module") else {
              abort("fixture expected the raw domain module")
            }
            complete()
          }
          _ => complete()
        }
      },
      release=() => (),
    )
    (first, operation)
  })
}
