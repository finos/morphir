///|
/// These are internal requests, decoded from the frozen private host boundary.
priv enum SchemeOperation {
  SubmitScheme
  SubmitNativePolicy
  SubmitHttpPolicy
  PlanScheme
  ClaimScheme
  ReplanScheme
}

///|
/// Keep payload admission in the owning handler. Only this decoder constructs
/// requests, so unknown operation names cannot reach a registered sender.
priv enum BoundaryRequest {
  Submit(Map[String, Json])
  Query(Map[String, Json])
  Cancel(Map[String, Json])
  Release(Map[String, Json])
  Claim(Map[String, Json])
  Complete(Map[String, Json])
  Scheme(SchemeOperation, Map[String, Json])
}

///|
fn BoundaryRequest::decode(source : String) -> BoundaryRequest raise {
  let fields = command(source)
  match string(fields["op"]) {
    "submit" => Submit(fields)
    "query" => Query(fields)
    "cancel" => Cancel(fields)
    "release" => Release(fields)
    "claim" => Claim(fields)
    "complete" => Complete(fields)
    "submit-scheme" => Scheme(SubmitScheme, fields)
    "submit-native-policy" => Scheme(SubmitNativePolicy, fields)
    "submit-http-policy" => Scheme(SubmitHttpPolicy, fields)
    "plan-scheme" => Scheme(PlanScheme, fields)
    "claim-scheme" => Scheme(ClaimScheme, fields)
    "replan-scheme" => Scheme(ReplanScheme, fields)
    _ => raise Invalid("workbench.host_operation")
  }
}

///|
let boundary_sender : @mediator.Sender[Host, BoundaryRequest, Json] = @mediator.sender(fn(
    host,
    request,
  ) raise {
    host.dispatch(request)
  },
)
