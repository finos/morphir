///|
#cfg(target="js")
let pending_completion : Ref[@js_async.Promise[Int32]?] = Ref(None)

///|
#cfg(target="js")
fn remember_completion(promise : @js_async.Promise[Int32]) -> Unit {
  pending_completion.val = Some(promise)
}

///|
/// Await the owning helper inside the mediator's cancellation/timing/log scope.
#cfg(target="js")
async fn complete_command(status : Int32) -> Int32 {
  match pending_completion.val {
    Some(promise) => {
      pending_completion.val = None
      promise.wait()
    }
    None => status
  }
}

///|
#cfg(not(target="js"))
fn complete_command(status : Int32) -> Int32 {
  status
}
