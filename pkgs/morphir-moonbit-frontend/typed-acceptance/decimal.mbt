///|
fn decimal_source() -> String {
  [
    "pub fn exact(v : String) -> @decimal.Decimal raise @decimal.DecimalError { @decimal.from_string_exact(v) }",
    "pub fn spelling() -> @decimal.Decimal raise @decimal.DecimalError { @decimal.from_string_exact(\"12.3400\") }",
    "pub fn identity(v : @decimal.Decimal) -> @decimal.Decimal { v }", "pub fn add(a : String, b : String) -> @decimal.Decimal raise @decimal.DecimalError { @decimal.add(exact(a), exact(b)) }",
    "pub fn sub(a : String, b : String) -> @decimal.Decimal raise @decimal.DecimalError { @decimal.sub(exact(a), exact(b)) }",
    "pub fn mul(a : String, b : String) -> @decimal.Decimal raise @decimal.DecimalError { @decimal.mul(exact(a), exact(b)) }",
    "pub fn divide(a : String, b : String) -> @decimal.Decimal raise @decimal.DecimalError { @decimal.divide(exact(a), exact(b)) }",
    "pub fn round(v : String) -> @decimal.Decimal raise @decimal.DecimalError { @decimal.round(exact(v)) }",
    "pub fn eq(a : String, b : String) -> Bool raise @decimal.DecimalError { @decimal.eq(exact(a), exact(b)) }",
    "pub fn neq(a : String, b : String) -> Bool raise @decimal.DecimalError { @decimal.neq(exact(a), exact(b)) }",
    "pub fn lt(a : String, b : String) -> Bool raise @decimal.DecimalError { @decimal.lt(exact(a), exact(b)) }",
    "pub fn lte(a : String, b : String) -> Bool raise @decimal.DecimalError { @decimal.lte(exact(a), exact(b)) }",
    "pub fn gt(a : String, b : String) -> Bool raise @decimal.DecimalError { @decimal.gt(exact(a), exact(b)) }",
    "pub fn gte(a : String, b : String) -> Bool raise @decimal.DecimalError { @decimal.gte(exact(a), exact(b)) }",
    "pub fn fallback(v : String, a : String, b : String) -> @decimal.Decimal raise @decimal.DecimalError { @decimal.divide_with_default(exact(v), exact(a), exact(b)) }",
  ].join("\n")
}

///|
fn decimal_references() -> Array[(String, Array[String], String)] {
  [
    ("exact", ["9007199254740993.00"], "9007199254740993"),
    (
      "exact",
      ["0.000000000000000000000000000000010"],
      "0.00000000000000000000000000000001",
    ),
    ("exact", ["-0.000000000000000000000000000000000"], "0"),
    ("exact", ["1.25e2"], "125"),
    ("spelling", [], "12.34"),
    ("add", ["12.3400", "0.660"], "13"),
    ("sub", ["0", "1.2300"], "-1.23"),
    ("mul", ["1.25", "2.4"], "3"),
    ("mul", ["1e-32", "0.1"], "0"),
    ("round", ["2.5"], "2"),
    ("round", ["3.5"], "4"),
    ("round", ["-2.5"], "-2"),
    ("round", ["-3.5"], "-4"),
    ("divide", ["1", "3"], "0.33333333333333333333333333333333"),
    ("divide", ["-1", "2"], "-0.5"),
    ("divide", ["1e-32", "1"], "0.00000000000000000000000000000001"),
    ("divide", ["0", "2"], "0"),
    ("fallback", ["99", "1", "0"], "99"),
    ("fallback", ["99", "1e-32", "2"], "99"),
    ("fallback", ["99", "1", "2"], "0.5"),
  ]
}

///|
fn decimal_comparisons() -> Array[(String, String, String, Bool)] {
  [
    ("eq", "1.2300", "1.23", true),
    ("neq", "-0.00", "0", false),
    ("lt", "9007199254740992", "9007199254740993", true),
    ("lte", "1.00", "1", true),
    ("gt", "-1", "-2", true),
    ("gte", "0", "1e-32", false),
  ]
}

///|
fn decimal_failures() -> Array[(String, Array[String], String)] {
  [
    ("divide", ["1", "0"], "division_by_zero"),
    ("divide", ["0", "0"], "division_by_zero"),
    ("divide", ["1e-32", "2"], "underflow"),
    ("exact", ["0.000000000000000000000000000000001"], "precision_loss"),
    ("exact", ["NaN"], "invalid_literal"),
  ]
}
