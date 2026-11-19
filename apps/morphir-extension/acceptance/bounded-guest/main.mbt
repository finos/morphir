///|
priv enum OrdersPhase {
  RootModules
  FirstMembers(String)
  FinalMembers(@access.InventoryIdentity)
  FinalValue(@access.InventoryIdentity)
  ReferencedValue
}

///|
fn orders_support() -> @access.Support raise {
  let tuple : @access.AccessTuple = {
    ir: V4,
    codec: MorphirJson,
    encoding: Plain,
  }
  @access.Support::from_json({
    "tuples": [tuple.to_json()],
    "limits": {
      "maxFrameBytes": 32768,
      "maxEncodedBytesPerExchange": 8192,
      "maxDecodedBytesPerExchange": 6144,
      "maxDocumentsPerBatch": 8,
      "maxDepth": 64,
      "maxNodes": 256,
      "maxDiagnosticsPerExchange": 16,
      "maxOutstandingRequests": 8,
      "maxGuestStateBytes": 1048576,
      "maxHostCacheBytes": 1048576,
      "maxArtifactChunkBytes": 4096,
      "maxArtifactBytes": 4096,
      "maxTotalArtifactBytes": 4096,
      "maxSessionDiskBytes": 16384,
      "maxSessionWorkUnits": 4096,
      "maxRounds": 16,
      "maxCallMilliseconds": 500,
      "maxSessionMilliseconds": 2500,
    },
  })
}

///|
fn orders_pending(
  session_id : String,
  round : Int32,
  request : @access.ReadRequest,
) -> @access.GenerationStep {
  Continue(session_id~, round~, requests=[request], artifacts=[], diagnostics=[])
}

///|
fn orders_body(
  document : @access.DocumentDelivery,
  name : String,
) -> Json raise {
  let bytes = @base64.decode(document.content)
  let value = @wire.parse_bounded(@utf8.decode(bytes[:]))
  guard @wire.field(value, "name") == Json::string(name) else {
    fail("Unexpected orders document name")
  }
  let definition = @wire.field(@wire.field(value, "def"), "Public")
  let expression = @wire.field(definition, "ExpressionBody")
  guard @wire.field(expression, "outputType") ==
    Json::string("morphir/SDK:basics#int") else {
    fail("Expected the SDK int output type")
  }
  @wire.field(expression, "body")
}

///|
fn orders_advance(
  phase : Ref[OrdersPhase],
  advance : @access.Advance,
) -> @access.GenerationStep raise {
  let request_id = "orders-\{advance.round + 1}"
  let (next, request) : (OrdersPhase, @access.ReadRequest) = match
    (phase.val, advance.deliveries) {
    (RootModules, [Inventory(page)]) => {
      for entry in page.entries {
        if entry is Module(identity, member_selection=Some(selection)) &&
          identity.package_name == "acme/orders" &&
          identity.module_path == "domain" &&
          identity.role is Definition {
          phase.val = FirstMembers(selection)
          return orders_pending(
            advance.session_id,
            advance.round + 1,
            Inventory(request_id~, selection~, page_size=2, cursor=None),
          )
        }
      }
      guard page.next_cursor is Some(cursor) else {
        fail("Root inventory ended before reaching the orders domain")
      }
      (
        RootModules,
        Inventory(
          request_id~,
          selection="root",
          page_size=1,
          cursor=Some(cursor),
        ),
      )
    }
    (FirstMembers(selection), [Inventory(page)]) => {
      guard page.entries
        is [Type(order_type, name="order"), Value(order, name="order")] &&
        order_type.document_id != order.document_id &&
        page.next_cursor is Some(cursor) else {
        fail("Expected the order type, order value, and a live member cursor")
      }
      (
        FinalMembers(order),
        Inventory(request_id~, selection~, page_size=2, cursor=Some(cursor)),
      )
    }
    (FinalMembers(order), [Inventory(page)]) => {
      guard page.entries is [Value(total, name="total-in-USD")] &&
        page.next_cursor is None else {
        fail("Expected total-in-USD on the final inventory page")
      }
      (FinalValue(order), Document(request_id~, document_id=total.document_id))
    }
    (FinalValue(order), [Document(document)]) => {
      let reference = @wire.string(
        @wire.field(orders_body(document, "total-in-USD"), "Reference"),
      )
      guard reference == "\{order.package_name}:\{order.module_path}#order" else {
        fail(
          "The final-page reference did not resolve to the inventoried order value",
        )
      }
      (ReferencedValue, Document(request_id~, document_id=order.document_id))
    }
    (ReferencedValue, [Document(document)]) => {
      let literal = @wire.field(orders_body(document, "order"), "Literal")
      let bytes = @utf8.encode(
        @wire.integer_text(@wire.field(literal, "IntegerLiteral")) + "\n",
      )
      let chunk = @access.ArtifactChunk::from_json({
        "path": "order.txt",
        "offset": 0,
        "decodedByteLength": bytes.length(),
        "sha256": @crypto.bytes_to_hex_string(@crypto.sha256(bytes)),
        "content": @base64.encode(bytes[:]),
        "end": true,
      })
      return Complete(session_id=advance.session_id, artifacts=[chunk], diagnostics=[])
    }
    _ => fail("Unexpected delivery in the orders generation exchange")
  }
  phase.val = next
  orders_pending(advance.session_id, advance.round + 1, request)
}

///|
fn orders_backend(mode : ReviewMode) -> @mep.BoundedBackend raise {
  @mep.BoundedBackend::new(review_support(mode), start => {
    let phase = Ref(RootModules)
    let first = orders_pending(
      start.session_id,
      1,
      Inventory(
        request_id="orders-1",
        selection="root",
        page_size=1,
        cursor=None,
      ),
    )
    let operation = @mep.BoundedOperation::new(
      advance=advance => {
        if mode is LeasePause("reject", _) && phase.val is ReferencedValue {
          return Failed(
            session_id=start.session_id,
            first_diagnostic={
              "severity": "error",
              "code": "fixture.refused",
              "message": "fixture rejected after the final read",
            },
            other_diagnostics=[],
          )
        }
        orders_advance(phase, advance) catch {
          error =>
            Failed(
              session_id=start.session_id,
              first_diagnostic={
                "severity": "error",
                "code": "fixture.orders_delivery",
                "message": error.to_string(),
              },
              other_diagnostics=[],
            )
        }
      },
      release=() => (),
    )
    (first, operation)
  })
}

///|
async fn main {
  let mode = review_mode(@env.args())
  let backend = match mode {
    Orders | LeasePause(_, _) => orders_backend(mode)
    _ => review_backend(mode)
  }
  let session = @mep.Session::new(bounded=Some(backend))
  let decoder = @mep.Decoder::new()
  let started = Ref(false)
  while @stdio.stdin.read_some(max_len=32768) is Some(chunk) {
    for body in decoder.feed(chunk) {
      if !(mode is Orders) {
        review_before_message(
          mode,
          @wire.parse_bounded(@utf8.decode(body[:])),
          started,
        )
      }
      if session.receive(body) is Some(response) {
        @stdio.stdout.write(@mep.encode_frame(response.stringify()))
      }
      if session.exited() {
        return
      }
    }
  }
  decoder.finish()
}
