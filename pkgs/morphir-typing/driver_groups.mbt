///|
/// The value declarations of a library or an application, in IR order.
fn collect_declarations(file : @ir.IRFile) -> Array[Decl] {
  let (pkg_name, def) = match file.distribution {
    Library(name, _, def) | Application(name, _, def, _) => (name, def)
    Specs(_, _, _) => return []
  }
  let out : Array[Decl] = []
  for module_, m in def.modules {
    for name, v in m.value.values {
      let fq : @ir.FQName = {
        package_name: pkg_name,
        module_name: module_,
        local_name: name,
      }
      let def = v.value.value
      out.push({
        key: fq.to_canonical(),
        root: @identities.value_root(fq),
        def,
        declared: is_declared(def),
      })
    }
  }
  out
}

///|
/// A definition is declared when it has an output type and no signature variable carries the unknown marker.
fn is_declared(def : @ir.ValueDefinition) -> Bool {
  let (inputs, output, _) = definition_parts(def)
  guard output is Some(output) else { return false }
  !has_marker(output) && !inputs.iter().any(input => has_marker(input.1))
}

///|
/// The binding groups, in dependency order: a group comes after every group that it refers to. A declaration
/// refers to the undeclared values of the file that its body names. Declared values need no order, because
/// their schemes are known before any group is solved.
fn Driver::groups(self : Driver) -> Array[Array[Int32]] {
  let edges = self.decls.map(d => self.edges(d))
  let n = self.decls.length()
  let t : Tarjan = {
    edges,
    index: Array::make(n, -1),
    low: Array::make(n, 0),
    on_stack: Array::make(n, false),
    stack: [],
    counter: 0,
    groups: [],
  }
  for v = 0; v < n; v = v + 1 {
    if t.index[v] < 0 {
      t.visit(v)
    }
  }
  t.groups
}

///|
/// The undeclared declarations of the file that the body of `d` refers to, in first-seen order.
fn Driver::edges(self : Driver, d : Decl) -> Array[Int32] {
  let refs : Array[String] = []
  if definition_parts(d.def).2 is Some(body) {
    references_in(body, refs)
  }
  let out : Array[Int32] = []
  for key in refs {
    if self.index.get(key) is Some(j) &&
      !self.decls[j].declared &&
      !out.contains(j) {
      out.push(j)
    }
  }
  out
}

///|
/// Every value reference in `v`, as canonical FQName text.
fn references_in(v : @ir.Value, out : Array[String]) -> Unit {
  if v is Reference(_, name) {
    out.push(name.to_canonical())
  }
  for child in value_children(v) {
    references_in(child, out)
  }
}

///|
/// The values directly inside `v`, including the bodies of its let definitions.
fn value_children(v : @ir.Value) -> Array[@ir.Value] {
  match v {
    Tuple(_, items) | List(_, items) => items
    Record(_, fields) => fields.values().collect()
    UpdateRecord(_, record, fields) => [record, ..fields.values()]
    Field(_, record, _) => [record]
    Apply(_, f, a) => [f, a]
    Lambda(_, _, body) => [body]
    LetDefinition(_, _, def, rest) => [..definition_parts(def).2, rest]
    LetRecursion(_, defs, rest) => {
      let out = defs
        .values()
        .filter_map(def => definition_parts(def).2)
        .collect()
      out.push(rest)
      out
    }
    Destructure(_, _, value, rest) => [value, rest]
    IfThenElse(_, c, t, e) => [c, t, e]
    PatternMatch(_, subject, cases) => [subject, ..cases.map(c => c.1)]
    Literal(_, _)
    | Constructor(_, _)
    | Variable(_, _)
    | Reference(_, _)
    | FieldFunction(_, _)
    | Unit(_)
    | Hole(_, _, _) => []
  }
}

///|
/// Tarjan's algorithm for strongly connected components. A component is emitted after every component that
/// it reaches, so the components come out in dependency order.
priv struct Tarjan {
  edges : Array[Array[Int32]]
  index : Array[Int32]
  low : Array[Int32]
  on_stack : Array[Bool]
  stack : Array[Int32]
  mut counter : Int32
  groups : Array[Array[Int32]]
}

///|
fn Tarjan::visit(self : Tarjan, v : Int32) -> Unit {
  self.index[v] = self.counter
  self.low[v] = self.counter
  self.counter += 1
  self.stack.push(v)
  self.on_stack[v] = true
  for w in self.edges[v] {
    if self.index[w] < 0 {
      self.visit(w)
      self.low[v] = min_int(self.low[v], self.low[w])
    } else if self.on_stack[w] {
      self.low[v] = min_int(self.low[v], self.index[w])
    }
  }
  if self.low[v] == self.index[v] {
    let group : Array[Int32] = []
    while self.stack.pop() is Some(w) {
      self.on_stack[w] = false
      group.push(w)
      if w == v {
        break
      }
    }
    // Within a group, declarations are solved in IR order.
    group.sort()
    self.groups.push(group)
  }
}

///|
fn min_int(a : Int32, b : Int32) -> Int32 {
  if a < b {
    a
  } else {
    b
  }
}
