///|
pub(all) suberror VSpecError {
  VSpecError(String)
} derive(Eq, Debug)

///|
pub extend VSpecError with Eq::{equal, not_equal}

///|
pub extend VSpecError with @debug.Debug::{to_repr}

///|
priv enum Token {
  Str(String)
  Sym(String)
  Open
  Close
  OpenList
  CloseList
  Comma
}

///|
priv enum Expr {
  Str(String)
  Unit
  List(Array[Expr])
  Pair(Array[Expr])
  App(String, Array[Expr])
}

///|
fn tokenize(text : String) -> Array[Token] raise VSpecError {
  let tokens : Array[Token] = []
  let chars = text.to_array()
  let mut i = 0
  while i < chars.length() {
    let c = chars[i]
    if c == ' ' || c == '\n' || c == '\t' || c == '\r' {
      i += 1
    } else if c == '-' && i + 1 < chars.length() && chars[i + 1] == '-' {
      while i < chars.length() && chars[i] != '\n' {
        i += 1
      }
    } else if c == '"' {
      let buf = StringBuilder()
      i += 1
      while i < chars.length() && chars[i] != '"' {
        if chars[i] == '\\' && i + 1 < chars.length() {
          i += 1
        }
        buf.write_char(chars[i])
        i += 1
      }
      if i >= chars.length() {
        raise VSpecError("unterminated string")
      }
      i += 1
      tokens.push(Str(buf.to_string()))
    } else if c == '(' {
      tokens.push(Open)
      i += 1
    } else if c == ')' {
      tokens.push(Close)
      i += 1
    } else if c == '[' {
      tokens.push(OpenList)
      i += 1
    } else if c == ']' {
      tokens.push(CloseList)
      i += 1
    } else if c == ',' {
      tokens.push(Comma)
      i += 1
    } else if is_letter(c) {
      let start = i
      i += 1
      while i < chars.length() &&
            (is_letter(chars[i]) || is_digit(chars[i]) || chars[i] == '.') {
        i += 1
      }
      tokens.push(Sym(String::from_array(chars[start:i])))
    } else {
      raise VSpecError("unexpected character `\{c}`")
    }
  }
  tokens
}

///|
priv struct Parser {
  tokens : Array[Token]
  mut pos : Int32
}

///|
fn Parser::peek(self : Parser) -> Token? {
  if self.pos < self.tokens.length() {
    Some(self.tokens[self.pos])
  } else {
    None
  }
}

///|
fn Parser::expect_close(self : Parser) -> Unit raise VSpecError {
  match self.peek() {
    Some(Close) => self.pos += 1
    _ => raise VSpecError("expected `)`")
  }
}

///|
fn Parser::expect_close_list(self : Parser) -> Unit raise VSpecError {
  match self.peek() {
    Some(CloseList) => self.pos += 1
    _ => raise VSpecError("expected `]`")
  }
}

///|
fn Parser::starts_atom(self : Parser) -> Bool {
  match self.peek() {
    Some(Str(_) | Open | OpenList) => true
    _ => false
  }
}

///|
/// An atom: a string, `()`, `( expr )`, `( expr , expr ... )` or `[ expr , ... ]`.
fn Parser::atom(self : Parser) -> Expr raise VSpecError {
  match self.peek() {
    Some(Str(s)) => {
      self.pos += 1
      Str(s)
    }
    Some(Open) => {
      self.pos += 1
      if self.peek() is Some(Close) {
        self.pos += 1
        return Unit
      }
      let items = [self.expr()]
      while self.peek() is Some(Comma) {
        self.pos += 1
        items.push(self.expr())
      }
      self.expect_close()
      if items.length() == 1 {
        items[0]
      } else {
        Pair(items)
      }
    }
    Some(OpenList) => {
      self.pos += 1
      let items : Array[Expr] = []
      if self.peek() is Some(CloseList) {
        self.pos += 1
        return List(items)
      }
      items.push(self.expr())
      while self.peek() is Some(Comma) {
        self.pos += 1
        items.push(self.expr())
      }
      self.expect_close_list()
      List(items)
    }
    _ => raise VSpecError("expected a value")
  }
}

///|
/// An expression: an atom, or a symbol applied to atoms.
fn Parser::expr(self : Parser) -> Expr raise VSpecError {
  match self.peek() {
    Some(Sym(head)) => {
      self.pos += 1
      let args : Array[Expr] = []
      while self.starts_atom() {
        args.push(self.atom())
      }
      App(head, args)
    }
    _ => self.atom()
  }
}

///|
fn type_attrs(constraints : Map[String, @ir.Data]) -> @ir.TypeAttributes {
  { source: None, constraints, extensions: Map([]), }
}

///|
/// The type class of a variable name. The longest prefix wins.
fn class_of(name : @ir.Name) -> String? {
  let text = name.to_canonical()
  for class in ["compappend", "appendable", "comparable", "number"] {
    if text.has_prefix(class) {
      return Some(class)
    }
  }
  None
}

///|
fn variable(text : String) -> @ir.Type {
  let name = elm_name(text)
  let constraints : Map[String, @ir.Data] = Map([])
  if class_of(name) is Some(class) {
    constraints["typeclass"] = Text(class)
  }
  Variable(type_attrs(constraints), name)
}

///|
fn sdk_type(head : String) -> String? {
  match head {
    "listType" => Some("list#list")
    "stringType" => Some("string#string")
    "intType" => Some("basics#int")
    "boolType" => Some("basics#bool")
    "decimalType" => Some("decimal#decimal")
    "floatType" => Some("basics#float")
    "maybeType" => Some("maybe#maybe")
    "dictType" => Some("dict#dict")
    "charType" => Some("char#char")
    "setType" => Some("set#set")
    "resultType" => Some("result#result")
    "orderType" => Some("basics#order")
    "neverType" => Some("basics#never")
    "int8Type" => Some("int#int-8")
    "int16Type" => Some("int#int-16")
    "int32Type" => Some("int#int-32")
    "int64Type" => Some("int#int-64")
    _ => None
  }
}

///|
fn to_type(expr : Expr) -> @ir.Type raise VSpecError {
  guard expr is App(head, args) else { raise VSpecError("expected a type") }
  match head {
    "tVar" =>
      match args {
        [Str(name)] => variable(name)
        _ => raise VSpecError("tVar takes one name")
      }
    "tFun" =>
      match args {
        [List(params), result] => {
          let mut t = to_type(result)
          let mut i = params.length() - 1
          while i >= 0 {
            t = Function(type_attrs(Map([])), to_type(params[i]), t)
            i -= 1
          }
          t
        }
        _ => raise VSpecError("tFun takes a list of types and a result")
      }
    "Type.Tuple" =>
      match args {
        [Unit, List(items)] =>
          Tuple(type_attrs(Map([])), items.map(i => to_type(i)))
        _ => raise VSpecError("Type.Tuple takes () and a list of types")
      }
    _ =>
      match sdk_type(head) {
        Some(reference) =>
          match args {
            [Unit, .. rest] =>
              Reference(
                type_attrs(Map([])),
                @ir.FQName::parse("morphir/SDK:\{reference}") catch {
                  _ => raise VSpecError("bad reference \{reference}")
                },
                rest.map(a => to_type(a)),
              )
            _ => raise VSpecError("\{head} takes () first")
          }
        None => raise VSpecError("unknown SDK type \{head}")
      }
  }
}

///|
/// Parse a morphir-elm `vSpec`.
///
/// Returns the Elm name, the parameters with their Elm names, and the result.
pub fn parse_vspec(
  text : String,
) -> (String, Array[(String, @ir.Type)], @ir.Type) raise VSpecError {
  let parser = { tokens: tokenize(text), pos: 0, }
  let expr = parser.expr()
  if parser.pos < parser.tokens.length() {
    raise VSpecError("unexpected text after the vSpec")
  }
  guard expr is App("vSpec", [Str(name), List(items), result]) else {
    raise VSpecError("expected vSpec \"name\" [ parameters ] result")
  }
  let params : Array[(String, @ir.Type)] = []
  for item in items {
    guard item is Pair([Str(p), t]) else {
      raise VSpecError("a parameter is ( \"name\", type )")
    }
    params.push((p, to_type(t)))
  }
  (name, params, to_type(result))
}
