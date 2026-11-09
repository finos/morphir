///|
/// Letters for a value name: `a`, `b`, ..., `z`, `ba`, ...
fn cost_name(index : Int32) -> String {
  let letters = StringBuilder()
  let mut rest = index
  let digits : Array[Char] = []
  while true {
    digits.push((rest % 26 + 'a'.to_int()).unsafe_to_char())
    rest = rest / 26
    if rest == 0 {
      break
    }
  }
  digits.rev_in_place()
  for digit in digits {
    letters.write_char(digit)
  }
  "value" + letters.to_string()
}

///|
/// A plain IR file of `count` public integer literal values in one module.
fn value_dense_ir(count : Int32) -> Bytes {
  let values = StringBuilder()
  for index in 0..<count {
    if index > 0 {
      values.write_char(',')
    }
    values.write_string(
      "\"\{cost_name(index)}\":{\"Public\":{\"ExpressionBody\":{\"inputTypes\":{},\"outputType\":\"morphir/SDK:basics#int\",\"body\":{\"Literal\":{\"IntegerLiteral\":42}}}}}",
    )
  }
  @utf8.encode(
    "{\"formatVersion\":4,\"distribution\":{\"Library\":{\"packageName\":\"generated\",\"dependencies\":{},\"def\":{\"modules\":{\"main\":{\"Public\":{\"types\":{},\"values\":{\{values.to_string()}}}}}}}}}",
  )
}

///|
/// Sets the attribute of every value input (`[name, attribute, type]` in
/// `inputTypes`) to its declared type. morphir-elm writes the inferred type
/// there, and the format 3 migration refuses an input whose two types differ,
/// as the Elm parity harness in pkgs/morphir-elm/conformance explains.
fn declared_input_types(json : Json) -> Unit {
  match json {
    Object(fields) =>
      for key, field in fields {
        if key == "inputTypes" && field is Array(inputs) {
          for input in inputs {
            if input is Array(parts) && parts.length() == 3 {
              parts[1] = parts[2]
            }
          }
        }
        declared_input_types(field)
      }
    Array(items) =>
      for item in items {
        declared_input_types(item)
      }
    _ => ()
  }
}

///|
/// A model file of any IR version, such as a morphir-elm make output, as an
/// IR 4 file, which the guest needs.
fn ir4_of_file(text : String) -> Bytes raise {
  let json = @json.parse(text)
  declared_input_types(json)
  let file = @versioned_json.read(json.stringify())
  @utf8.encode(@v4_json.write(@migration.to_current(file)))
}

///|
/// How one generate call of the portable guest ended.
priv enum Ending {
  Generated
  OverBudget
  Refused(String)
}

///|
/// How the portable guest generates `bytes` within `instructions`.
async fn generate_within(
  path : String,
  portable : Bytes,
  bytes : Bytes,
  instructions : Int32,
) -> Ending {
  let call = @guest.CallBounds::new(
    deadline_ms=600000,
    instructions=Some(instructions),
  )
  let mut ending = OverBudget
  with_host(path, call~, host => {
    let spec = wasm_spec(portable, abi=MorphirBytesV1)
    let claims = host.probe(spec).claims
    let wrapped = @worker.WrappedPlainIr::of(
      bytes,
      @json.parse(@utf8.decode(bytes[:])),
    )
    let generated = host.with_session(
      spec,
      expected=claims,
      offer=@worker.Offer::of_model(claims, wrapped.tuple),
      session => {
        session.generate(
          @worker.GenerateRequest::new(
            generate_params(wrapped.envelope, wrapped.tuple),
          ),
        )
      },
    )
    ending = match generated.class {
      Completed(_) => Generated
      Failed(Host(code=BudgetExhausted, ..)) => OverBudget
      _ => Refused(@debug.to_string(generated.class))
    }
  })
  ending
}

///|
/// The smallest budget, to within 1 %, at which the portable guest generates
/// `bytes`: a count, "over 2147483647", or the refusal of the guest.
async fn least_budget(path : String, portable : Bytes, bytes : Bytes) -> Json {
  let max = 2147483647L
  match generate_within(path, portable, bytes, max.to_int()) {
    Generated => ()
    OverBudget => return Json::string("over 2147483647")
    Refused(text) => return { "refused": text }
  }
  let mut low = 1000000L
  let mut high = max
  while high - low > high / 100L {
    let middle = low + (high - low) / 2L
    if generate_within(path, portable, bytes, middle.to_int()) is Generated {
      high = middle
    } else {
      low = middle
    }
  }
  Json::string(high.to_string())
}

///|
/// Measures the instruction cost of generateModel in the portable guest. Runs
/// only with MORPHIR_GUEST_COST set to a comma-separated list of value counts
/// or of absolute IR file paths, and prints one JSON line per entry.
async test "portable guest cost: the least budget that generates each input" {
  guard @env.get_env_var("MORPHIR_GUEST_COST") is Some(entries) &&
    entries != "" &&
    cli() is Some(path) &&
    prerequisite("MORPHIR_PORTABLE_GUEST") is Some(portable_path) else {
    return
  }
  let portable = @fs.read_file(portable_path).binary()
  for entry in entries.split(",") {
    let entry = entry.to_owned()
    let (label, bytes) = if entry.has_prefix("/") {
      (entry, ir4_of_file(@fs.read_file(entry).text()))
    } else {
      let count = @strconv.parse_int(entry)
      ("values=" + entry, value_dense_ir(count))
    }
    let least = least_budget(path, portable, bytes)
    let line : Json = {
      "input": label,
      "bytes": bytes.length(),
      "instructions": least,
    }
    println(line.stringify())
  }
}
