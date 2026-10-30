///|
priv enum ServiceOperation {
  Submit
  Query
  Cancel
  Release
}

///|
fn ServiceOperation::from_path(path : String) -> ServiceOperation raise {
  match path {
    "submit" => Submit
    "query" => Query
    "cancel" => Cancel
    "release" => Release
    _ => raise Invalid("workbench.native_operation")
  }
}

///|
fn ServiceOperation::from_native(operation : String) -> ServiceOperation? {
  match operation {
    "execution.submit" => Some(Submit)
    "execution.query" => Some(Query)
    "execution.cancel" => Some(Cancel)
    "execution.release" => Some(Release)
    _ => None
  }
}

///|
fn ServiceOperation::host_name(
  self : ServiceOperation,
  mode : SubmissionMode,
) -> String {
  match (self, mode) {
    (Submit, SelectedScheme) => "submit-native-policy"
    (Submit, WholeModel) => "submit"
    (Query, _) => "query"
    (Cancel, _) => "cancel"
    (Release, _) => "release"
  }
}

///|
/// Raw bodies retain duplicate-aware decoding in the shared execution owner.
priv enum ServiceRequest {
  Session
  Execution(ServiceOperation, String, SubmissionMode)
}

///|
let service_sender : @mediator_async.Sender[Service, ServiceRequest, Json] = @mediator_async.sender(fn(
    service,
    request,
  ) {
    match request {
      Session =>
        {
          "ok": true,
          "value": {
            "profile": "morphir/workbench/host",
            "contractVersion": "0.2.0-draft.1",
            "offer": service.offer,
          },
        }
      Execution(operation, body, mode) =>
        service.host.handle(
          ({ "op": operation.host_name(mode), "body": body } : Json).stringify(),
        )
    }
  },
)
