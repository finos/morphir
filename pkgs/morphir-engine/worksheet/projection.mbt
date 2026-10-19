///|
priv struct ProjectionBudget {
  mut nodes : Int32
  mut bytes : Int32
}

///|
fn ProjectionBudget::new() -> ProjectionBudget {
  { nodes: 100000, bytes: 2097152, }
}

///|
fn ProjectionBudget::charge(
  self : ProjectionBudget,
  bytes : Int32,
) -> Unit raise {
  self.bytes -= bytes
  if self.bytes < 0 {
    raise @execution.Invalid("execution.value_limit")
  }
}

///|
fn ProjectionBudget::scalar(
  self : ProjectionBudget,
  value : @execution.Value,
) -> Unit raise {
  self.charge(@utf8.encode(value.to_json().stringify()).length())
}

///|
fn project_value(
  value : @scheme.Value,
  depth : Int32,
  budget : ProjectionBudget,
) -> @execution.Value raise {
  budget.nodes -= 1
  if depth > 64 || budget.nodes < 0 {
    raise @execution.Invalid("execution.value_limit")
  }
  fn child(value : @scheme.Value) -> @execution.Value raise {
    project_value(value, depth + 1, budget)
  }
  let projected = match value {
    Number(Integer(number)) => {
      // Any larger magnitude exceeds the existing 10,000-decimal-digit bound.
      // Check cheaply before the semantic codec formats the whole integer.
      if number.bit_length() > 33220 {
        raise @execution.Invalid("worksheet.value_unsupported")
      }
      @execution.Integer(number)
    }
    Number(Real(number)) => @execution.Float64(number.reinterpret_as_uint64())
    Boolean(value) => @execution.Boolean(value)
    Text(text) => {
      budget.nodes -= text.length()
      if budget.nodes < 0 {
        raise @execution.Invalid("execution.utf16_units")
      }
      @execution.Text(text.code_units().to_owned().map(unit => unit.to_int()))
    }
    Character(character) => {
      budget.nodes -= if character.to_int() > 65535 { 2 } else { 1 }
      if budget.nodes < 0 {
        raise @execution.Invalid("execution.utf16_units")
      }
      @execution.Character(
        character.to_string().code_units().to_owned().map(unit => unit.to_int()),
      )
    }
    Unit => @execution.Unit
    Nil => {
      budget.scalar(@execution.Sequence([]))
      @execution.Sequence([])
    }
    Pair(_, _) => {
      budget.scalar(@execution.Sequence([]))
      let items : Array[@execution.Value] = []
      let mut rest = value
      while rest is @scheme.Pair(head, tail) {
        if !items.is_empty() {
          budget.charge(1)
        }
        items.push(child(head))
        rest = tail
      }
      if !(rest is @scheme.Nil) {
        raise @execution.Invalid("worksheet.value_unsupported")
      }
      @execution.Sequence(items)
    }
    Vector(items) => {
      budget.scalar(@execution.Product([]))
      if items.length() > budget.nodes {
        raise @execution.Invalid("execution.value_limit")
      }
      @execution.Product(
        items.mapi((index, item) => {
          if index > 0 {
            budget.charge(1)
          }
          child(item)
        }),
      )
    }
    Record(fields) => {
      budget.scalar(@execution.Record([]))
      if fields.length() > budget.nodes {
        raise @execution.Invalid("execution.value_limit")
      }
      let names = fields.keys().collect()
      names.sort()
      @execution.Record(
        names.mapi((index, name) => {
          if name == "" || name.length() > 1024 {
            raise @execution.Invalid("worksheet.value_unsupported")
          }
          if index > 0 {
            budget.charge(1)
          }
          // Charge each field wrapper before traversing its child. Subtract
          // only the null placeholder; the child charges its own exact JSON.
          let wrapper : Json = { "name": name, "value": Json::null() }
          budget.charge(@utf8.encode(wrapper.stringify()).length() - 4)
          (name, child(fields[name]))
        }),
      )
    }
    _ => raise @execution.Invalid("worksheet.value_unsupported")
  }
  match projected {
    Sequence(_) | Product(_) | Record(_) => ()
    _ => budget.scalar(projected)
  }
  projected
}
