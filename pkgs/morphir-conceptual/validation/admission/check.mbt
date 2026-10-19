///|
/// Type-structure recursion (union nesting, variable hops, alias expansion,
/// substitution, inventory) is capped separately from value depth so a
/// deeply nested type reports exhaustion instead of overflowing the stack
/// on any target.
let max_type_depth : Int32 = 128

///|
priv struct Checker {
  env : TypeEnvironment
  limits : Limits
  mut nodes : Int32
  mut type_nodes : Int32
  mut subst_exhausted : Bool
  mut active : Int32
}

///|
fn diag(code : String, path : String, message : String) -> Diagnostic {
  { code, path, message, }
}

///|
fn invalid(code : String, path : String, message : String) -> Outcome {
  Invalid([diag(code, path, message)])
}

///|
fn is_ambiguous(outcome : Outcome) -> Bool {
  match outcome {
    Invalid(diagnostics) =>
      diagnostics.iter().any(d => d.code == "contracts.ambiguous_value")
    _ => false
  }
}

///|
fn child_path(path : String, segment : String) -> String {
  // RFC 6901: the root pointer is empty; escape "~" first, then "/".
  let escaped = segment.replace(old="~", new="~0").replace(old="/", new="~1")
  path + "/" + escaped
}

///|
fn find_record_value(fields : Array[(String, Value)], name : String) -> Value? {
  for (other, value) in fields {
    if other == name {
      return Some(value)
    }
  }
  None
}

///|
fn find_dict_value(entries : Array[(Value, Value)], key : Value) -> Value? {
  for (other, value) in entries {
    if value_equal(other, key) {
      return Some(value)
    }
  }
  None
}

///|
fn find_field_type(
  fields : Array[(String, TypeExpr)],
  name : String,
) -> TypeExpr? {
  for (other, ty) in fields {
    if other == name {
      return Some(ty)
    }
  }
  None
}

///|
fn find_constructor(
  constructors : Array[(String, Array[TypeExpr])],
  name : String,
) -> Array[TypeExpr]? {
  for (other, payloads) in constructors {
    if other == name {
      return Some(payloads)
    }
  }
  None
}

///|
fn value_equal(a : Value, b : Value) -> Bool {
  match (a, b) {
    (VBool(x), VBool(y)) => x == y
    (VInt(x), VInt(y)) => x == y
    (VString(x), VString(y)) => x == y
    (VTuple(xs), VTuple(ys)) | (VList(xs), VList(ys)) =>
      xs.length() == ys.length() &&
      xs.iter().zip(ys.iter()).all(pair => value_equal(pair.0, pair.1))
    (VSet(xs), VSet(ys)) => {
      if xs.length() != ys.length() {
        return false
      }
      // Sets are unordered: match each element against a distinct partner.
      let used : Array[Bool] = []
      for _ in ys {
        used.push(false)
      }
      for x in xs {
        let mut matched = false
        for j in 0..<ys.length() {
          if !used[j] && value_equal(x, ys[j]) {
            used[j] = true
            matched = true
            break
          }
        }
        if !matched {
          return false
        }
      }
      true
    }
    (VRecord(xs), VRecord(ys)) =>
      xs.length() == ys.length() &&
      xs
      .iter()
      .all(pair => {
        match find_record_value(ys, pair.0) {
          Some(y) => value_equal(pair.1, y)
          None => false
        }
      })
    (VDict(xs), VDict(ys)) =>
      xs.length() == ys.length() &&
      xs
      .iter()
      .all(pair => {
        match find_dict_value(ys, pair.0) {
          Some(vy) => value_equal(pair.1, vy)
          None => false
        }
      })
    (VConstructed(cx, xs), VConstructed(cy, ys)) =>
      cx == cy &&
      xs.length() == ys.length() &&
      xs.iter().zip(ys.iter()).all(pair => value_equal(pair.0, pair.1))
    (VOpaque(nx, x), VOpaque(ny, y)) => nx == ny && value_equal(x, y)
    _ => false
  }
}

///|
priv enum RefinementResult {
  Holds
  Fails
  Unknown(String)
}

///|
fn refinement_known(refinement : Refinement) -> Bool {
  match refinement {
    NamedRefinement(name) =>
      name == "string.nonEmpty" ||
      name == "int.positive" ||
      name == "int.nonNegative"
    _ => true
  }
}

///|
fn refinement_holds(refinement : Refinement, value : Value) -> RefinementResult {
  match refinement {
    NonEmptyString =>
      match value {
        VString(s) => if s.is_empty() { Fails } else { Holds }
        _ => Fails
      }
    PositiveInt =>
      match value {
        VInt(n) => if n > @bigint.BigInt::from_int(0) { Holds } else { Fails }
        _ => Fails
      }
    NonNegativeInt =>
      match value {
        VInt(n) => if n >= @bigint.BigInt::from_int(0) { Holds } else { Fails }
        _ => Fails
      }
    MaxLength(limit) =>
      match value {
        VString(s) => if s.length() <= limit { Holds } else { Fails }
        _ => Fails
      }
    NamedRefinement(name) =>
      match name {
        "string.nonEmpty" => refinement_holds(NonEmptyString, value)
        "int.positive" => refinement_holds(PositiveInt, value)
        "int.nonNegative" => refinement_holds(NonNegativeInt, value)
        _ => Unknown(name)
      }
  }
}

///|
fn check_refinement(
  refinement : Refinement?,
  value : Value,
  path : String,
) -> Outcome {
  match refinement {
    None => Valid
    Some(rule) =>
      match refinement_holds(rule, value) {
        Holds => Valid
        Fails =>
          invalid(
            "contracts.refinement_failed", path, "value fails its declared refinement",
          )
        Unknown(name) =>
          Unsupported(
            diag(
              "contracts.unsupported_refinement",
              path,
              "unsupported refinement: " + name,
            ),
          )
      }
  }
}

///|
fn mismatch(value : Value, path : String, expected : String) -> Outcome {
  match value {
    VOpaque(name, _) =>
      invalid(
        "contracts.opaque_construction",
        path,
        "opaque value for " + name + " cannot be used as " + expected,
      )
    _ =>
      invalid(
        "contracts.invalid_value",
        path,
        "value does not match " + expected,
      )
  }
}

///|
fn type_equal(a : TypeExpr, b : TypeExpr) -> Bool {
  match (a, b) {
    (TBool, TBool) | (TInt, TInt) | (TString, TString) => true
    (TVariable(x), TVariable(y)) => x == y
    (TReference(x, xs), TReference(y, ys)) =>
      x == y &&
      xs.length() == ys.length() &&
      xs.iter().zip(ys.iter()).all(pair => type_equal(pair.0, pair.1))
    (TTuple(xs), TTuple(ys)) | (TUnion(xs), TUnion(ys)) =>
      xs.length() == ys.length() &&
      xs.iter().zip(ys.iter()).all(pair => type_equal(pair.0, pair.1))
    (TRecord(xs), TRecord(ys)) =>
      xs.length() == ys.length() &&
      xs
      .iter()
      .zip(ys.iter())
      .all(pair => pair.0.0 == pair.1.0 && type_equal(pair.0.1, pair.1.1))
    (TList(x), TList(y)) | (TSet(x), TSet(y)) => type_equal(x, y)
    (TDict(xk, xv), TDict(yk, yv)) => type_equal(xk, yk) && type_equal(xv, yv)
    (TFunction(x, xr), TFunction(y, yr)) =>
      x.length() == y.length() &&
      x.iter().zip(y.iter()).all(pair => type_equal(pair.0, pair.1)) &&
      type_equal(xr, yr)
    (TUnsupported(x), TUnsupported(y)) => x == y
    _ => false
  }
}

///|
fn contains_type(types : Array[TypeExpr], ty : TypeExpr) -> Bool {
  types.iter().any(other => type_equal(other, ty))
}

///|
/// Substitute type variables, charging every visited type node to the type
/// work budget and stopping at the type depth cap. A deeply nested or
/// widely shared generic argument cannot bypass the limits or the stack.
fn Checker::substitute(
  self : Checker,
  ty : TypeExpr,
  subst : Map[String, TypeExpr],
  tdepth : Int32,
) -> TypeExpr {
  if self.subst_exhausted {
    return ty
  }
  if tdepth > max_type_depth {
    self.subst_exhausted = true
    return ty
  }
  self.type_nodes = self.type_nodes + 1
  if self.type_nodes > self.limits.max_value_nodes {
    self.subst_exhausted = true
    return ty
  }
  match ty {
    TVariable(name) =>
      match subst.get(name) {
        Some(found) => found
        None => ty
      }
    TReference(name, args) =>
      TReference(name, args.map(a => self.substitute(a, subst, tdepth + 1)))
    TTuple(items) =>
      TTuple(items.map(a => self.substitute(a, subst, tdepth + 1)))
    TRecord(fields) =>
      TRecord(
        fields.map(pair => (pair.0, self.substitute(pair.1, subst, tdepth + 1))),
      )
    TUnion(members) =>
      TUnion(members.map(a => self.substitute(a, subst, tdepth + 1)))
    TList(elem) => TList(self.substitute(elem, subst, tdepth + 1))
    TSet(elem) => TSet(self.substitute(elem, subst, tdepth + 1))
    TDict(k, v) =>
      TDict(
        self.substitute(k, subst, tdepth + 1),
        self.substitute(v, subst, tdepth + 1),
      )
    TFunction(args, result) =>
      TFunction(
        args.map(a => self.substitute(a, subst, tdepth + 1)),
        self.substitute(result, subst, tdepth + 1),
      )
    _ => ty
  }
}

///|
fn Checker::bind_arguments(
  self : Checker,
  params : Array[String],
  args : Array[TypeExpr],
  subst : Map[String, TypeExpr],
  tdepth : Int32,
) -> (Map[String, TypeExpr], Array[TypeExpr]) {
  let bound : Map[String, TypeExpr] = Map([])
  let instantiated : Array[TypeExpr] = []
  for i in 0..<params.length() {
    let arg = self.substitute(args[i], subst, tdepth)
    bound[params[i]] = arg
    instantiated.push(arg)
  }
  (bound, instantiated)
}

///|
/// Total active recursion across checking steps is capped as an
/// implementation bound, so alias chains that stay active across value
/// levels report exhaustion instead of overflowing the target stack.
let max_active_recursion : Int32 = 256

///|
fn Checker::inventory(
  self : Checker,
  ty : TypeExpr,
  subst : Map[String, TypeExpr],
  visited : Array[TypeExpr],
  expanding : Array[TypeExpr],
  tdepth : Int32,
) -> Outcome {
  self.active = self.active + 1
  if self.active > max_active_recursion {
    self.active = self.active - 1
    return Exhausted(NodeLimit)
  }
  let outcome = self.inventory_body(ty, subst, visited, expanding, tdepth)
  self.active = self.active - 1
  outcome
}

///|
fn declaration_error(decl : TypeDecl) -> Diagnostic? {
  let params = match decl {
    Transparent(ps, _, _) => ps
    Opaque(ps, _, _) => ps
    Custom(ps, _) => ps
  }
  let seen : Map[String, Bool] = Map([])
  for param in params {
    if seen.contains(param) {
      return Some(
        diag(
          "contracts.invalid_value",
          "",
          "duplicate type parameter in declaration: " + param,
        ),
      )
    }
    seen[param] = true
  }
  match decl {
    Custom(_, constructors) => {
      let names : Map[String, Bool] = Map([])
      for pair in constructors {
        if names.contains(pair.0) {
          return Some(
            diag(
              "contracts.invalid_value",
              "",
              "duplicate constructor in declaration: " + pair.0,
            ),
          )
        }
        names[pair.0] = true
      }
      None
    }
    _ => None
  }
}

///|
/// Capability is decided before any value is admitted (C1): walk the type
/// and every reachable declaration, reporting unsupported forms, unknown
/// types, unbound variables and unknown refinements even where an empty
/// collection or an unselected constructor would visit no payload.
fn Checker::inventory_body(
  self : Checker,
  ty : TypeExpr,
  subst : Map[String, TypeExpr],
  visited : Array[TypeExpr],
  expanding : Array[TypeExpr],
  tdepth : Int32,
) -> Outcome {
  if tdepth > max_type_depth {
    return Exhausted(NodeLimit)
  }
  self.type_nodes = self.type_nodes + 1
  if self.type_nodes > self.limits.max_value_nodes {
    return Exhausted(NodeLimit)
  }
  match ty {
    TBool | TInt | TString => Valid
    TVariable(name) =>
      match subst.get(name) {
        Some(found) =>
          self.inventory(found, subst, visited, expanding, tdepth + 1)
        None =>
          Unsupported(
            diag(
              "contracts.unbound_variable",
              "",
              "unbound type variable: " + name,
            ),
          )
      }
    TTuple(items) => {
      for item in items {
        let outcome = self.inventory(item, subst, visited, [], tdepth + 1)
        if !(outcome is Valid) {
          return outcome
        }
      }
      Valid
    }
    TUnion(items) => {
      for item in items {
        let outcome = self.inventory(
          item,
          subst,
          visited,
          expanding,
          tdepth + 1,
        )
        if !(outcome is Valid) {
          return outcome
        }
      }
      Valid
    }
    TRecord(fields) => {
      let seen : Map[String, Bool] = Map([])
      for pair in fields {
        if seen.contains(pair.0) {
          return invalid(
            "contracts.invalid_value",
            "",
            "duplicate record field in declared type: " + pair.0,
          )
        }
        seen[pair.0] = true
        let outcome = self.inventory(pair.1, subst, visited, [], tdepth + 1)
        if !(outcome is Valid) {
          return outcome
        }
      }
      Valid
    }
    TList(elem) | TSet(elem) =>
      self.inventory(elem, subst, visited, [], tdepth + 1)
    TDict(k, v) => {
      let outcome = self.inventory(k, subst, visited, [], tdepth + 1)
      if !(outcome is Valid) {
        return outcome
      }
      self.inventory(v, subst, visited, [], tdepth + 1)
    }
    TFunction(_, _) =>
      Unsupported(
        diag(
          "contracts.unsupported_type", "", "function types are outside the bounded checking profile",
        ),
      )
    TUnsupported(name) =>
      Unsupported(
        diag("contracts.unsupported_type", "", "unsupported type: " + name),
      )
    TReference(name, args) =>
      match self.env.declarations.get(name) {
        None =>
          Unsupported(
            diag("contracts.unknown_type", "", "unknown type: " + name),
          )
        Some(decl) => {
          let params = match decl {
            Transparent(ps, _, _) => ps
            Opaque(ps, _, _) => ps
            Custom(ps, _) => ps
          }
          if params.length() != args.length() {
            return invalid(
              "contracts.invalid_value",
              "",
              "type argument count does not match declaration: " + name,
            )
          }
          match declaration_error(decl) {
            Some(error) => return Invalid([error])
            None => ()
          }
          // Arguments start a fresh alias chain: an unguarded cycle
          // inside an argument is self-contained, and whether an
          // argument occurrence is guarded is decided by the body walk
          // below, not by the caller's chain.
          for arg in args {
            let outcome = self.inventory(arg, subst, visited, [], tdepth + 1)
            if !(outcome is Valid) {
              return outcome
            }
          }
          let (bound, instantiated) = self.bind_arguments(
            params,
            args,
            subst,
            tdepth + 1,
          )
          if self.subst_exhausted {
            return Exhausted(NodeLimit)
          }
          let key = TReference(name, instantiated)
          // An alias that reaches itself without passing a value
          // constructor is unguarded: no finite value can be admitted,
          // wherever in the type it appears.
          if decl is Transparent(_, _, _) && contains_type(expanding, key) {
            return invalid(
              "contracts.alias_cycle",
              "",
              "alias cycle reaches: " + name,
            )
          }
          if contains_type(visited, key) {
            return Valid
          }
          let visited2 = visited + [key]
          match decl {
            Transparent(_, underlying, refinement)
            | Opaque(_, underlying, refinement) => {
              match refinement {
                Some(rule) if !refinement_known(rule) =>
                  return Unsupported(
                    diag(
                      "contracts.unsupported_refinement",
                      "",
                      "unsupported refinement on: " + name,
                    ),
                  )
                _ => ()
              }
              let next_expanding = match decl {
                Transparent(_, _, _) => expanding + [key]
                _ => []
              }
              self.inventory(
                underlying,
                bound,
                visited2,
                next_expanding,
                tdepth + 1,
              )
            }
            Custom(_, constructors) => {
              for pair in constructors {
                for payload in pair.1 {
                  let outcome = self.inventory(
                    payload,
                    bound,
                    visited2,
                    [],
                    tdepth + 1,
                  )
                  if !(outcome is Valid) {
                    return outcome
                  }
                }
              }
              Valid
            }
          }
        }
      }
  }
}

///|

///|
fn Checker::step(
  self : Checker,
  ty : TypeExpr,
  value : Value,
  path : String,
  depth : Int32,
  subst : Map[String, TypeExpr],
  expanding : Array[TypeExpr],
  tdepth : Int32,
  charge : Bool,
) -> Outcome {
  self.active = self.active + 1
  if self.active > max_active_recursion {
    self.active = self.active - 1
    return Exhausted(NodeLimit)
  }
  let outcome = self.step_body(
    ty, value, path, depth, subst, expanding, tdepth, charge,
  )
  self.active = self.active - 1
  outcome
}

///|
/// One checking step. `charge` is false for type-level moves that do not
/// consume a value (variable hops and transparent alias expansion), so an
/// alias never recounts the value it names. Value-consuming moves charge
/// one node and advance depth; type-only moves advance `tdepth` instead.
fn Checker::step_body(
  self : Checker,
  ty : TypeExpr,
  value : Value,
  path : String,
  depth : Int32,
  subst : Map[String, TypeExpr],
  expanding : Array[TypeExpr],
  tdepth : Int32,
  charge : Bool,
) -> Outcome {
  if tdepth > max_type_depth {
    return Exhausted(NodeLimit)
  }
  if charge {
    if depth > self.limits.max_depth {
      return Exhausted(DepthLimit)
    }
    self.nodes = self.nodes + 1
    if self.nodes > self.limits.max_value_nodes {
      return Exhausted(NodeLimit)
    }
  }
  match ty {
    TBool =>
      match value {
        VBool(_) => Valid
        _ => mismatch(value, path, "Bool")
      }
    TInt =>
      match value {
        VInt(n) => {
          let lexeme = n.to_string()
          let digits = if lexeme.has_prefix("-") {
            lexeme.length() - 1
          } else {
            lexeme.length()
          }
          if digits > self.limits.max_int_digits {
            Exhausted(IntDigitLimit)
          } else {
            Valid
          }
        }
        _ => mismatch(value, path, "Int")
      }
    TString =>
      match value {
        VString(_) => Valid
        _ => mismatch(value, path, "String")
      }
    TVariable(name) =>
      match subst.get(name) {
        Some(found) =>
          self.step(
            found,
            value,
            path,
            depth,
            subst,
            expanding,
            tdepth + 1,
            false,
          )
        None =>
          Unsupported(
            diag(
              "contracts.unbound_variable",
              path,
              "unbound type variable: " + name,
            ),
          )
      }
    TTuple(items) =>
      match value {
        VTuple(values) => {
          if values.length() != items.length() {
            return invalid(
              "contracts.invalid_value", path, "tuple arity does not match its declared type",
            )
          }
          let mut pending : Outcome = Valid
          for i in 0..<items.length() {
            let outcome = self.step(
              items[i],
              values[i],
              child_path(path, i.to_string()),
              depth + 1,
              subst,
              [],
              0,
              true,
            )
            match outcome {
              Valid => ()
              Invalid(_) if is_ambiguous(outcome) =>
                if pending is Valid {
                  pending = outcome
                }
              _ => return outcome
            }
          }
          pending
        }
        _ => mismatch(value, path, "tuple")
      }
    TRecord(fields) => {
      let seen : Map[String, Bool] = Map([])
      for pair in fields {
        seen[pair.0] = true
      }
      match value {
        VRecord(values) => {
          let present : Map[String, Bool] = Map([])
          let mut pending : Outcome = Valid
          for (name, field_value) in values {
            if present.contains(name) {
              return invalid(
                "contracts.invalid_value",
                child_path(path, name),
                "duplicate record field: " + name,
              )
            }
            present[name] = true
            if !seen.contains(name) {
              return invalid(
                "contracts.invalid_value",
                child_path(path, name),
                "unexpected record field: " + name,
              )
            }
            let field_ty = find_field_type(fields, name).unwrap()
            let outcome = self.step(
              field_ty,
              field_value,
              child_path(path, name),
              depth + 1,
              subst,
              [],
              0,
              true,
            )
            match outcome {
              Valid => ()
              Invalid(_) if is_ambiguous(outcome) =>
                if pending is Valid {
                  pending = outcome
                }
              _ => return outcome
            }
          }
          for pair in fields {
            if !present.contains(pair.0) {
              return invalid(
                "contracts.invalid_value",
                child_path(path, pair.0),
                "missing record field: " + pair.0,
              )
            }
          }
          pending
        }
        _ => mismatch(value, path, "record")
      }
    }
    TList(elem) =>
      match value {
        VList(values) => {
          let mut pending : Outcome = Valid
          for i in 0..<values.length() {
            let outcome = self.step(
              elem,
              values[i],
              child_path(path, i.to_string()),
              depth + 1,
              subst,
              [],
              0,
              true,
            )
            match outcome {
              Valid => ()
              Invalid(_) if is_ambiguous(outcome) =>
                if pending is Valid {
                  pending = outcome
                }
              _ => return outcome
            }
          }
          pending
        }
        _ => mismatch(value, path, "list")
      }
    TSet(elem) =>
      match value {
        VSet(values) => {
          let mut pending : Outcome = Valid
          for i in 0..<values.length() {
            let outcome = self.step(
              elem,
              values[i],
              child_path(path, i.to_string()),
              depth + 1,
              subst,
              [],
              0,
              true,
            )
            match outcome {
              Valid => ()
              Invalid(_) if is_ambiguous(outcome) =>
                if pending is Valid {
                  pending = outcome
                }
              _ => return outcome
            }
            for j in 0..<i {
              if value_equal(values[j], values[i]) {
                return invalid(
                  "contracts.invalid_value",
                  child_path(path, i.to_string()),
                  "duplicate set element",
                )
              }
            }
          }
          pending
        }
        _ => mismatch(value, path, "set")
      }
    TDict(key_ty, value_ty) =>
      match value {
        VDict(entries) => {
          let mut pending : Outcome = Valid
          for i in 0..<entries.length() {
            let (key, entry_value) = entries[i]
            let key_outcome = self.step(
              key_ty,
              key,
              child_path(path, i.to_string()),
              depth + 1,
              subst,
              [],
              0,
              true,
            )
            match key_outcome {
              Valid => ()
              Invalid(_) if is_ambiguous(key_outcome) =>
                if pending is Valid {
                  pending = key_outcome
                }
              _ => return key_outcome
            }
            let value_outcome = self.step(
              value_ty,
              entry_value,
              child_path(path, i.to_string()),
              depth + 1,
              subst,
              [],
              0,
              true,
            )
            match value_outcome {
              Valid => ()
              Invalid(_) if is_ambiguous(value_outcome) =>
                if pending is Valid {
                  pending = value_outcome
                }
              _ => return value_outcome
            }
            for j in 0..<i {
              if value_equal(entries[j].0, key) {
                return invalid(
                  "contracts.invalid_value",
                  child_path(path, i.to_string()),
                  "duplicate dict key",
                )
              }
            }
          }
          pending
        }
        _ => mismatch(value, path, "dict")
      }
    TUnion(members) => {
      if members.is_empty() {
        return invalid(
          "contracts.invalid_value", path, "union has no member types",
        )
      }
      let mut matched = 0
      let mut first_failure : Outcome = Valid
      for member_ty in members {
        let outcome = self.step(
          member_ty,
          value,
          path,
          depth,
          subst,
          expanding,
          tdepth + 1,
          true,
        )
        match outcome {
          Valid => matched = matched + 1
          Unsupported(_) | Exhausted(_) => return outcome
          Invalid(_) =>
            if is_ambiguous(outcome) {
              // A member that is itself ambiguous contributes at least
              // two leaf matches, provided the member branch is viable;
              // composite members only report ambiguity when every other
              // part of the branch admits the value.
              matched = matched + 2
            } else if first_failure is Valid {
              first_failure = outcome
            }
        }
      }
      if matched == 1 {
        Valid
      } else if matched > 1 {
        invalid(
          "contracts.ambiguous_value", path, "value matches more than one union member",
        )
      } else {
        first_failure
      }
    }
    TFunction(_, _) =>
      Unsupported(
        diag(
          "contracts.unsupported_type", path, "function types are outside the bounded checking profile",
        ),
      )
    TUnsupported(name) =>
      Unsupported(
        diag("contracts.unsupported_type", path, "unsupported type: " + name),
      )
    TReference(name, args) =>
      match self.env.declarations.get(name) {
        None =>
          Unsupported(
            diag("contracts.unknown_type", path, "unknown type: " + name),
          )
        Some(decl) => {
          let params = match decl {
            Transparent(ps, _, _) => ps
            Opaque(ps, _, _) => ps
            Custom(ps, _) => ps
          }
          if params.length() != args.length() {
            return invalid(
              "contracts.invalid_value",
              path,
              "type argument count does not match declaration: " + name,
            )
          }
          let (bound, instantiated) = self.bind_arguments(
            params,
            args,
            subst,
            tdepth + 1,
          )
          if self.subst_exhausted {
            return Exhausted(NodeLimit)
          }
          // Alias identity includes the instantiation, so Id<Id<Int>>
          // expands twice while A -> B -> A with the same arguments is a
          // genuine cycle.
          let key = TReference(name, instantiated)
          match decl {
            Transparent(_, underlying, refinement) => {
              if contains_type(expanding, key) {
                return invalid(
                  "contracts.alias_cycle",
                  path,
                  "alias cycle reaches: " + name,
                )
              }
              let outcome = self.step(
                underlying,
                value,
                path,
                depth,
                bound,
                expanding + [key],
                tdepth + 1,
                false,
              )
              if outcome is Valid || is_ambiguous(outcome) {
                // The refinement decides whether this branch admits the
                // value at all; ambiguity inside the payload counts only
                // when the branch itself is viable.
                match check_refinement(refinement, value, path) {
                  Valid => outcome
                  refined => refined
                }
              } else {
                outcome
              }
            }
            Opaque(_, underlying, refinement) =>
              // No cycle check here: every recursion through an opaque
              // type consumes one constructed wrapper and charges depth,
              // so a finite value bounds the expansion.
              match value {
                VOpaque(value_name, inner) => {
                  if value_name != name {
                    return invalid(
                      "contracts.opaque_construction",
                      path,
                      "opaque value for " +
                      value_name +
                      " cannot be used as " +
                      name,
                    )
                  }
                  let outcome = self.step(
                    underlying,
                    inner,
                    path,
                    depth + 1,
                    bound,
                    [],
                    0,
                    true,
                  )
                  if outcome is Valid || is_ambiguous(outcome) {
                    match check_refinement(refinement, inner, path) {
                      Valid => outcome
                      refined => refined
                    }
                  } else {
                    outcome
                  }
                }
                _ =>
                  invalid(
                    "contracts.opaque_construction",
                    path,
                    "opaque type " +
                    name +
                    " requires a constructed value; its representation is hidden",
                  )
              }
            Custom(_, constructors) =>
              match value {
                VConstructed(ctor, payloads) =>
                  match find_constructor(constructors, ctor) {
                    None =>
                      invalid(
                        "contracts.invalid_value",
                        path,
                        "unknown constructor: " + ctor,
                      )
                    Some(payload_tys) => {
                      if payloads.length() != payload_tys.length() {
                        return invalid(
                          "contracts.invalid_value",
                          path,
                          "constructor payload count does not match: " + ctor,
                        )
                      }
                      let mut pending : Outcome = Valid
                      for i in 0..<payload_tys.length() {
                        let outcome = self.step(
                          payload_tys[i],
                          payloads[i],
                          child_path(path, i.to_string()),
                          depth + 1,
                          bound,
                          [],
                          0,
                          true,
                        )
                        match outcome {
                          Valid => ()
                          Invalid(_) if is_ambiguous(outcome) =>
                            if pending is Valid {
                              pending = outcome
                            }
                          _ => return outcome
                        }
                      }
                      pending
                    }
                  }
                VOpaque(value_name, _) =>
                  invalid(
                    "contracts.opaque_construction",
                    path,
                    "opaque value for " +
                    value_name +
                    " cannot be used as " +
                    name,
                  )
                _ =>
                  invalid(
                    "contracts.invalid_value",
                    path,
                    "value requires a constructor of: " + name,
                  )
              }
          }
        }
      }
  }
}

///|
/// Check `value` against `ty` under `env`, bounded by `limits`.
///
/// Capability is decided first: unsupported types, unknown names, unbound
/// variables and unknown refinements are reported before any value is
/// admitted. The check itself is recursive over records, custom types,
/// generics, tuples of any arity, collections and untagged unions. It
/// respects refinements and opacity, reports ambiguous union membership,
/// and never reports `Valid` after a budget is exhausted. Transparent
/// alias expansion and generic substitution consume type work, not value
/// nodes or value depth.
pub fn admit(
  env : TypeEnvironment,
  ty : TypeExpr,
  value : Value,
  limits~ : Limits = Limits::default(),
) -> Outcome {
  if env.profile != supported_profile {
    return Unsupported(
      diag(
        "contracts.unsupported_profile",
        "",
        "unsupported fixture profile: " + env.profile,
      ),
    )
  }
  match env.declaration_error {
    Some(error) => return Invalid([error])
    None => ()
  }
  let checker : Checker = {
    env,
    limits,
    nodes: 0,
    type_nodes: 0,
    subst_exhausted: false,
    active: 0,
  }
  let empty_subst : Map[String, TypeExpr] = Map([])
  let no_types : Array[TypeExpr] = []
  let inventory = checker.inventory(ty, empty_subst, no_types, no_types, 0)
  if !(inventory is Valid) {
    return inventory
  }
  checker.step(ty, value, "", 1, empty_subst, no_types, 0, true)
}
