///|
/// Round and request ownership shared by the bounded host and guest.
#derive(Eq, Debug)
pub struct GenerationRun {
  session_id : String
  snapshot_id : String
  limits : Limits
  round : Int32
  priv requests : Array[ReadRequest]
  priv request_ids : Array[String]
}

///|
pub extend GenerationRun with Eq::{equal, not_equal}

///|
pub extend GenerationRun with @debug.Debug::{to_repr}

///|
pub fn GenerationRun::new(request : Start) -> GenerationRun {
  {
    session_id: request.session_id,
    snapshot_id: request.snapshot.snapshot_id,
    limits: request.limits,
    round: 0,
    requests: [],
    request_ids: [],
  }
}

///|
fn DocumentDelivery::matches_bytes(self : DocumentDelivery) -> Bool {
  let bytes = @base64.decode(self.content) catch { _ => return false }
  bytes.length() == self.decoded_byte_length &&
  @base64.encode(bytes[:]) == self.content &&
  @crypto.bytes_to_hex_string(@crypto.sha256(bytes)) == self.sha256
}

///|
/// Verifies ordered delivery ownership, inventory and batch bounds, and the
/// integrity of document bytes before a peer can dispatch the advance.
pub fn GenerationRun::accepts(self : GenerationRun, advance : Advance) -> Bool {
  guard self.session_id == advance.session_id &&
    self.round == advance.round &&
    self.requests.length() == advance.deliveries.length() else {
    return false
  }
  let mut document_count = 0L
  let mut encoded = 0L
  let mut decoded = 0L
  for i, request in self.requests {
    let delivery = advance.deliveries[i]
    if delivery.request_id() != request.request_id() ||
      delivery.snapshot_id() != self.snapshot_id {
      return false
    }
    match (request, delivery) {
      (Inventory(page_size~, ..), Inventory(page)) if page.entries.length() <=
        page_size => ()
      (Document(document_id~, ..), Document(document)) if document.document_id ==
        document_id => {
        let size = document.decoded_byte_length.to_int64()
        let wire_size = document.content.length().to_int64()
        guard size >= 0L && wire_size == (size + 2L) / 3L * 4L else {
          return false
        }
        document_count += 1L
        encoded += wire_size
        decoded += size
      }
      _ => return false
    }
  }

  // Refuse the whole batch before base64 decoding any selected document.
  guard document_count <= self.limits.values[DOCUMENT_COUNT_INDEX] &&
    encoded <= self.limits.values[ENCODED_BYTES_INDEX] &&
    decoded <= self.limits.values[DECODED_BYTES_INDEX] else {
    return false
  }
  for delivery in advance.deliveries {
    if delivery is Document(document) && !document.matches_bytes() {
      return false
    }
  }
  true
}

///|
/// Admits a step for this operation and returns its next delivery round.
/// Complete and failed steps settle the operation.
pub fn GenerationRun::accept_step(
  self : GenerationRun,
  step : GenerationStep,
) -> GenerationRun? raise @wire.CodecError {
  guard step.session_id() == self.session_id else {
    raise @wire.Invalid(
      "model_access.invalid_session", "generation result names another session",
    )
  }
  let diagnostic_count = match step {
    Continue(diagnostics~, ..) | Complete(diagnostics~, ..) =>
      diagnostics.length().to_int64()
    Failed(other_diagnostics~, ..) => other_diagnostics.length().to_int64() + 1L
  }
  guard diagnostic_count <= self.limits.diagnostics_per_exchange().to_int64() else {
    raise @wire.Invalid(
      "model_access.diagnostics_limit", "generation result exceeds the diagnostics limit",
    )
  }
  guard step is Continue(round~, requests~, ..) else { return None }
  guard round.to_int64() == self.round.to_int64() + 1L &&
    round <= self.limits.rounds() else {
    raise @wire.Invalid(
      "model_access.invalid_round", "generation continuation has a stale or out-of-bounds round",
    )
  }
  guard requests.length() <= self.limits.outstanding_requests() else {
    raise @wire.Invalid(
      "model_access.requests_limit", "generation continuation exceeds the outstanding request limit",
    )
  }
  let new_ids : Array[String] = []
  for request in requests {
    let id = request.request_id()
    guard !self.request_ids.contains(id) && !new_ids.contains(id) else {
      raise @wire.Invalid(
        "model_access.duplicate_request", "generation continuation repeats a request ID",
      )
    }
    new_ids.push(id)
  }
  Some({
    ..self,
    round,
    requests: [..requests],
    request_ids: [..self.request_ids, ..new_ids],
  })
}
