///|
/// A bounded rendering tree for the private worker, not an invocation codec.
/// Never recover values by parsing Scheme's printed representation.
fn result_tree(value : @scheme.Value) -> Json {
  result_node(value, 0, Ref(500))
}

///|
fn result_node(
  value : @scheme.Value,
  depth : Int32,
  budget : Ref[Int32],
) -> Json {
  fn node(kind : String, fields : Array[(String, Json)]) -> Json {
    let entries = [("kind", @wire.text(kind))]
    entries.append(fields)
    @wire.obj(entries)
  }
  fn omitted(message : String) -> Json {
    node("truncated", [("text", @wire.text(message))])
  }
  fn scalar(
    kind : String,
    text : String,
    extra : Array[(String, Json)],
  ) -> Json {
    if text.length() > 16384 {
      return omitted("Text exceeds the 16,384-character display limit")
    }
    let fields = [("text", @wire.text(text))]
    fields.append(extra)
    node(kind, fields)
  }
  if budget.val <= 0 {
    return omitted("Result display limit reached")
  }
  budget.val -= 1
  // Depth-truncated children consume budget too, including wide values at depth 32.
  if depth > 32 {
    return omitted("Result display limit reached")
  }
  fn children(values : Array[@scheme.Value]) -> Array[Json] {
    let result = []
    for value in values {
      result.push(result_node(value, depth + 1, budget))
      if budget.val <= 0 {
        if result.length() < values.length() {
          result.push(omitted("Remaining items omitted"))
        }
        break
      }
    }
    result
  }
  match value {
    Number(Integer(n)) => scalar("int", n.to_string(), [])
    Number(Rational(n, d)) =>
      scalar("rational", n.to_string() + "/" + d.to_string(), [])
    Number(Real(n)) =>
      scalar("float", @scheme.Number::Real(n).to_text(), [
        ("bits", @wire.text(n.reinterpret_as_uint64().to_string())),
      ])
    Boolean(b) => scalar("bool", if b { "#t" } else { "#f" }, [])
    Character(c) => scalar("char", c.to_string(), [])
    Text(s) => scalar("string", Json::string(s).stringify(), [])
    Symbol(s) => scalar("symbol", s, [])
    Unit => scalar("unit", "#<unit>", [])
    Nil => node("list", [("items", Json::array([]))])
    Pair(_, _) => {
      let items = []
      let mut rest = value
      while rest is Pair(head, tail) {
        if budget.val <= 0 {
          items.push(omitted("Remaining list items omitted"))
          return node("list", [("items", Json::array(items))])
        }
        items.push(result_node(head, depth + 1, budget))
        rest = tail
      }
      let fields = [("items", Json::array(items))]
      if !(rest is Nil) {
        fields.push(("tail", result_node(rest, depth + 1, budget)))
      }
      node("list", fields)
    }
    Vector(values) => node("tuple", [("items", Json::array(children(values)))])
    Tagged(tag, values) =>
      node("constructor", [
        ("tag", @wire.text(tag)),
        ("items", Json::array(children(values))),
      ])
    Record(fields) => {
      let entries = fields.iter().collect()
      entries.sort_by((a, b) => a.0.lexical_compare(b.0))
      let values = []
      for (name, child) in entries {
        values.push(
          @wire.obj([
            ("name", @wire.text(name)),
            ("value", result_node(child, depth + 1, budget)),
          ]),
        )
        if budget.val <= 0 {
          if values.length() < entries.length() {
            values.push(
              @wire.obj([
                ("name", @wire.text("…")),
                ("value", omitted("Remaining fields omitted")),
              ]),
            )
          }
          break
        }
      }
      node("record", [("fields", Json::array(values))])
    }
    Closure(_) | Native(_) | NativeFunction(_) =>
      scalar("opaque", "Procedure · inspectable text only", [])
    IR(_) => scalar("opaque", "Morphir value · inspectable text only", [])
    IRType(_) => scalar("opaque", "Morphir type · inspectable text only", [])
    IRFile(_) => scalar("opaque", "Morphir model · inspectable text only", [])
  }
}
