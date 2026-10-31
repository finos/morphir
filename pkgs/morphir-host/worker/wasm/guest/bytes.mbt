///|
/// The request and response of the call that runs, shared with the byte
/// callbacks.
priv struct Exchange {
  mut input : Bytes
  output : Array[Byte]
  response_limit : Int32
  mut busy : Bool
}

///|
priv enum State {
  Ready
  Exited
  Failed
}

///|
/// A `morphir-bytes-v1` guest. The host provides exactly `input_len`,
/// `input_byte` and `output_byte`, and reads the result of `handle`: a
/// positive value is the length of the response, 0 is exit, -2 is a
/// notification and -1 is a failure. -2 for a request, a message with an
/// `id`, is a failure: the host does not wait for a response that the guest
/// will not give. Requests and responses must be valid UTF-8.
pub struct BytesGuest {
  priv instance : @engine.Instance
  priv exchange : Exchange
  priv budget : @engine.Budget?
  priv deadline : @engine.Deadline
  priv request_limit : Int32
  priv mut state : State
}

///|
fn callback_error(text : String) -> @engine.HostError {
  HostError("morphir_bytes_v1: \{text}")
}

///|
fn BytesGuest::load(
  prepared : @wasm.PreparedModule,
  call~ : CallBounds,
  limits~ : @worker.Limits,
  ceiling~ : @wasm.MemoryCeiling,
) -> BytesGuest raise @worker.LaunchError {
  let engine = @engine.Engine::default()
  let module_ = compile(engine, prepared)
  let exchange = {
    input: b"",
    output: [],
    response_limit: limits.response_bytes,
    busy: false,
  }
  let callbacks = @wasm.bytes_namespace
  let imports = @engine.Imports::new()
    .host(callbacks, "input_len", @engine.Signature::new([], [I32]), (_, _) => {
      guard exchange.busy else { raise callback_error("called outside a call") }
      [I32(exchange.input.length())]
    })
    .host(callbacks, "input_byte", @engine.Signature::new([I32], [I32]), (
      _,
      args,
    ) => {
      guard exchange.busy && args is [I32(index)] else {
        raise callback_error("input_byte called outside a call")
      }
      guard index >= 0 && index < exchange.input.length() else {
        raise callback_error("input_byte index \{index} out of range")
      }
      [I32(exchange.input[index].to_int())]
    })
    .host(callbacks, "output_byte", @engine.Signature::new([I32], []), (_, args) => {
      guard exchange.busy && args is [I32(value)] else {
        raise callback_error("output_byte called outside a call")
      }
      guard value >= 0 && value <= 255 else {
        raise callback_error("output_byte value \{value} is not a byte")
      }
      guard exchange.output.length() < exchange.response_limit else {
        raise callback_error(
          "the response is over \{exchange.response_limit} bytes",
        )
      }
      exchange.output.push(value.to_byte())
      []
    })
  let memory_ceiling = @engine.PageCount::parse(ceiling.pages()) catch {
    _ => raise LaunchFailed("invalid memory ceiling")
  }
  let instance = module_.instantiate(imports, memory_ceiling~) catch {
    error =>
      raise LaunchFailed(
        "the guest did not instantiate: \{@debug.to_string(error)}",
      )
  }
  let (budget, deadline) = call.engine()
  {
    instance,
    exchange,
    budget,
    deadline,
    request_limit: limits.request_bytes,
    state: Ready,
  }
}

///|
fn BytesGuest::fail(
  self : BytesGuest,
  fault : @worker.GuestFault,
) -> GuestError {
  self.state = Failed
  Faulted(fault)
}

///|
fn valid_utf8(bytes : Bytes) -> Bool {
  (@utf8.decode(bytes[:], ignore_bom=false) catch { _ => return false })
  |> ignore
  true
}

///|
pub extend BytesGuest with Guest::{exchange}

///|
/// Gives one request or notification to the guest's `handle`.
pub impl Guest for BytesGuest with fn exchange(self, request) {
  match self.state {
    Ready => ()
    Exited => raise Faulted(Failure("the guest has exited"))
    Failed => raise Faulted(Failure("the guest failed before"))
  }
  guard request.length() <= self.request_limit else {
    raise self.fail(Failure("the request is over \{self.request_limit} bytes"))
  }
  guard valid_utf8(request) else {
    raise self.fail(Failure("the request is not valid UTF-8"))
  }
  let (is_notification, _) = notification(request) catch { _ => (false, false) }
  let exchange = self.exchange
  exchange.input = request
  exchange.output.clear()
  exchange.busy = true
  let results = self.instance.call(
    @wasm.handle_export,
    [],
    budget?=self.budget,
    deadline=self.deadline,
  ) catch {
    error => {
      exchange.busy = false
      raise self.fail(call_fault(error))
    }
  }
  exchange.busy = false
  exchange.input = b""
  if self.instance.take_refused_grow() {
    raise self.fail(MemoryLimit("memory.grow beyond the ceiling was refused"))
  }
  let written = exchange.output.length()
  guard results is [I32(result)] else {
    raise self.fail(Failure("handle returned \{@debug.to_string(results)}"))
  }
  match result {
    -1 =>
      raise self.fail(
        Failure("the guest reported a failure: handle returned -1"),
      )
    0 if written == 0 => {
      self.state = Exited
      Exit
    }
    -2 if written == 0 && is_notification => Notified
    -2 if written == 0 =>
      raise self.fail(
        Failure("the guest returned -2 for a request; -2 is for notifications"),
      )
    length if length > 0 && length == written => {
      let response = Bytes::from_array(exchange.output)
      guard valid_utf8(response) else {
        raise self.fail(Failure("the response is not valid UTF-8"))
      }
      Response(response)
    }
    _ =>
      raise self.fail(
        Failure("the guest returned \{result}, but wrote \{written} bytes"),
      )
  }
}
