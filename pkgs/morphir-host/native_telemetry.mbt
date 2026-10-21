///|
/// Explicit host capability. The caller supplies the built binary and its
/// receipt; binary verification does not attest a caller's build provenance.
pub struct NativeTelemetry {
  priv program : String
  priv helper : String
  priv endpoint : String
  priv protocol : String
  priv timeout : Int32
  priv binary_identity : String
}

///|
pub fn NativeTelemetry::new(
  program : String,
  helper : String,
  endpoint : String,
  protocol : String,
  pin : Json,
  timeout~ : Int32 = 1000,
) -> NativeTelemetry raise {
  let platform = if @platform.system_type() == "macos" {
    "darwin"
  } else {
    @platform.system_type()
  }
  if !@platform.process_supported() ||
    !((platform == "darwin" && @platform.architecture() == "arm64") ||
    (platform == "linux" && @platform.architecture() == "x64")) {
    raise @config.Invalid("observability.native_adapter_host_unavailable")
  }
  if program == "" ||
    helper == "" ||
    !native_telemetry_endpoint(endpoint) ||
    protocol != "http/json" ||
    timeout < 1 ||
    timeout > 5000 {
    raise @config.Invalid("observability.native_adapter_configuration")
  }
  if build_text(pin, "profile") != "morphir-native-otel-pin-v1" ||
    build_text(pin, "platform") != platform ||
    build_text(pin, "arch") != @platform.architecture() ||
    build_text(pin, "compilerVersion") != "0.10.16+b1a0e846e" ||
    build_text(pin, "otelArchiveIdentity") !=
    "51c7ad32e1344cae45cedfa8d5ee3836d3e22f17ff4796a45a8394917568033f" {
    raise @config.Invalid("observability.native_adapter_pin")
  }
  let binary_identity = build_text(pin, "binaryIdentity")
  if @platform.kind(program) != 1 ||
    binary_identity.length() != 64 ||
    binary_identity != @identity.sha256(@platform.read_bytes(program)) ||
    @platform.kind(helper) != 1 {
    raise @config.Invalid("observability.native_adapter_identity")
  }
  { program, helper, endpoint, protocol, timeout, binary_identity, }
}

///|
pub fn TelemetrySession::flush_native(
  self : TelemetrySession,
  adapter : NativeTelemetry,
  node : String,
) -> Unit {
  self.flush_to_process(
    node,
    adapter.helper,
    adapter.program,
    [adapter.endpoint, adapter.protocol, adapter.timeout.to_string()],
    timeout=adapter.timeout,
    program_identity=Some(adapter.binary_identity),
    clear_otel_environment=true,
  )
}

///|
/// Current adapter accepts an ASCII HTTP(S) origin with DNS/IPv4 authority and
/// optional TCP port. Path prefixes, credentials, queries, fragments and IPv6
/// are outside this profile. Validation is pure and usable during dry-run.
pub fn native_telemetry_endpoint(endpoint : String) -> Bool {
  if endpoint.length() > 4096 {
    return false
  }
  let authority = if endpoint.has_prefix("http://") {
    endpoint[7:].to_owned()
  } else if endpoint.has_prefix("https://") {
    endpoint[8:].to_owned()
  } else {
    return false
  }
  let pieces = authority.split(":").collect()
  if pieces.length() > 2 || pieces.is_empty() {
    return false
  }
  let host = pieces[0]
  if host.length() == 0 || host.length() > 253 {
    return false
  }
  if pieces.length() == 2 {
    let port = pieces[1]
    if port.length() == 0 ||
      port.length() > 5 ||
      !port.code_units().all(c => c is ('0'..<='9')) {
      return false
    }
    let number = @string.parse_int(port) catch { _ => 0 }
    if number < 1 || number > 65535 {
      return false
    }
  }
  let labels = host.split(".").collect()
  for label in labels {
    if label.length() == 0 ||
      label.length() > 63 ||
      !label
      .code_units()
      .all(c => c is ('0'..<='9' | 'a'..<='z' | 'A'..<='Z' | '-')) ||
      label.has_prefix("-") ||
      label.has_suffix("-") {
      return false
    }
  }
  if labels.length() == 4 &&
    labels.all(label => label.code_units().all(c => c is ('0'..<='9'))) {
    for label in labels {
      if label.length() > 3 || (label.length() > 1 && label.has_prefix("0")) {
        return false
      }
      let octet = @string.parse_int(label) catch { _ => 256 }
      if octet > 255 {
        return false
      }
    }
  }
  true
}
