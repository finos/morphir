///|
fn invalid(message : String) -> Unit raise {
  raise @ion.IonError::DataModel(message)
}

///|
// The build record is the JSON-compatible typed host boundary. Metadata stays
// an Ion value and never passes through JavaScript's numeric representation.
fn checked_json(value : @ion.IonValue) -> Json raise {
  let json = @ion_json.to_json(value)
  if !@ion_json.to_ion(json).equals(value) {
    invalid(
      "Value cannot be represented losslessly by the checked JSON boundary",
    )
  }
  let work = [json]
  while !work.is_empty() {
    match work.pop().unwrap() {
      Number(n, ..) =>
        if n.is_nan() ||
          n.is_inf() ||
          n.abs() > 9007199254740991.0 ||
          n.floor() != n {
          invalid("JSON boundary requires exact safe integers")
        }
      Array(xs) => work.append(xs)
      Object(fields) => work.append(fields.values().collect())
      Null | True | False | String(_) => ()
    }
  }
  json
}

///|
#export_name("encode_manifest")
pub fn encode_manifest(
  build : String,
  metadata : String,
  encoding : String,
) -> String {
  try {
    let build = @ion_json.read_json(build[:])
    checked_json(build) |> ignore
    let metadata = @ion_text.read_ion(metadata[:])
    let record = @ion.IonValue::from_fields([
      @ion.Field::new("build", build),
      @ion.Field::new("metadata", metadata),
    ])
    let bytes = match encoding {
      "ion" =>
        @ion_binary.write_binary_value(
          record.with_annotation(
            @ion.SymbolToken::new("morphir_assembly_artifact_v1"),
          ),
        )
      "json" => {
        checked_json(metadata) |> ignore
        @utf8.encode(@ion_json.write_json(record))
      }
      _ => {
        invalid("Unsupported manifest encoding")
        b""
      }
    }
    Json::object({
      "bytes": Json::array(
        bytes.to_array().map(b => Json::number(b.to_int().to_double())),
      ),
    }).stringify()
  } catch {
    error =>
      Json::object({ "error": Json::string(error.to_string()) }).stringify()
  }
}

///|
#export_name("decode_manifest")
pub fn decode_manifest(input : Bytes, encoding : String) -> String {
  try {
    let record = match encoding {
      "ion" => {
        let record = @ion_binary.read_binary_value(input[:])
        let annotations = record.annotations()
        if annotations.length() != 1 ||
          annotations[0].text() != Some("morphir_assembly_artifact_v1") {
          invalid("Missing assembly manifest annotation")
        }
        record
      }
      "json" => @ion_json.read_json(@utf8.decode(input)[:])
      _ => {
        invalid("Unsupported manifest encoding")
        @ion.IonValue::untyped_null()
      }
    }
    guard record.kind() is @ion.Struct(fields) else {
      invalid("Expected manifest record")
      return ""
    }
    let mut build = None
    let mut metadata = None
    for field in fields {
      match field.name().text() {
        Some("build") if build is None => build = Some(field.value())
        Some("metadata") if metadata is None => metadata = Some(field.value())
        _ => invalid("Unknown or duplicate manifest field")
      }
    }
    guard (build, metadata) is (Some(build), Some(metadata)) else {
      invalid("Incomplete manifest record")
      return ""
    }
    if encoding == "json" {
      checked_json(metadata) |> ignore
    }
    Json::object({
      "build": checked_json(build),
      "metadataIon": Json::string(@ion_text.write_ion(metadata)),
    }).stringify()
  } catch {
    error =>
      Json::object({ "error": Json::string(error.to_string()) }).stringify()
  }
}
