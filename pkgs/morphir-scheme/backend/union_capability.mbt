///|
fn require_union_free(types : Array[@ir.Type]) -> Unit raise {
  if types.any(@ir.Type::has_union) {
    raise @scheme.Unsupported(
      "Untagged unions are not supported by Scheme execution",
    )
  }
}

///|
priv struct RequiredTypes {
  named : Map[String, Array[@ir.Type]]
  values : Map[String, Array[@ir.Type]]
  constructors : Map[String, Array[@ir.Type]]
  visited : Map[String, Bool]
}

///|
fn RequiredTypes::of_file(file : @ir.IRFile) -> RequiredTypes {
  let out : RequiredTypes = {
    named: Map([]),
    values: Map([]),
    constructors: Map([]),
    visited: Map([]),
  }
  let definitions = (package_name : @ir.PackageName, d : @ir.PackageDefinition) => {
    for module_name, m in d.modules {
      for local_name, td in m.value.types {
        let n : @ir.FQName = { package_name, module_name, local_name, }
        out.named[n.to_canonical()] = td.value.value.required_types()
        if td.value.value is CustomTypeDefinition(_, variants) {
          for constructor_name, inputs in variants.value {
            let constructor_fq : @ir.FQName = {
              package_name,
              module_name,
              local_name: constructor_name,
            }
            out.constructors[constructor_fq.to_canonical()] = inputs.map(x => {
              x.1
            })
          }
        }
      }
      for local_name, v in m.value.values {
        let n : @ir.FQName = { package_name, module_name, local_name, }
        out.values[n.to_canonical()] = v.value.value.required_types()
      }
    }
  }
  let specification = (
    package_name : @ir.PackageName,
    s : @ir.PackageSpecification,
  ) => {
    for module_name, m in s.modules {
      let module_types = m.annotations
        .iter()
        .flat_map(a => a.required_types().iter())
        .collect()
      for local_name, ts in m.types {
        let n : @ir.FQName = { package_name, module_name, local_name, }
        out.named[n.to_canonical()] = [
          ..module_types,
          ..ts.value.required_types(),
        ]
        if ts.value.body is CustomTypeSpecification(_, variants) {
          let annotations = ts.value.annotations
            .iter()
            .flat_map(a => a.required_types().iter())
            .collect()
          for constructor_name, inputs in variants {
            let constructor_fq : @ir.FQName = {
              package_name,
              module_name,
              local_name: constructor_name,
            }
            out.constructors[constructor_fq.to_canonical()] = [
              ..module_types,
              ..annotations,
              ..inputs.map(x => x.1),
            ]
          }
        }
      }
      for local_name, v in m.values {
        let n : @ir.FQName = { package_name, module_name, local_name, }
        out.values[n.to_canonical()] = [
          ..module_types,
          ..v.value.required_types(),
        ]
      }
    }
  }
  match file.distribution {
    Library(n, deps, d) => {
      definitions(n, d)
      for n, s in deps {
        specification(n, s)
      }
    }
    Application(n, deps, d, _) => {
      definitions(n, d)
      for n, d in deps {
        definitions(n, d)
      }
    }
    Specs(n, deps, s) => {
      specification(n, s)
      for n, s in deps {
        specification(n, s)
      }
    }
  }
  out
}

///|
/// Check before selected_file discards aliases. Cycles are visited once.
fn RequiredTypes::check(
  self : RequiredTypes,
  types : Array[@ir.Type],
  depth~ : Int32 = 0,
) -> Unit raise {
  if depth > 256 {
    raise @scheme.Limit("Type dependency depth")
  }
  for t in types {
    if t.has_union() {
      raise SelectedReferenceInvalid("execution.unsupported_type")
    }
    for n in t.references() {
      let key = n.to_canonical()
      if !self.visited.contains(key) {
        self.visited[key] = true
        if self.named.get(key) is Some(types) {
          self.check(types, depth=depth + 1)
        }
      }
    }
  }
}
