///|
/// Offline codec selection never grants a live host operation.
priv enum InvocationFormat {
  JsonText
  IonText
  IonBinary
}

///|
fn invocation_format(value : Json) -> InvocationFormat raise {
  match value {
    String("json") => JsonText
    String("ion-text") => IonText
    String("ion-binary") => IonBinary
    _ => raise @execution.Invalid("workbench.invalid_request")
  }
}

///|
fn InvocationFormat::name(self : InvocationFormat) -> String {
  match self {
    JsonText => "json"
    IonText => "ion-text"
    IonBinary => "ion-binary"
  }
}

///|
fn codec_fields(value : Json, names : Array[String]) -> Unit raise {
  guard value is Object(fields) &&
    fields.length() == names.length() &&
    fields.keys().all(name => names.contains(name)) else {
    raise @execution.Invalid("workbench.invalid_request")
  }
}

///|
fn codec_source(value : Json) -> Bytes raise {
  guard value is Object(fields) && fields.length() == 1 else {
    raise @execution.Invalid("workbench.invalid_request")
  }
  if fields.get("utf8") is Some(String(source)) {
    if source.length() > 1048576 {
      raise @execution.Invalid("workbench.input_limit")
    }
    let bytes = @utf8.encode(source)
    if bytes.length() > 1048576 {
      raise @execution.Invalid("workbench.input_limit")
    }
    guard @utf8.decode(bytes[:]) == source else {
      raise @execution.Invalid("workbench.invalid_request")
    }
    return bytes
  }
  guard fields.get("hex") is Some(String(source)) && source.length() % 2 == 0 else {
    raise @execution.Invalid("workbench.invalid_request")
  }
  if source.length() > 2097152 {
    raise @execution.Invalid("workbench.input_limit")
  }
  fn nibble(unit : UInt16) -> Int32 raise {
    if unit >= 48 && unit <= 57 {
      unit.to_int() - 48
    } else if unit >= 97 && unit <= 102 {
      unit.to_int() - 87
    } else {
      raise @execution.Invalid("workbench.invalid_request")
    }
  }
  let bytes : Array[Byte] = []
  for i in 0..<(source.length() / 2) {
    bytes.push(
      (nibble(source[i * 2]) * 16 + nibble(source[i * 2 + 1])).to_byte(),
    )
  }
  Bytes::from_array(bytes)
}

///|
fn decode_invocations(
  bytes : Bytes,
  format : InvocationFormat,
) -> @execution.Suite raise {
  @execution.Suite::decode(bytes, format.name()) catch {
    @execution.Invalid(code) => raise @execution.Invalid(code)
    _ =>
      raise @execution.Invalid(
        match format {
          JsonText => "workbench.invalid_json"
          IonText | IonBinary => "workbench.invalid_ion"
        },
      )
  }
}

///|
fn transcode_invocations(input : Json) -> Json raise {
  codec_fields(input, ["sourceFormat", "source", "targetFormat"])
  let source_format = invocation_format(field(input, "sourceFormat"))
  let target_format = invocation_format(field(input, "targetFormat"))
  let original = decode_invocations(
    codec_source(field(input, "source")),
    source_format,
  )
  let encoded = original.encode(target_format.name())
  // Decode actual output bytes, including the production byte budget. Ion
  // representations can differ; independent goldens compare semantic values.
  let decoded = decode_invocations(encoded, target_format)
  { "targetFormat": target_format.name(), "invocations": decoded.to_json() }
}

///|
fn comparison_policy(value : Json) -> @execution.ComparisonPolicy raise {
  match field(value, "profile") {
    String("morphir-comparison-exact-v1") => {
      codec_fields(value, ["profile"])
      @execution.Exact
    }
    String("morphir-comparison-approximate-v1") => {
      codec_fields(value, ["profile", "absolute", "relative"])
      guard field(value, "absolute") is Number(absolute, ..) &&
        field(value, "relative") is Number(relative, ..) else {
        raise @execution.Invalid("workbench.invalid_request")
      }
      let policy = @execution.Approximate(absolute, relative)
      policy.validate()
      policy
    }
    _ => raise @execution.Invalid("workbench.invalid_request")
  }
}

///|
fn compare_values(input : Json) -> Json raise {
  codec_fields(input, ["actual", "expected", "comparison"])
  let policy = comparison_policy(field(input, "comparison"))
  let actual = @execution.Value::from_json(field(input, "actual"))
  let expected = @execution.Value::from_json(field(input, "expected"))
  let matches = @execution.compare(actual, expected, policy~)
  let mismatch = @execution.mismatch_path(actual, expected, policy~)
  {
    "matches": matches,
    "mismatchPath": match mismatch {
      Some(path) => Json::string(path)
      None => Json::null()
    },
  }
}

///|
fn codec_comparison(id : Json, operation : Json, input : Json) -> Json {
  try {
    if @utf8.encode(input.stringify()).length() > 3145728 {
      return invalid(id, "workbench.input_limit")
    }
    let value = match operation {
      String("transcode-invocations") => transcode_invocations(input)
      String("compare-values") => compare_values(input)
      _ => raise @execution.Invalid("workbench.invalid_request")
    }
    // Bound retained compatibility evidence independently of source/output
    // encoding budgets. This does not change production codec acceptance.
    if @utf8.encode(value.stringify()).length() > 1048576 {
      return invalid(id, "workbench.output_limit")
    }
    { "id": id, "status": "ok", "value": value }
  } catch {
    @execution.Invalid(code) =>
      invalid(
        id,
        code.split(":").next().unwrap_or("workbench.codec_failure").to_owned(),
      )
    _ => invalid(id, "workbench.codec_failure")
  }
}
