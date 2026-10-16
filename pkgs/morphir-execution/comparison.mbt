///|
pub(all) enum ComparisonPolicy {
  Exact
  Approximate(Double, Double)
}

///|
pub fn ComparisonPolicy::validate(self : ComparisonPolicy) -> Unit raise {
  match self {
    Exact => ()
    Approximate(absolute, relative) =>
      if !finite(absolute) ||
        !finite(relative) ||
        absolute < 0.0 ||
        relative < 0.0 {
        raise Invalid("execution.comparison_tolerance")
      }
  }
}

///|
pub fn compare(
  left : Value,
  right : Value,
  policy~ : ComparisonPolicy = Exact,
) -> Bool raise {
  policy.validate()
  validate_value(left, 0, Ref(100000))
  validate_value(right, 0, Ref(100000))
  compare_value(left, right, policy)
}

///|
fn compare_value(
  left : Value,
  right : Value,
  policy : ComparisonPolicy,
) -> Bool raise {
  fn arrays(a : Array[Value], b : Array[Value]) -> Bool raise {
    if a.length() != b.length() {
      return false
    }
    for i, v in a {
      if !compare_value(v, b[i], policy) {
        return false
      }
    }
    true
  }
  match (left, right) {
    (Decimal(a, ae), Decimal(b, be)) =>
      normalize_decimal(a, ae) == normalize_decimal(b, be)
    (Float64(a), Float64(b)) => {
      if a == b {
        return true
      }
      match policy {
        Exact => false
        Approximate(absolute, relative) => {
          let x = a.reinterpret_as_double()
          let y = b.reinterpret_as_double()
          // Non-finite bits and the sign of zero remain exact under either policy.
          if !finite(x) || !finite(y) || (x == 0.0 && y == 0.0) {
            return false
          }
          let distance = (x - y).abs()
          let tolerance = absolute +
            relative * (if x.abs() > y.abs() { x.abs() } else { y.abs() })
          finite(distance) && finite(tolerance) && distance <= tolerance
        }
      }
    }
    (Sequence(a), Sequence(b)) | (Product(a), Product(b)) => arrays(a, b)
    (Record(a), Record(b)) => {
      if a.length() != b.length() {
        return false
      }
      let fields = Map(b)
      for (name, v) in a {
        guard fields.get(name) is Some(other) else { return false }
        if !compare_value(v, other, policy) {
          return false
        }
      }
      true
    }
    (Constructor(owner, tag, a), Constructor(other_owner, other_tag, b)) =>
      owner == other_owner && tag == other_tag && arrays(a, b)
    (Optional(Some(a)), Optional(Some(b)))
    | (Outcome(Ok(a)), Outcome(Ok(b)))
    | (Outcome(Err(a)), Outcome(Err(b))) => compare_value(a, b, policy)
    _ => left == right
  }
}

///|
fn finite(value : Double) -> Bool {
  (value.reinterpret_as_uint64() & 0x7ff0000000000000UL) != 0x7ff0000000000000UL
}

///|
pub fn ComparisonPolicy::to_json(self : ComparisonPolicy) -> Json {
  match self {
    Exact => { "profile": "morphir-comparison-exact-v1" }
    Approximate(absolute, relative) =>
      {
        "profile": "morphir-comparison-approximate-v1",
        "absolute": absolute,
        "relative": relative,
      }
  }
}

///|
/// First mismatch as a JSON Pointer. Semantic comparisons retain rich typed values.
pub fn mismatch_path(
  left : Value,
  right : Value,
  policy~ : ComparisonPolicy = Exact,
) -> String? raise {
  if compare(left, right, policy~) {
    return None
  }
  locate_mismatch(left, right, policy, "")
}

///|
fn locate_mismatch(
  left : Value,
  right : Value,
  policy : ComparisonPolicy,
  path : String,
) -> String? raise {
  fn items(a : Array[Value], b : Array[Value]) -> String? raise {
    if a.length() != b.length() {
      return Some(path + "/length")
    }
    for i, value in a {
      if !compare_value(value, b[i], policy) {
        return locate_mismatch(value, b[i], policy, path + "/" + i.to_string())
      }
    }
    Some(path)
  }
  match (left, right) {
    (Sequence(a), Sequence(b)) | (Product(a), Product(b)) => items(a, b)
    (Record(a), Record(b)) => {
      let fields = Map(b)
      for (name, value) in a {
        let child = path +
          "/" +
          name.replace_all(old="~", new="~0").replace_all(old="/", new="~1")
        guard fields.get(name) is Some(other) else { return Some(child) }
        if !compare_value(value, other, policy) {
          return locate_mismatch(value, other, policy, child)
        }
      }
      Some(path)
    }
    (Constructor(owner, tag, a), Constructor(other_owner, other_tag, b)) =>
      if owner != other_owner || tag != other_tag {
        Some(path + "/constructor")
      } else {
        items(a, b)
      }
    (Optional(Some(a)), Optional(Some(b))) =>
      locate_mismatch(a, b, policy, path + "/just")
    (Outcome(Ok(a)), Outcome(Ok(b))) =>
      locate_mismatch(a, b, policy, path + "/ok")
    (Outcome(Err(a)), Outcome(Err(b))) =>
      locate_mismatch(a, b, policy, path + "/err")
    _ => Some(path)
  }
}
