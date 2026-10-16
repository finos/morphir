///|
pub fn arity(
  args : Array[Value],
  count : Int32,
  name : String,
) -> Unit raise SchemeError {
  if args.length() != count {
    raise Invalid(name + ": expected " + count.to_string() + " arguments")
  }
}

///|
fn Runtime::install_builtins(self : Runtime) -> Unit {
  for
    name in [
      "+", "-", "*", "/", "=", "<", ">", "<=", ">=", "quotient", "remainder", "not",
      "cons", "car", "cdr", "list", "null?", "pair?", "list?", "number?", "integer?",
      "boolean?", "string?", "symbol?", "procedure?", "equal?", "length", "append",
      "reverse", "map", "fold-left", "apply", "string-append", "string=?", "symbol->string",
      "string->symbol", "number->string", "string->number", "record", "record-ref",
      "record-set", "record-keys", "vector", "vector-ref", "vector-length", "unit",
      "error",
    ] {
    self.define_native(name, fn(runtime, args) raise {
      builtin(runtime, name, args)
    })
  }
}

///|
fn builtin(
  runtime : Runtime,
  name : String,
  args : Array[Value],
) -> Value raise {
  match name {
    "+" | "*" | "-" | "/" => {
      if args.is_empty() && (name == "-" || name == "/") {
        raise Invalid(name + " needs an operand")
      }
      let mut result = if name == "*" || name == "/" {
        Number::Integer(@bigint.BigInt::from_int(1))
      } else {
        Number::Integer(@bigint.BigInt::from_int(0))
      }
      let start = if (name == "-" || name == "/") && args.length() > 1 {
        result = number(args[0])
        1
      } else {
        0
      }
      for i = start; i < args.length(); i = i + 1 {
        result = arithmetic(name, result, number(args[i]))
      }
      Number(result)
    }
    "=" | "<" | ">" | "<=" | ">=" => {
      if args.length() < 2 {
        raise Invalid("Comparison needs at least two operands")
      }
      let mut result = true
      for i = 1; i < args.length(); i = i + 1 {
        let comparison = compare_numbers(number(args[i - 1]), number(args[i]))
        result = result &&
          (match name {
            "=" => comparison == 0
            "<" => comparison < 0
            ">" => comparison > 0
            "<=" => comparison <= 0
            _ => comparison >= 0
          })
      }
      Boolean(result)
    }
    "quotient" | "remainder" => {
      arity(args, 2, name)
      match (number(args[0]), number(args[1])) {
        (Integer(a), Integer(b)) => {
          if b.is_zero() {
            raise Invalid("Division by zero")
          }
          Number(Integer(if name == "quotient" { a / b } else { a % b }))
        }
        _ => raise Invalid("Expected exact integers")
      }
    }
    "not" => {
      arity(args, 1, name)
      Boolean(!truth(args[0]))
    }
    "cons" => {
      arity(args, 2, name)
      Pair(args[0], args[1])
    }
    "car" | "cdr" => {
      arity(args, 1, name)
      match args[0] {
        Pair(head, tail) => if name == "car" { head } else { tail }
        _ => raise Invalid("Expected pair")
      }
    }
    "list" => list(args)
    "null?"
    | "pair?"
    | "list?"
    | "number?"
    | "integer?"
    | "boolean?"
    | "string?"
    | "symbol?"
    | "procedure?" => {
      arity(args, 1, name)
      Boolean(
        match name {
          "null?" => args[0] is Nil
          "pair?" => args[0] is Pair(_, _)
          "list?" =>
            try {
              ignore(args[0].to_array())
              true
            } catch {
              _ => false
            }
          "number?" => args[0] is Number(_)
          "integer?" => args[0] is Number(Integer(_))
          "boolean?" => args[0] is Boolean(_)
          "string?" => args[0] is Text(_)
          "symbol?" => args[0] is Symbol(_)
          _ =>
            args[0] is Closure(_) ||
            args[0] is Native(_) ||
            args[0] is NativeFunction(_)
        },
      )
    }
    "equal?" => {
      arity(args, 2, name)
      Boolean(runtime.equal_values(args[0], args[1]))
    }
    "length" => {
      arity(args, 1, name)
      Number(Integer(@bigint.BigInt::from_int(args[0].to_array().length())))
    }
    "append" => {
      if args.is_empty() {
        return Nil
      }
      let mut result = args[args.length() - 1]
      for i = args.length() - 2; i >= 0; i = i - 1 {
        let items = args[i].to_array()
        for j = items.length() - 1; j >= 0; j = j - 1 {
          result = Pair(items[j], result)
        }
      }
      result
    }
    "reverse" => {
      arity(args, 1, name)
      let items = args[0].to_array()
      let mut result = Nil
      for item in items {
        result = Pair(item, result)
      }
      result
    }
    "map" => {
      arity(args, 2, name)
      list(args[1].to_array().map(item => runtime.call(args[0], [item])))
    }
    "fold-left" => {
      arity(args, 3, name)
      let mut result = args[1]
      for item in args[2].to_array() {
        result = runtime.call(args[0], [result, item])
      }
      result
    }
    "apply" => {
      if args.length() < 2 {
        raise Invalid("apply needs a procedure and list")
      }
      let actual = args[1:args.length() - 1].to_owned()
      actual.append(args[args.length() - 1].to_array())
      runtime.call(args[0], actual)
    }
    "string-append" => Text(args.map(Value::as_text).join(""))
    "string=?" => {
      arity(args, 2, name)
      Boolean(args[0].as_text() == args[1].as_text())
    }
    "symbol->string" => {
      arity(args, 1, name)
      match args[0] {
        Symbol(s) => Text(s)
        _ => raise Invalid("Expected symbol")
      }
    }
    "string->symbol" => {
      arity(args, 1, name)
      Symbol(args[0].as_text())
    }
    "number->string" => {
      arity(args, 1, name)
      Text(number(args[0]).to_text())
    }
    "string->number" => {
      arity(args, 1, name)
      match parse_number(args[0].as_text()) {
        Some(n) => Number(n)
        None => Boolean(false)
      }
    }
    "record" => {
      let fields : Map[String, Value] = Map([])
      for arg in args {
        match arg {
          Pair(Text(key), value) => {
            if fields.contains(key) {
              raise Invalid("Duplicate record field: " + key)
            }
            fields[key] = value
          }
          _ => raise Invalid("record expects pairs with string keys")
        }
      }
      Record(fields)
    }
    "record-ref" => {
      arity(args, 2, name)
      match args[0] {
        Record(fields) =>
          match fields.get(args[1].as_text()) {
            Some(value) => value
            None => raise Invalid("Missing record field")
          }
        _ => raise Invalid("Expected record")
      }
    }
    "record-set" => {
      arity(args, 3, name)
      match args[0] {
        Record(fields) => {
          let copy = Map::from_array(fields.iter().collect())
          copy[args[1].as_text()] = args[2]
          Record(copy)
        }
        _ => raise Invalid("Expected record")
      }
    }
    "record-keys" => {
      arity(args, 1, name)
      match args[0] {
        Record(fields) =>
          list(fields.iter().collect().map(pair => Text(pair.0)))
        _ => raise Invalid("Expected record")
      }
    }
    "vector" => Vector(args)
    "vector-length" => {
      arity(args, 1, name)
      match args[0] {
        Vector(items) =>
          Number(Integer(@bigint.BigInt::from_int(items.length())))
        _ => raise Invalid("Expected vector")
      }
    }
    "vector-ref" => {
      arity(args, 2, name)
      match (args[0], args[1]) {
        (Vector(items), Number(Integer(index))) => {
          if index < @bigint.BigInt::from_int(0) ||
            index >= @bigint.BigInt::from_int(items.length()) {
            raise Invalid("Vector index out of range")
          }
          items[index.to_int()]
        }
        _ => raise Invalid("Expected vector and integer")
      }
    }
    "unit" => {
      arity(args, 0, name)
      Unit
    }
    "error" => raise Invalid(args.map(value_to_string).join(" "))
    _ => raise Unbound(name)
  }
}

///|
pub fn Runtime::equal_values(
  self : Runtime,
  left : Value,
  right : Value,
) -> Bool raise {
  let pending = [(left, right)]
  while pending.pop() is Some((left, right)) {
    self.tick()
    match (left, right) {
      (Number(a), Number(b)) => if compare_numbers(a, b) != 0 { return false }
      (Boolean(a), Boolean(b)) => if a != b { return false }
      (Text(a), Text(b)) | (Symbol(a), Symbol(b)) => if a != b { return false }
      (Character(a), Character(b)) => if a != b { return false }
      (Nil, Nil) | (Unit, Unit) => ()
      (Pair(a, b), Pair(c, d)) => {
        pending.push((a, c))
        pending.push((b, d))
      }
      (Vector(a), Vector(b)) | (Tagged(_, a), Tagged(_, b)) => {
        if left is Tagged(a, _) && right is Tagged(b, _) && a != b {
          return false
        }
        if a.length() != b.length() {
          return false
        }
        for i = 0; i < a.length(); i = i + 1 {
          pending.push((a[i], b[i]))
        }
      }
      (Record(a), Record(b)) => {
        if a.length() != b.length() {
          return false
        }
        for key, value in a {
          match b.get(key) {
            Some(other) => pending.push((value, other))
            None => return false
          }
        }
      }
      (IR(a), IR(b)) => if a != b { return false }
      (IRType(a), IRType(b)) => if a != b { return false }
      (IRFile(a), IRFile(b)) => if a != b { return false }
      _ => return false
    }
  }
  true
}

///|
pub fn value_to_string(value : Value) -> String raise SchemeError {
  render(value, 0)
}

///|
fn render(value : Value, depth : Int32) -> String raise SchemeError {
  if depth > 256 {
    raise Limit("value printing depth")
  }
  match value {
    Number(n) => n.to_text()
    Boolean(b) => if b { "#t" } else { "#f" }
    Character(c) => Datum::Character(c).to_source()
    Text(s) => Datum::Text(s).to_source()
    Symbol(s) => symbol_text(s)
    Nil => "()"
    Pair(_, _) => {
      let items : Array[String] = []
      let mut rest = value
      while rest is Pair(head, tail) {
        items.push(render(head, depth + 1))
        rest = tail
      }
      "(" +
      items.join(" ") +
      (match rest {
        Nil => ""
        _ => " . " + render(rest, depth + 1)
      }) +
      ")"
    }
    Vector(items) =>
      "#(" + items.map(item => render(item, depth + 1)).join(" ") + ")"
    Record(fields) =>
      "#<record " +
      fields
      .iter()
      .collect()
      .map(pair => pair.0 + "=" + render(pair.1, depth + 1))
      .join(" ") +
      ">"
    Tagged(tag, items) =>
      "#<" +
      tag +
      " " +
      items.map(item => render(item, depth + 1)).join(" ") +
      ">"
    Unit => "#<unit>"
    Closure(_) | Native(_) | NativeFunction(_) => "#<procedure>"
    IR(_) => "#<morphir-value>"
    IRType(_) => "#<morphir-type>"
    IRFile(_) => "#<morphir-file>"
  }
}
