///|
/// Refuses members that the object should not have.
fn only_members(
  fields : Map[String, Json],
  allowed : ArrayView[String],
  what : String,
  invalid~ : (String) -> ValueError = text => InvalidRuntime(text),
) -> Unit raise ValueError {
  for name, _ in fields {
    guard allowed.contains(name) else {
      raise invalid("\{what} has the member \{name}, which it cannot have")
    }
  }
}

///|
/// Decodes the `runtime` object that pins and the installed catalog share:
/// `{"kind": "process", "platform": <target triple>, "args": [...]}` or
/// `{"kind": "wasm"}` with an optional `"abi"`. An object that mixes the
/// members of both runtimes is refused.
pub fn WorkerRuntime::from_json(value : Json) -> WorkerRuntime raise ValueError {
  guard value is Object(fields) else {
    raise InvalidRuntime("the runtime is not an object")
  }
  match fields.get("kind") {
    Some(String("process")) => {
      only_members(fields, ["kind", "platform", "args"], "a process runtime")
      guard fields.get("platform") is Some(String(platform)) else {
        raise InvalidRuntime("a process runtime has no platform")
      }
      guard fields.get("args") is Some(Array(items)) else {
        raise InvalidRuntime("a process runtime has no argument array")
      }
      let args = items.map(item => {
        guard item is String(arg) else {
          raise InvalidRuntime("a process argument is not text")
        }
        arg
      })
      Process(platform=Platform::parse(platform), args~)
    }
    Some(String("wasm")) => {
      only_members(fields, ["kind", "abi"], "a WASM runtime")
      let abi = match fields.get("abi") {
        None => None
        Some(String(abi)) => Some(WasmAbi::parse(abi))
        Some(_) => raise InvalidRuntime("the WASM ABI is not text")
      }
      Wasm(abi~)
    }
    Some(String(kind)) => raise InvalidRuntime("unknown runtime kind \{kind}")
    _ => raise InvalidRuntime("the runtime has no kind")
  }
}

///|
pub extend WorkerRuntime with ToJson::{to_json}

///|
/// Encodes the runtime in the form that `from_json` reads, for the catalog.
pub impl ToJson for WorkerRuntime with fn to_json(self) {
  match self {
    Process(platform~, args~) =>
      {
        "kind": "process",
        "platform": platform.to_string(),
        "args": Json::array(args.map(Json::string)),
      }
    Wasm(abi=None) => { "kind": "wasm" }
    Wasm(abi=Some(abi)) => { "kind": "wasm", "abi": abi.to_string() }
  }
}

///|
/// Decodes an artifact file reference, `{"path": ..., "sha256": ...}`, with
/// the host's path style. A reference without a digest, or with another
/// member, is refused.
pub fn ArtifactRef::from_json(
  value : Json,
  style : PathStyle,
) -> ArtifactRef raise ValueError {
  guard value is Object(fields) else {
    raise InvalidArtifact("the artifact is not an object")
  }
  only_members(fields, ["path", "sha256"], "the artifact", invalid=text => {
    InvalidArtifact(text)
  })
  guard fields.get("path") is Some(String(path)) else {
    raise InvalidArtifact("the artifact has no path")
  }
  guard fields.get("sha256") is Some(String(digest)) else {
    raise InvalidArtifact("the artifact has no sha256 digest")
  }
  ArtifactRef::new(
    File(ArtifactPath::parse(path, style)),
    Sha256::parse(digest),
  )
}

///|
/// Decodes the `artifact` and `runtime` members of a pin or a catalog entry
/// into a worker specification. Other members belong to the caller and are
/// not read.
pub fn WorkerSpec::from_json(
  value : Json,
  style : PathStyle,
) -> WorkerSpec raise ValueError {
  guard value is Object(fields) &&
    fields.get("artifact") is Some(artifact) &&
    fields.get("runtime") is Some(runtime) else {
    raise InvalidRuntime("the specification needs an artifact and a runtime")
  }
  WorkerSpec::new(
    ArtifactRef::from_json(artifact, style),
    WorkerRuntime::from_json(runtime),
  )
}
