///|
/// A compact text form of a value, for assertions. Attributes are not shown. A variable pattern
/// `AsPattern(WildcardPattern, x)` shows as `x`.
fn show(v : @ir.Value) -> String {
  match v {
    Literal(_, l) => show_literal(l)
    Constructor(_, fq) => "(ctor \{fq.to_canonical()})"
    Tuple(_, items) => "(tuple" + items.map(i => " " + show(i)).join("") + ")"
    List(_, items) => "(list" + items.map(i => " " + show(i)).join("") + ")"
    Record(_, fields) => "(record" + show_fields(fields) + ")"
    Variable(_, n) => n.to_canonical()
    Reference(_, fq) => "(ref \{fq.to_canonical()})"
    Field(_, r, n) => "(field \{show(r)} \{n.to_canonical()})"
    FieldFunction(_, n) => "(field-fn \{n.to_canonical()})"
    Apply(_, f, x) => "(apply \{show(f)} \{show(x)})"
    Lambda(_, p, b) => "(lambda \{show_pattern(p)} \{show(b)})"
    LetDefinition(_, n, d, i) =>
      "(let \{n.to_canonical()} \{show_definition(d)} \{show(i)})"
    LetRecursion(_, defs, i) => {
      let names = defs.keys().collect()
      names.sort_by((a, b) => a.to_canonical().compare(b.to_canonical()))
      "(letrec" +
      names
      .map(n => " (\{n.to_canonical()} \{show_definition(defs[n])})")
      .join("") +
      " " +
      show(i) +
      ")"
    }
    Destructure(_, p, x, i) =>
      "(destructure \{show_pattern(p)} \{show(x)} \{show(i)})"
    IfThenElse(_, c, t, e) => "(if \{show(c)} \{show(t)} \{show(e)})"
    PatternMatch(_, s, cases) =>
      "(case \{show(s)}" +
      cases.map(c => " (\{show_pattern(c.0)} \{show(c.1)})").join("") +
      ")"
    UpdateRecord(_, r, fields) =>
      "(update \{show(r)}" + show_fields(fields) + ")"
    Unit(_) => "()"
    Hole(_, _, _) => "(hole)"
  }
}

///|
fn show_fields(fields : Map[@ir.Name, @ir.Value]) -> String {
  let names = fields.keys().collect()
  names.sort_by((a, b) => a.to_canonical().compare(b.to_canonical()))
  names.map(n => " (\{n.to_canonical()} \{show(fields[n])})").join("")
}

///|
fn show_definition(d : @ir.ValueDefinition) -> String {
  match d {
    ExpressionBody([], _, body) => show(body)
    ExpressionBody(inputs, _, body) =>
      "(def (" +
      inputs.map(i => i.0.to_canonical()).join(" ") +
      ") " +
      show(body) +
      ")"
    _ => "(not-an-expression-body)"
  }
}

///|
fn show_literal(l : @ir.Literal) -> String {
  match l {
    BoolLiteral(b) => "(bool \{b})"
    CharLiteral(c) => "(char \{c})"
    StringLiteral(s) => "(str \{s})"
    IntegerLiteral(s) => "(int \{s})"
    FloatLiteral(d) => "(float \{d})"
    DecimalLiteral(s) => "(decimal \{s})"
    DocumentLiteral(_) => "(document)"
  }
}

///|
fn show_pattern(p : @ir.Pattern) -> String {
  match p {
    WildcardPattern(_) => "_"
    AsPattern(_, WildcardPattern(_), n) => n.to_canonical()
    AsPattern(_, inner, n) => "(as \{show_pattern(inner)} \{n.to_canonical()})"
    TuplePattern(_, items) =>
      "(ptuple" + items.map(i => " " + show_pattern(i)).join("") + ")"
    ConstructorPattern(_, fq, args) =>
      "(pctor \{fq.to_canonical()}" +
      args.map(a => " " + show_pattern(a)).join("") +
      ")"
    EmptyListPattern(_) => "[]"
    HeadTailPattern(_, h, t) => "(cons \{show_pattern(h)} \{show_pattern(t)})"
    LiteralPattern(_, l) =>
      match l {
        BoolLiteral(b) => "(plit (bool \{b}))"
        CharLiteral(c) => "(plit (char \{c}))"
        StringLiteral(s) => "(plit (str \{s}))"
        IntegerLiteral(s) => "(plit (int \{s}))"
        FloatLiteral(d) => "(plit (float \{d}))"
        DecimalLiteral(s) => "(plit (decimal \{s}))"
      }
    UnitPattern(_) => "()"
  }
}
