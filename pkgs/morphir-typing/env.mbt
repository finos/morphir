///|
/// What inference knows about a named type.
priv enum TypeInfo {
  /// An alias: its parameters by canonical name, and its body.
  Alias(Array[String], @ir.Type)
  /// An opaque, custom or derived type, by arity.
  Nominal(Int32)
}

///|
/// The names that inference can resolve, keyed by canonical FQName text.
priv struct Env {
  types : Map[String, TypeInfo]
  constructors : Map[String, Poly]
  values : Map[String, Poly]
  /// The packages that have a specification or a definition. A reference into one of them that does not
  /// resolve is `unknown_reference`; a reference into any other pkg_name is `missing_dependency`.
  packages : Map[String, Bool]
  /// The aliases that refer to themselves, directly or through other aliases. They do not expand.
  cyclic_aliases : Map[String, Bool]
}

///|
fn Env::new() -> Env {
  {
    types: Map([]),
    constructors: Map([]),
    values: Map([]),
    packages: Map([]),
    cyclic_aliases: Map([]),
  }
}

///|
/// The environment of `file`. It holds every dependency's types, constructors and values, and the file's own
/// types and constructors. The driver adds the file's values.
fn Env::from(
  deps : Map[@ir.PackageName, @ir.PackageSpecification],
  file : @ir.IRFile,
) -> Env {
  let env = Env::new()
  for name, spec in deps {
    env.add_specification(name, spec)
  }
  match file.distribution {
    Library(name, own_deps, def) => {
      for dep, spec in own_deps {
        env.add_specification(dep, spec)
      }
      env.add_definition(name, def, false)
    }
    Specs(name, own_deps, spec) => {
      for dep, spec in own_deps {
        env.add_specification(dep, spec)
      }
      env.add_specification(name, spec)
    }
    Application(name, bundled, def, _) => {
      for dep, dep_def in bundled {
        env.add_definition(dep, dep_def, true)
        env.add_values_of_definition(dep, dep_def)
      }
      env.add_definition(name, def, false)
    }
  }
  env.find_cyclic_aliases()
  env
}

///|
fn fq_text(pkg_name : @ir.Path, module_ : @ir.Path, name : @ir.Name) -> String {
  pkg_name.to_canonical() +
  ":" +
  module_.to_canonical() +
  "#" +
  name.to_canonical()
}

///|
/// Adds the types, constructors and values of a pkg_name specification.
fn Env::add_specification(
  self : Env,
  pkg_name : @ir.PackageName,
  spec : @ir.PackageSpecification,
) -> Unit {
  self.packages[pkg_name.to_canonical()] = true
  for module_, m in spec.modules {
    for name, t in m.types {
      let key = fq_text(pkg_name, module_, name)
      match t.value.body {
        TypeAliasSpecification(params, body) =>
          self.add_alias(pkg_name, module_, name, params, body)
        OpaqueTypeSpecification(params) | DerivedTypeSpecification(params, _) =>
          self.types[key] = Nominal(params.length())
        CustomTypeSpecification(params, ctors) =>
          self.add_custom(pkg_name, module_, name, params, ctors)
      }
    }
    for name, v in m.values {
      self.values[fq_text(pkg_name, module_, name)] = poly_of_signature(
        v.value.inputs,
        v.value.output,
      )
    }
  }
}

///|
/// Adds the types and constructors of a pkg_name definition. With `public_only`, as for a bundled dependency,
/// only public modules and types count, and private constructors make their type opaque.
fn Env::add_definition(
  self : Env,
  pkg_name : @ir.PackageName,
  def : @ir.PackageDefinition,
  public_only : Bool,
) -> Unit {
  self.packages[pkg_name.to_canonical()] = true
  for module_, m in def.modules {
    if public_only && m.access is Private {
      continue
    }
    for name, t in m.value.types {
      if public_only && t.access is Private {
        continue
      }
      let key = fq_text(pkg_name, module_, name)
      match t.value.value {
        TypeAliasDefinition(params, body) =>
          self.add_alias(pkg_name, module_, name, params, body)
        CustomTypeDefinition(params, ctors) =>
          if public_only && ctors.access is Private {
            self.types[key] = Nominal(params.length())
          } else {
            self.add_custom(pkg_name, module_, name, params, ctors.value)
          }
        IncompleteTypeDefinition(params, _, _) =>
          self.types[key] = Nominal(params.length())
      }
    }
  }
}

///|
/// Adds the signatures of the public values of a bundled dependency definition.
fn Env::add_values_of_definition(
  self : Env,
  pkg_name : @ir.PackageName,
  def : @ir.PackageDefinition,
) -> Unit {
  for module_, m in def.modules {
    guard m.access is Public else { continue }
    for name, v in m.value.values {
      guard v.access is Public else { continue }
      if v.value.value.to_specification() is Some(spec) {
        self.values[fq_text(pkg_name, module_, name)] = poly_of_signature(
          spec.inputs,
          spec.output,
        )
      }
    }
  }
}

///|
/// Adds an alias. An alias of a closed record is also a constructor, as in Elm and in morphir-elm
/// (`MetaTypeMapping.lookupConstructor`): `Point 1 2` for `type alias Point = { x : Int, y : Int }`. It takes the
/// fields in declaration order and gives the alias type.
fn Env::add_alias(
  self : Env,
  pkg_name : @ir.PackageName,
  module_ : @ir.ModuleName,
  name : @ir.Name,
  params : Array[@ir.Name],
  body : @ir.Type,
) -> Unit {
  let key = fq_text(pkg_name, module_, name)
  self.types[key] = Alias(params.map(p => p.to_canonical()), body)
  guard body is Record(_, fields) else { return }
  let attrs : @ir.TypeAttributes = Default::default()
  let result : @ir.Type = Reference(
    attrs,
    { package_name: pkg_name, module_name: module_, local_name: name, },
    params.map(p => Variable(attrs, p)),
  )
  self.constructors[key] = poly_of_signature(fields.to_array(), result)
}

///|
/// Adds a custom type and its constructors. A constructor has the type `args -> T params`.
fn Env::add_custom(
  self : Env,
  pkg_name : @ir.PackageName,
  module_ : @ir.ModuleName,
  name : @ir.Name,
  params : Array[@ir.Name],
  ctors : @ir.Constructors,
) -> Unit {
  self.types[fq_text(pkg_name, module_, name)] = Nominal(params.length())
  let attrs : @ir.TypeAttributes = Default::default()
  let result : @ir.Type = Reference(
    attrs,
    { package_name: pkg_name, module_name: module_, local_name: name, },
    params.map(p => Variable(attrs, p)),
  )
  for ctor, args in ctors {
    self.constructors[fq_text(pkg_name, module_, ctor)] = poly_of_signature(
      args, result,
    )
  }
}

///|
/// Records every alias that reaches itself through alias references, such as `A = A`, `A = B` with `B = A`,
/// and the growing `T a = T (List a)`.
fn Env::find_cyclic_aliases(self : Env) -> Unit {
  for name, info in self.types {
    if info is Alias(_, _) && self.reaches(name, name, Map([])) {
      self.cyclic_aliases[name] = true
    }
  }
}

///|
/// Whether the alias `from` refers to `target`, directly or through other aliases.
fn Env::reaches(
  self : Env,
  from : String,
  target : String,
  seen : Map[String, Bool],
) -> Bool {
  guard self.types.get(from) is Some(Alias(_, body)) else { return false }
  let refs : Array[String] = []
  references_of(body, refs)
  for r in refs {
    if r == target {
      return true
    }
    if !seen.contains(r) {
      seen[r] = true
      if self.reaches(r, target, seen) {
        return true
      }
    }
  }
  false
}

///|
/// Every type name that `t` refers to.
fn references_of(t : @ir.Type, out : Array[String]) -> Unit {
  match t {
    Reference(_, name, args) => {
      out.push(name.to_canonical())
      args.each(a => references_of(a, out))
    }
    Tuple(_, items) => items.each(a => references_of(a, out))
    Record(_, fields) | ExtensibleRecord(_, _, fields) =>
      fields.values().each(a => references_of(a, out))
    Function(_, input, output) => {
      references_of(input, out)
      references_of(output, out)
    }
    Variable(_, _) | Unit(_) => ()
  }
}

///|
/// Every type reference that `t` contains, as its canonical name and its number of arguments.
fn counted_references_of(t : @ir.Type, out : Array[(String, Int32)]) -> Unit {
  match t {
    Reference(_, name, args) => {
      out.push((name.to_canonical(), args.length()))
      args.each(a => counted_references_of(a, out))
    }
    Tuple(_, items) => items.each(a => counted_references_of(a, out))
    Record(_, fields) | ExtensibleRecord(_, _, fields) =>
      fields.values().each(a => counted_references_of(a, out))
    Function(_, input, output) => {
      counted_references_of(input, out)
      counted_references_of(output, out)
    }
    Variable(_, _) | Unit(_) => ()
  }
}

///|
/// The expansion of the alias `name` applied to `args`. `None` when `name` is not an alias, is cyclic or has a
/// different arity.
fn Env::expand(self : Env, name : String, args : Array[Ty]) -> Ty? {
  guard self.types.get(name) is Some(Alias(params, body)) else { return None }
  if self.cyclic_aliases.contains(name) || params.length() != args.length() {
    return None
  }
  let bound : Map[String, Ty] = Map([])
  for i, p in params {
    bound[p] = args[i]
  }
  Some(
    to_ty(body, (name, attrs) => {
      match bound.get(name) {
        Some(t) => t
        None => Rigid(name, classes_of(name, attrs))
      }
    }),
  )
}
