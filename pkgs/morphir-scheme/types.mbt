///|
/// Errors are values at every embedding boundary; no language error aborts the host.
pub(all) suberror SchemeError {
  Syntax(String, Int32)
  Unbound(String)
  Invalid(String)
  Domain(String, String)
  Unsupported(String)
  Limit(String)
  Stage(String, String)
} derive(Eq, Debug)

///|
pub extend SchemeError with Eq::{equal, not_equal}

///|
pub extend SchemeError with @debug.Debug::{to_repr}

///|
/// Exact integers and normalized rational numbers, or finite inexact reals.
pub(all) enum Number {
  Integer(@bigint.BigInt)
  Rational(@bigint.BigInt, @bigint.BigInt)
  Real(Double)
} derive(Eq, Debug)

///|
pub extend Number with Eq::{equal, not_equal}

///|
pub extend Number with @debug.Debug::{to_repr}

///|
/// Reader data is separate from runtime values and Morphir IR.
pub(all) enum Datum {
  Number(Number)
  Boolean(Bool)
  Character(Char)
  Text(String)
  Symbol(String)
  Sequence(Array[Datum], Datum?)
  Vector(Array[Datum])
} derive(Eq, Debug)

///|
pub extend Datum with Eq::{equal, not_equal}

///|
pub extend Datum with @debug.Debug::{to_repr}

///|
/// Closures carry an owning runtime and an arena index, avoiding environment cycles.
pub struct Closure {
  priv owner : Int32
  priv environment : Int32
  priv parameters : Array[String]
  priv rest : String?
  priv body : Array[Datum]
}

///|
/// Typed IR values let host procedures transform IR without string substitution.
pub(all) enum Value {
  Number(Number)
  Boolean(Bool)
  Character(Char)
  Text(String)
  Symbol(String)
  Nil
  Pair(Value, Value)
  Vector(Array[Value])
  Record(Map[String, Value])
  Tagged(String, Array[Value])
  Unit
  Closure(Closure)
  Native(String)
  NativeFunction((Runtime, Array[Value]) -> Value raise)
  IR(@ir.Value)
  IRType(@ir.Type)
  IRFile(@ir.IRFile)
}

///|
struct Frame {
  parent : Int32?
  bindings : Map[String, Value]
  pending : Map[String, Bool]
}

///|
/// Limits apply to one public evaluation or call, including nested host callbacks.
pub(all) struct Limits {
  steps : Int32
  depth : Int32
  frames : Int32
} derive(Eq, Debug)

///|
pub fn Limits::default() -> Limits {
  { steps: 1000000, depth: 256, frames: 100000, }
}

///|
pub extend Limits with Eq::{equal, not_equal}

///|
pub extend Limits with @debug.Debug::{to_repr}

///|
/// A persistent session. Native procedures receive the active runtime explicitly.
pub struct Runtime {
  priv owner : Int32
  priv frames : Array[Frame]
  priv natives : Map[String, (Runtime, Array[Value]) -> Value raise]
  priv native_arities : Map[String, Int32]
  priv limits : Limits
  priv mut fuel : Int32
  priv mut depth : Int32
  priv mut cancelled : () -> Bool
  priv mut active : Bool
}

///|
let next_owner : Ref[Int32] = { val: 0, }

///|
pub fn Runtime::new(
  limits~ : Limits = Limits::default(),
) -> Runtime raise SchemeError {
  if limits.steps <= 0 || limits.depth <= 0 || limits.frames <= 0 {
    raise Invalid("Runtime limits must be positive")
  }
  next_owner.val += 1
  let runtime = {
    owner: next_owner.val,
    frames: [{ parent: None, bindings: Map([]), pending: Map([]), }],
    natives: Map([]),
    native_arities: Map([]),
    limits,
    fuel: limits.steps,
    depth: 0,
    active: false,
    cancelled: fn() { false },
  }
  runtime.install_builtins()
  runtime
}

///|
pub fn Runtime::set_global(
  self : Runtime,
  name : String,
  value : Value,
) -> Unit {
  self.frames[0].bindings[name] = value
}

///|
pub fn Runtime::define_native(
  self : Runtime,
  name : String,
  procedure : (Runtime, Array[Value]) -> Value raise,
) -> Unit {
  self.natives[name] = procedure
  self.set_global(name, Native(name))
}

///|
pub fn Runtime::has_native(self : Runtime, name : String) -> Bool {
  self.natives.contains(name)
}

///|
pub fn Runtime::native_arity(self : Runtime, name : String) -> Int32? {
  self.native_arities.get(name)
}

///|
/// Host bindings reject accidental replacement. An explicit override uses
/// replace_native_binding instead.
pub fn Runtime::register_native_binding(
  self : Runtime,
  name : String,
  arity : Int32,
  procedure : (Runtime, Array[Value]) -> Value raise,
) -> Unit raise SchemeError {
  if arity < 0 {
    raise Invalid("Native binding arity must be nonnegative")
  }
  if self.has_native(name) {
    raise Invalid("Duplicate native binding: " + name)
  }
  self.define_native(name, procedure)
  self.native_arities[name] = arity
}

///|
pub fn Runtime::replace_native_binding(
  self : Runtime,
  name : String,
  arity : Int32,
  procedure : (Runtime, Array[Value]) -> Value raise,
) -> Unit raise SchemeError {
  if arity < 0 || !self.has_native(name) {
    raise Invalid("No native binding to replace: " + name)
  }
  self.define_native(name, procedure)
  self.native_arities[name] = arity
}

///|
pub fn Runtime::lookup(
  self : Runtime,
  name : String,
) -> Value raise SchemeError {
  self.lookup_in(0, name)
}

///|
fn Runtime::lookup_in(
  self : Runtime,
  environment : Int32,
  name : String,
) -> Value raise SchemeError {
  let mut scope = Some(environment)
  while scope is Some(index) {
    if self.frames[index].pending.contains(name) {
      raise Invalid("Uninitialized recursive binding: " + name)
    }
    if self.frames[index].bindings.get(name) is Some(value) {
      return value
    }
    scope = self.frames[index].parent
  }
  raise Unbound(name)
}

///|
fn Runtime::frame(self : Runtime, parent : Int32) -> Int32 raise SchemeError {
  if self.frames.length() >= self.limits.frames {
    raise Limit("environment frames")
  }
  let index = self.frames.length()
  self.frames.push({
    parent: Some(parent),
    bindings: Map([]),
    pending: Map([]),
  })
  index
}

///|
fn Runtime::tick(self : Runtime) -> Unit raise SchemeError {
  if (self.cancelled)() {
    raise Limit("cancelled")
  }
  self.fuel -= 1
  if self.fuel < 0 {
    raise Limit("evaluation steps")
  }
}

///|
pub fn Value::as_text(self : Value) -> String raise SchemeError {
  match self {
    Text(text) => text
    _ => raise Invalid("Expected string")
  }
}

///|
pub fn Value::as_ir(self : Value) -> @ir.Value raise SchemeError {
  match self {
    IR(value) => value
    _ => raise Invalid("Expected Morphir IR value")
  }
}

///|
pub fn Value::as_file(self : Value) -> @ir.IRFile raise SchemeError {
  match self {
    IRFile(value) => value
    _ => raise Invalid("Expected Morphir IR file")
  }
}

///|
pub fn list(values : Array[Value]) -> Value {
  let mut result = Nil
  for i = values.length() - 1; i >= 0; i = i - 1 {
    result = Pair(values[i], result)
  }
  result
}

///|
pub fn Value::to_array(self : Value) -> Array[Value] raise SchemeError {
  let result = []
  let mut rest = self
  while rest is Pair(head, tail) {
    result.push(head)
    rest = tail
  }
  if !(rest is Nil) {
    raise Invalid("Expected proper list")
  }
  result
}

///|
pub fn integer(text : String) -> Value raise SchemeError {
  match parse_number(text) {
    Some(Integer(_) as number) => Number(number)
    _ => raise Invalid("Expected integer")
  }
}

///|
pub fn truth(value : Value) -> Bool {
  !(value is Boolean(false))
}

///|
/// Include error payloads when reporting language failures to a host user.
pub fn error_message(error : Error) -> String {
  match error {
    Syntax(message, offset) =>
      "Syntax at character " + offset.to_string() + ": " + message
    Unbound(name) => "Unbound identifier: " + name
    Invalid(message) | Domain(_, message) => message
    Unsupported(message) => "Unsupported: " + message
    Limit(resource) => "Limit exceeded: " + resource
    Stage(stage, message) => stage + ": " + message
    _ => error.to_string()
  }
}

///|
/// Hosts may cancel a running evaluator at its next evaluation step.
pub fn Runtime::set_cancelled(self : Runtime, cancelled : () -> Bool) -> Unit {
  self.cancelled = cancelled
}
