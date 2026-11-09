///|
priv struct LocalNames {
  names : Map[@ir.Name, String]
  used : NameSet
  plan : TargetNames
  owner : String
}

///|
fn collect_pattern_names(
  pattern : @ir.Pattern,
  names : Map[@ir.Name, Bool],
) -> Unit {
  match pattern {
    AsPattern(_, inner, name) => {
      names[name] = true
      collect_pattern_names(inner, names)
    }
    TuplePattern(_, ps) | ConstructorPattern(_, _, ps) =>
      for p in ps {
        collect_pattern_names(p, names)
      }
    HeadTailPattern(_, a, b) => {
      collect_pattern_names(a, names)
      collect_pattern_names(b, names)
    }
    _ => ()
  }
}

///|
fn collect_local_names(value : @ir.Value, names : Map[@ir.Name, Bool]) -> Unit {
  match value {
    Variable(_, name) => names[name] = true
    Lambda(_, pattern, body) => {
      collect_pattern_names(pattern, names)
      collect_local_names(body, names)
    }
    LetDefinition(_, name, definition, body) => {
      names[name] = true
      if definition is ExpressionBody(inputs, _, value) {
        for (name, _) in inputs {
          names[name] = true
        }
        collect_local_names(value, names)
      }
      collect_local_names(body, names)
    }
    Apply(_, a, b) => {
      collect_local_names(a, names)
      collect_local_names(b, names)
    }
    Tuple(_, xs) | List(_, xs) =>
      for x in xs {
        collect_local_names(x, names)
      }
    Record(_, fields) =>
      for _, value in fields {
        collect_local_names(value, names)
      }
    Field(_, value, _) => collect_local_names(value, names)
    Destructure(_, pattern, value, body) => {
      collect_pattern_names(pattern, names)
      collect_local_names(value, names)
      collect_local_names(body, names)
    }
    IfThenElse(_, a, b, c) => {
      collect_local_names(a, names)
      collect_local_names(b, names)
      collect_local_names(c, names)
    }
    PatternMatch(_, value, cases) => {
      collect_local_names(value, names)
      for (pattern, body) in cases {
        collect_pattern_names(pattern, names)
        collect_local_names(body, names)
      }
    }
    UpdateRecord(_, value, fields) => {
      collect_local_names(value, names)
      for _, v in fields {
        collect_local_names(v, names)
      }
    }
    _ => ()
  }
}

///|
fn LocalNames::new(
  plan : TargetNames,
  declaration : Declaration,
) -> LocalNames raise {
  let owner = value_node(declaration.fqname)
  let keys = Map::from_array(declaration.inputs.map(p => (p.0, true)))
  collect_local_names(declaration.body, keys)
  let names = keys.keys().collect()
  names.sort()
  let hints : Map[String, (String, @diagnostics.Span?)] = Map([])
  let ambiguous : Map[String, Bool] = Map([])
  fn save_hint(
    id : String,
    text : String,
    source : @diagnostics.Span?,
  ) -> Unit {
    if hints.contains(id) {
      hints.remove(id)
      ambiguous[id] = true
    } else if !ambiguous.contains(id) {
      hints[id] = (text, source)
    }
  }
  if plan.origins.get(owner) is Some(data) {
    if hint_field(data, "parameters") is Some(v) && v.kind() is List(parameters) {
      for i, p in parameters {
        let identity = match hint_text(p, "identity") {
          Some(id) => Some(id)
          None if parameters.length() == declaration.inputs.length() =>
            Some(declaration.inputs[i].0.to_canonical())
          None => None
        }
        if identity is Some(id) && hint_text(p, "name") is Some(text) {
          save_hint(id, text, hint_span(p))
        }
      }
    }
  }
  if plan.origins.get(owner + "/body") is Some(data) {
    if hint_field(data, "nodes") is Some(v) && v.kind() is List(nodes) {
      for n in nodes {
        if hint_field(n, "binding") is Some(binding) &&
          hint_text(n, "identity") is Some(id) &&
          hint_text(n, "allocation_reason") != Some("lexical-shadow") {
          if hint_text(binding, "name") is Some(text) {
            save_hint(id, text, hint_span(binding))
          }
        }
      }
    }
  }
  let result : LocalNames = {
    names: Map([]),
    used: NameSet::over(plan.reserved),
    plan,
    owner,
  }
  let candidates = []
  for name in names {
    validate_name(name)
    let id = owner + "/local/" + name.to_canonical()
    let hint = hints.get(name.to_canonical())
    let c = candidate(
      id,
      "local",
      name,
      declaration.module_name,
      hint.map(h => h.0),
      hint.map(h => h.1).unwrap_or(None),
      false,
    )
    let c = if plan.style == LegacyHex {
      {
        ..c,
        candidate: local_name(name),
        qualified: local_name(name) + "_local",
        reason: "legacy",
      }
    } else {
      { ..c, qualified: c.candidate + "_local", }
    }
    candidates.push(c)
  }
  allocate_namespace(plan, candidates, result.used, reserve_global=false)
  for name in names {
    result.names[name] = plan.names[owner + "/local/" + name.to_canonical()]
    result.used.add(result.names[name])
  }
  result
}

///|
fn LocalNames::fresh(self : LocalNames, role : String) -> String {
  let mut ordinal = 1
  while true {
    let name = role + "_" + ordinal.to_string()
    if !self.used.contains(name) {
      self.used.add(name)
      self.plan.allocations.push({
        owner: self.owner + "/temporary/" + name,
        role: "temporary",
        original: None,
        requested: None,
        candidate: role,
        allocated: name,
        reason: "fresh",
      })
      return name
    }
    ordinal += 1
  } nobreak {
    abort("unreachable")
  }
}
