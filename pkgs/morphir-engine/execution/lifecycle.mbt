///|
pub(all) suberror LifecycleError {
  CleanupFailed(Error?, Error)
}

///|
pub(all) struct Failure {
  phase : String
  cause : Error?
  cleanup : Error?
}

///|
pub(all) struct Terminal {
  id : String
  status : String
}

///|
pub fn Failure::cancelled(self : Failure) -> Bool {
  self.cause is Some(@protocol.Invalid("Cancelled"))
}

///|
fn bounded_error(error : Error) -> String {
  let text = match error {
    @protocol.Invalid(message)
    | @config.Invalid(message)
    | @scheme.Invalid(message) => message
    @data.Invalid(code, message) => code + ": " + message
    @moonbit.Invalid(code, context, message) =>
      code + ": " + context + " " + message
    _ => error.to_string()
  }
  if text.length() > 512 {
    text[:512].to_owned()
  } else {
    text
  }
}

///|
pub fn Failure::to_json(self : Failure) -> Json {
  {
    "phase": self.phase,
    "cause": self.cause
    .map(e => Json::string(bounded_error(e)))
    .unwrap_or(Json::null()),
    "cleanup": self.cleanup
    .map(e => Json::string(bounded_error(e)))
    .unwrap_or(Json::null()),
  }
}

///|
/// A required matrix cannot infer success from a partial set or matching errors.
pub fn matrix_successful(
  required : Array[String],
  reports : Array[Report],
) -> Bool {
  if required.is_empty() || required.length() != reports.length() {
    return false
  }
  let seen = Map([])
  for target in required {
    if seen.contains(target) {
      return false
    }
    seen[target] = true
    let lane = reports.filter(r => r.target == target)
    if lane.length() != 1 || !lane[0].successful() || lane[0].evaluator is None {
      return false
    }
    if lane[0].evaluator != reports[0].evaluator ||
      lane[0].comparison.to_json() != reports[0].comparison.to_json() {
      return false
    }
    if lane[0].terminals.map(t => t.id) != reports[0].terminals.map(t => t.id) {
      return false
    }
  }
  true
}

///|
/// Native rich values and opaque annotations remain Ion in verification receipts.
pub fn Report::to_ion(self : Report) -> @ion.IonValue raise {
  guard self.to_json() is Object(fields) else { abort("report object") }
  ignore(fields.remove("calls"))
  ignore(fields.remove("extensions"))
  let names = fields.keys().collect()
  names.sort()
  let result = names.map(name => (name, evidence_ion(fields[name])))
  result.push(
    (
      "calls",
      @ion.IonValue::list(
        self.calls.map(c => {
          @protocol.record([
            ("id", @ion.IonValue::string(c.id)),
            ("actual", c.actual.to_ion()),
            (
              "expected",
              c.expected
              .map(v => v.to_ion())
              .unwrap_or(@ion.IonValue::untyped_null()),
            ),
            ("matches", @ion.IonValue::bool(c.matches)),
            (
              "mismatch_path",
              c.mismatch_path
              .map(@ion.IonValue::string)
              .unwrap_or(@ion.IonValue::untyped_null()),
            ),
          ])
        }),
      ),
    ),
  )
  result.push(
    (
      "extensions",
      match self.extensions {
        Some(bytes) =>
          @ion_binary.read_binary_value(
            bytes[:],
            fuel=Limited(@ion.Budget(128)),
          )
        None => @ion.IonValue::untyped_null()
      },
    ),
  )
  @protocol.record(result)
}

///|
fn evidence_ion(value : Json) -> @ion.IonValue raise {
  match value {
    Null => @ion.IonValue::untyped_null()
    String(s) => @ion.IonValue::string(s)
    True => @ion.IonValue::bool(true)
    False => @ion.IonValue::bool(false)
    Number(n, ..) => @ion.IonValue::float(n)
    Array(items) => @ion.IonValue::list(items.map(evidence_ion))
    Object(fields) => {
      let names = fields.keys().collect()
      names.sort()
      @protocol.record(names.map(name => (name, evidence_ion(fields[name]))))
    }
  }
}

///|
pub fn Report::status(self : Report) -> String {
  if self.failure is Some(f) {
    return if f.cancelled() { "cancelled" } else { "failed" }
  }
  if self.successful() {
    "succeeded"
  } else if self.terminals.any(t => t.status == "mismatch") {
    "mismatch"
  } else {
    "failed"
  }
}
