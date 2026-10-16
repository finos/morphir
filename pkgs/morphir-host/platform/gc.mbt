///|
/// Explicit embedding ABI. Strings cross as UTF-16 code units through opaque handles.
#external
priv type Text

///|
fn begin() -> Text = "morphir_host_v1" "begin"

///|
fn append(text : Text, code : Int32) -> Unit = "morphir_host_v1" "append"

///|
fn length(text : Text) -> Int32 = "morphir_host_v1" "length"

///|
fn at(text : Text, i : Int32) -> Int32 = "morphir_host_v1" "at"

///|
fn request(op : Text, a : Text, b : Text) -> Text = "morphir_host_v1" "request"

///|
fn external(text : String) -> Text {
  let result = begin()
  for code in text.code_units() {
    append(result, code.to_int())
  }
  result
}

///|
fn call(op : String, a~ : String = "", b~ : String = "") -> Json raise {
  let response = request(external(op), external(a), external(b))
  let text = StringBuilder()
  for i = 0; i < length(response); i = i + 1 {
    text.write_char(at(response, i).unsafe_to_char())
  }
  match @json.parse(text.to_string()) {
    Object(fields) =>
      match fields.get("error") {
        Some(String(message)) => raise IOError(message)
        _ => fields.get("value").unwrap_or(Json::null())
      }
    _ => raise IOError("Invalid morphir_host_v1 response")
  }
}

///|
fn text(op : String, a~ : String = "") -> String raise {
  match call(op, a~) {
    String(s) => s
    _ => raise IOError("Expected host string")
  }
}

///|
fn array(op : String, a~ : String = "") -> Array[String] raise {
  match call(op, a~) {
    Array(items) =>
      items.map(fn(item) raise {
        match item {
          String(s) => s
          _ => raise IOError("Expected host strings")
        }
      })
    _ => raise IOError("Expected host array")
  }
}

///|
pub fn args() -> Array[String] {
  array("args") catch {
    _ => []
  }
}

///|
pub fn cwd() -> String {
  text("cwd") catch {
    _ => "."
  }
}

///|
pub fn environment() -> Map[String, String] {
  let result = Map([])
  try {
    if call("environment") is Object(fields) {
      for key, value in fields {
        if value is String(s) {
          result[key] = s
        }
      }
    }
  } catch {
    _ => ()
  }
  result
}

///|
pub fn read(path : String) -> String raise {
  text("read", a=path)
}

///|
pub fn write(path : String, content : String) -> Unit raise {
  ignore(call("write", a=path, b=content))
}

///|
pub fn list(path : String) -> Array[String] raise {
  array("list", a=path)
}

///|
pub fn kind(path : String) -> Int32 raise {
  match call("kind", a=path) {
    Number(n, ..) => n.to_int()
    _ => raise IOError("Expected host kind")
  }
}

///|
pub fn mkdir(path : String) -> Unit raise {
  ignore(call("mkdir", a=path))
}

///|
pub fn remove_file(path : String) -> Unit raise {
  ignore(call("remove_file", a=path))
}

///|
pub fn remove_dir(path : String) -> Unit raise {
  ignore(call("remove_dir", a=path))
}

///|
pub fn rename(a : String, b : String) -> Unit raise {
  ignore(call("rename", a~, b~))
}

///|
pub fn stderr(s : String) -> Unit {
  ignore(call("stderr", a=s)) catch {
    _ => ()
  }
}

///|
pub fn exit(code : Int32) -> Unit {
  ignore(call("exit", a=code.to_string())) catch {
    _ => ()
  }
}

///|
pub fn arguments() -> Array[String] {
  let values = args()
  if values.is_empty() {
    []
  } else {
    values[1:].to_owned()
  }
}

///|
pub fn system_type() -> String {
  text("system_type") catch {
    _ => "unknown"
  }
}

///|
pub fn architecture() -> String {
  text("architecture") catch {
    _ => "unknown"
  }
}

///|
pub fn process_supported() -> Bool {
  (call("process_supported") is True) catch {
    _ => false
  }
}

///|
pub fn temporary() -> String raise {
  text("temporary")
}

///|
pub fn process(
  program : String,
  args : Array[String],
  cwd : String,
  home : String,
  timeout : Int32,
) -> Json raise {
  call(
    "process",
    a=Json::object(
      Map::from_array([
        ("program", Json::string(program)),
        ("args", Json::array(args.map(Json::string))),
        ("cwd", Json::string(cwd)),
        ("home", Json::string(home)),
        ("timeout", Json::number(timeout.to_double())),
      ]),
    ).stringify(),
  )
}

///|
/// Additive v1 operations use JSON byte arrays, never UTF-8 coercion.
pub fn read_bytes(path : String) -> Bytes raise {
  match call("read_bytes", a=path) {
    Array(items) =>
      Bytes::from_array(
        items.map(fn(item) raise {
          match item {
            Number(n, ..) if n >= 0.0 &&
              n <= 255.0 &&
              n == n.to_int().to_double() => n.to_int().to_byte()
            _ => raise IOError("Invalid host byte")
          }
        }),
      )
    _ => raise IOError("Expected host bytes; host.byte_read_required")
  }
}

///|
pub fn write_bytes(path : String, content : Bytes) -> Unit raise {
  ignore(
    call(
      "write_bytes",
      a=path,
      b=Json::array(
        content
        .to_array()
        .map(fn(byte) { Json::number(byte.to_int().to_double()) }),
      ).stringify(),
    ),
  )
}

///|
pub fn bytes_supported() -> Bool {
  (call("bytes_supported") is True) catch {
    _ => false
  }
}
