///|
fn text(value : String) -> String {
  @scheme.Datum::Text(value).to_source()
}

///|
fn variable(name : @ir.Name) -> String {
  @scheme.symbol_text("v:" + name.to_canonical())
}

///|
fn reference(name : @ir.FQName) -> String {
  @scheme.symbol_text("r:" + name.to_canonical())
}

///|
fn curried_native(
  inputs : Array[(@ir.Name, @ir.Type)],
  binding : String,
) -> String {
  let parameters = inputs.map(input => variable(input.0))
  let mut result = "(%morphir-call-native " +
    text(binding) +
    (if parameters.is_empty() { "" } else { " " + parameters.join(" ") }) +
    ")"
  for i = parameters.length() - 1; i >= 0; i = i - 1 {
    result = "(lambda (" + parameters[i] + ") " + result + ")"
  }
  result
}

///|
fn checked_native(
  inputs : Array[(@ir.Name, @ir.Type)],
  binding : String,
) -> String {
  "(begin (%morphir-check-native " +
  text(binding) +
  " " +
  inputs.length().to_string() +
  ") " +
  curried_native(inputs, binding) +
  ")"
}

///|
priv struct Emitter {
  mut next : Int32
  globals : Map[@ir.Name, @ir.FQName]
  deferred : Bool
}

///|
fn Emitter::fresh(self : Emitter) -> String {
  self.next += 1
  "%morphir-temp-" + self.next.to_string()
}

///|
fn Emitter::literal(_self : Emitter, literal : @ir.Literal) -> String raise {
  match literal {
    BoolLiteral(b) => if b { "#t" } else { "#f" }
    CharLiteral(c) => @scheme.Datum::Character(c).to_source()
    StringLiteral(s) => text(s)
    IntegerLiteral(s) => {
      ignore(@wire.write_integer(s))
      s
    }
    FloatLiteral(n) => {
      ignore(@wire.write_float(n))
      @scheme.Number::Real(n).to_text()
    }
    DecimalLiteral(s) => {
      ignore(@wire.decimal(Json::string(s)))
      "(%morphir-tag \"decimal\" " + text(s) + ")"
    }
    DocumentLiteral(data) =>
      "(%morphir-tag \"document\" " +
      text(@wire.write_data(data).stringify()) +
      ")"
  }
}

///|
fn collect_names(
  pattern : @ir.Pattern,
  names : Array[@ir.Name],
  depth : Int32,
) -> Unit raise {
  if depth > 256 {
    raise @scheme.Limit("Pattern depth")
  }
  match pattern {
    AsPattern(_, inner, name) => {
      collect_names(inner, names, depth + 1)
      names.push(name)
    }
    TuplePattern(_, items) | ConstructorPattern(_, _, items) =>
      for item in items {
        collect_names(item, names, depth + 1)
      }
    HeadTailPattern(_, head, tail) => {
      collect_names(head, names, depth + 1)
      collect_names(tail, names, depth + 1)
    }
    _ => ()
  }
}

///|
fn Emitter::matched(
  self : Emitter,
  pattern : @ir.Pattern,
  target : String,
  body : @ir.Value,
  fallback : String,
  bound : Map[@ir.Name, Bool],
  depth : Int32,
) -> String raise {
  let names : Array[@ir.Name] = []
  collect_names(pattern, names, 0)
  let scope = Map::from_array(bound.iter().collect())
  let temp = self.fresh()
  let bindings : Array[String] = []
  let seen : Map[@ir.Name, Bool] = Map([])
  for name in names {
    if seen.contains(name) {
      raise @scheme.Invalid("Duplicate pattern binding")
    }
    seen[name] = true
    scope[name] = true
    bindings.push(
      "(" +
      variable(name) +
      " (record-ref " +
      temp +
      " " +
      text(name.to_canonical()) +
      "))",
    )
  }
  "(let ((" +
  temp +
  " (%morphir-match " +
  text(@ir_json.write_pattern(pattern).stringify()) +
  " " +
  target +
  "))) (if " +
  temp +
  " (let (" +
  bindings.join(" ") +
  ") " +
  self.value(body, scope, depth + 1) +
  ") " +
  fallback +
  "))"
}

///|
fn Emitter::definition(
  self : Emitter,
  definition : @ir.ValueDefinition,
  bound : Map[@ir.Name, Bool],
  depth : Int32,
) -> String raise {
  match definition {
    ExpressionBody(inputs, _, body) => {
      let scope = Map::from_array(bound.iter().collect())
      for (name, _) in inputs {
        scope[name] = true
      }
      let mut result = self.value(body, scope, depth + 1)
      for i = inputs.length() - 1; i >= 0; i = i - 1 {
        result = "(lambda (" + variable(inputs[i].0) + ") " + result + ")"
      }
      result
    }
    ExternalBody(inputs, _, bindings, fallback) => {
      let mut result = match fallback {
        Some(body) =>
          self.definition(
            @ir.ValueDefinition::ExpressionBody(
              inputs,
              @ir.Type::Unit(@ir.TypeAttributes::default()),
              body,
            ),
            bound,
            depth + 1,
          )
        None => "(%morphir-require-native " + text("external binding") + ")"
      }
      let candidates = runtime_external_bindings(bindings)
      for i = candidates.length() - 1; i >= 0; i = i - 1 {
        let native = candidates[i]
        result = "(if (%morphir-has-native " +
          text(native) +
          ") " +
          (if self.deferred {
            checked_native(inputs, native)
          } else {
            curried_native(inputs, native)
          }) +
          " " +
          result +
          ")"
      }
      result
    }
    NativeBody(_, _, _) =>
      if self.deferred {
        "(%morphir-require-native \"local native binding\")"
      } else {
        raise @scheme.Unsupported(
          "Native bodies require a registered runtime implementation",
        )
      }
    IncompleteBody(inputs, _, _, partial) => {
      if !self.deferred {
        raise @scheme.Unsupported("Cannot execute incomplete definition")
      }
      let scope = bound.copy()
      for (name, _) in inputs {
        scope[name] = true
      }
      if partial is Some(partial) {
        ignore(self.value(partial, scope, depth + 1))
      }
      let mut result = "(%morphir-unsupported-reached)"
      for i = inputs.length() - 1; i >= 0; i = i - 1 {
        result = "(lambda (" + variable(inputs[i].0) + ") " + result + ")"
      }
      result
    }
  }
}

///|
fn Emitter::value(
  self : Emitter,
  value : @ir.Value,
  bound : Map[@ir.Name, Bool],
  depth : Int32,
) -> String raise {
  if depth > 256 {
    raise @scheme.Limit("IR backend depth")
  }
  match value {
    Literal(_, literal) => self.literal(literal)
    Variable(_, name) =>
      if !bound.contains(name) && self.globals.get(name) is Some(name) {
        "(" + reference(name) + ")"
      } else {
        variable(name)
      }
    Reference(_, name) => "(" + reference(name) + ")"
    Constructor(_, name) =>
      "(%morphir-constructor " + text(name.to_canonical()) + ")"
    Apply(_, function, argument) => {
      if function is Apply(_, Reference(_, name), left) {
        let fq = name.to_canonical()
        if fq == "morphir/SDK:basics#and" || fq == "morphir/SDK:basics#or" {
          let lhs = "(%morphir-boolean " +
            self.value(left, bound, depth + 1) +
            ")"
          let rhs = "(%morphir-boolean " +
            self.value(argument, bound, depth + 1) +
            ")"
          return if fq == "morphir/SDK:basics#and" {
            "(if " + lhs + " " + rhs + " #f)"
          } else {
            "(if " + lhs + " #t " + rhs + ")"
          }
        }
      }
      "(" +
      self.value(function, bound, depth + 1) +
      " " +
      self.value(argument, bound, depth + 1) +
      ")"
    }
    Lambda(_, pattern, body) => {
      let arg = self.fresh()
      "(lambda (" +
      arg +
      ") " +
      self.matched(
        pattern,
        arg,
        body,
        "(error \"Lambda pattern mismatch\")",
        bound,
        depth + 1,
      ) +
      ")"
    }
    Tuple(_, items) | List(_, items) => {
      let sequence_kind = if value is @ir.Value::Tuple(_, _) {
        "vector"
      } else {
        "list"
      }
      "(" +
      sequence_kind +
      (if items.is_empty() {
        ""
      } else {
        " " + items.map(item => self.value(item, bound, depth + 1)).join(" ")
      }) +
      ")"
    }
    Record(_, fields) =>
      "(record " +
      fields
      .iter()
      .collect()
      .map(pair => {
        "(cons " +
        text(pair.0.to_canonical()) +
        " " +
        self.value(pair.1, bound, depth + 1) +
        ")"
      })
      .join(" ") +
      ")"
    Field(_, target, name) =>
      "(record-ref " +
      self.value(target, bound, depth + 1) +
      " " +
      text(name.to_canonical()) +
      ")"
    FieldFunction(_, name) => {
      let arg = self.fresh()
      "(lambda (" +
      arg +
      ") (record-ref " +
      arg +
      " " +
      text(name.to_canonical()) +
      "))"
    }
    LetDefinition(_, name, definition, body) => {
      let scope = Map::from_array(bound.iter().collect())
      scope[name] = true
      "(let ((" +
      variable(name) +
      " " +
      self.definition(definition, bound, depth + 1) +
      ")) " +
      self.value(body, scope, depth + 1) +
      ")"
    }
    LetRecursion(_, definitions, body) => {
      let scope = Map::from_array(bound.iter().collect())
      for name, _ in definitions {
        scope[name] = true
      }
      "(letrec (" +
      definitions
      .iter()
      .collect()
      .map(pair => {
        "(" +
        variable(pair.0) +
        " " +
        self.definition(pair.1, scope, depth + 1) +
        ")"
      })
      .join(" ") +
      ") " +
      self.value(body, scope, depth + 1) +
      ")"
    }
    Destructure(_, pattern, value, body) =>
      self.matched(
        pattern,
        self.value(value, bound, depth + 1),
        body,
        "(error \"Destructure pattern mismatch\")",
        bound,
        depth + 1,
      )
    IfThenElse(_, condition, yes, no) =>
      "(if (%morphir-boolean " +
      self.value(condition, bound, depth + 1) +
      ") " +
      self.value(yes, bound, depth + 1) +
      " " +
      self.value(no, bound, depth + 1) +
      ")"
    PatternMatch(_, target, cases) => {
      let temp = self.fresh()
      let mut body = "(error \"No matching pattern\")"
      for i = cases.length() - 1; i >= 0; i = i - 1 {
        body = self.matched(
          cases[i].0,
          temp,
          cases[i].1,
          body,
          bound,
          depth + 1,
        )
      }
      "(let ((" +
      temp +
      " " +
      self.value(target, bound, depth + 1) +
      ")) " +
      body +
      ")"
    }
    UpdateRecord(_, target, fields) => {
      let mut body = self.value(target, bound, depth + 1)
      for name, value in fields {
        body = "(%morphir-update " +
          body +
          " " +
          text(name.to_canonical()) +
          " " +
          self.value(value, bound, depth + 1) +
          ")"
      }
      body
    }
    Unit(_) => "(unit)"
    Hole(_, _, _) =>
      if self.deferred {
        "(%morphir-unsupported-reached)"
      } else {
        raise @scheme.Unsupported("Cannot execute a hole")
      }
  }
}

///|
pub fn emit_expression(value : @ir.Value) -> String raise {
  Emitter::{ next: 0, globals: Map([]), deferred: false, }.value(
    value,
    Map([]),
    0,
  )
}

///|
/// One emitted `define`: the symbol the text binds and the access of the value.
priv struct Symbol {
  fqname : String
  scheme_symbol : String
  public : Bool
}

///|
priv struct Emitted {
  forms : Array[String]
  symbols : Array[Symbol]
}

///|
/// `hints` maps a canonical fqname to the comment line written above its define.
fn emit_package(
  package_name : @ir.Path,
  package_def : @ir.PackageDefinition,
  hints : Map[String, String],
  emitted : Emitted,
  deferred : Bool,
) -> Unit raise {
  for module_name, module_def in package_def.modules {
    let globals : Map[@ir.Name, @ir.FQName] = Map([])
    for name, _ in module_def.value.values {
      globals[name] = { package_name, module_name, local_name: name, }
    }
    let emitter = Emitter::{ next: 0, globals, deferred, }
    for name, definition in module_def.value.values {
      let fq : @ir.FQName = { package_name, module_name, local_name: name, }
      let body = match definition.value.value {
        NativeBody(inputs, output_type, _) =>
          @ir.ValueDefinition::ExternalBody(
            inputs,
            output_type,
            [
              {
                target_platform: "morphir-scheme",
                external_name: fq.to_canonical(),
              },
            ],
            None,
          )
        other => other
      }
      let implementation = emitter.definition(body, Map([]), 0)
      let implementation = match definition.value.value {
        ExpressionBody(inputs, _, _) => {
          let binding = "accelerator:" + fq.to_canonical()
          "(if (%morphir-has-native " +
          text(binding) +
          ") " +
          (if deferred {
            checked_native(inputs, binding)
          } else {
            curried_native(inputs, binding)
          }) +
          " " +
          implementation +
          ")"
        }
        _ => implementation
      }
      let canonical = fq.to_canonical()
      let symbol = reference(fq)
      if hints.get(canonical) is Some(comment) {
        emitted.forms.push(comment)
      }
      if definition.value.doc is Some(doc) && doc != "" {
        for
          line in doc
          .split("\r\n")
          .join("\n")
          .split("\r")
          .join("\n")
          .split("\n") {
          emitted.forms.push(
            if line == "" {
              ";"
            } else {
              "; " + line.to_owned()
            },
          )
        }
      }
      emitted.forms.push(
        "(define " + symbol + " (lambda () " + implementation + "))",
      )
      emitted.symbols.push({
        fqname: canonical,
        scheme_symbol: symbol,
        public: module_def.access is Public && definition.access is Public,
      })
    }
    for _, definition in module_def.value.types {
      if definition.value.value
        is @ir.TypeDefinition::CustomTypeDefinition(_, constructors) {
        for name, params in constructors.value {
          // Retained constructor metadata remains subject to the installation
          // resource cap, including references in dormant executable branches.
          if deferred && params.length() > 256 {
            raise @scheme.Limit("Constructor arity")
          }
          let fq : @ir.FQName = { package_name, module_name, local_name: name, }
          emitted.forms.push(
            "(%morphir-register-constructor " +
            text(fq.to_canonical()) +
            " " +
            params.length().to_string() +
            ")",
          )
        }
      }
    }
  }
}

///|
fn emit_distribution(
  file : @ir.IRFile,
  hints : Map[String, String],
  deferred~ : Bool = false,
) -> Emitted raise {
  let emitted : Emitted = { forms: [], symbols: [], }
  match file.distribution {
    Library(name, _, definition) =>
      emit_package(name, definition, hints, emitted, deferred)
    Application(name, dependencies, definition, _) => {
      for dependency, implementation in dependencies {
        emit_package(dependency, implementation, hints, emitted, deferred)
      }
      emit_package(name, definition, hints, emitted, deferred)
    }
    Specs(_, _, _) =>
      raise @scheme.Unsupported("A Specs distribution has no executable bodies")
  }
  emitted
}

///|
/// Emit executable definitions. Evaluate in a runtime initialized with install().
pub fn emit_file(file : @ir.IRFile) -> String raise {
  emit_distribution(file, Map([])).forms.join("\n")
}

///|
pub fn call_entry(
  runtime : @scheme.Runtime,
  entry : @ir.FQName,
  arguments : Array[@scheme.Value],
) -> @scheme.Value raise {
  let mut value = runtime.call(runtime.lookup("r:" + entry.to_canonical()), [])
  for argument in arguments {
    value = runtime.call(value, [argument])
  }
  value
}

///|
/// Validate selected references and emit known unsupported operations as reached-only traps.
/// Structural checks, including retained constructor limits, still run eagerly.
pub fn emit_selected(file : @ir.IRFile, entry : @ir.FQName) -> String raise {
  emit_distribution(selected_file(file, entry), Map([]), deferred=true).forms.join(
    "\n",
  )
}
