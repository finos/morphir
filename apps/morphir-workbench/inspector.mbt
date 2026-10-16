///|
fn capitalize(value : String) -> String {
  let chars = value.to_array()
  if chars.is_empty() {
    return value
  }
  if chars[0] >= 'a' && chars[0] <= 'z' {
    chars[0] = (chars[0].to_int() - 32).unsafe_to_char()
  }
  String::from_array(chars)
}

///|
fn display_name(name : @ir.Name, upper~ : Bool = false) -> String {
  let parts = name.to_segments()
  parts
  .mapi((index, segment) => {
    match segment {
      Word(word) => if index == 0 && !upper { word } else { capitalize(word) }
      Initialism(word) => word
    }
  })
  .join("")
}

///|
fn qualified(name : @ir.FQName, upper~ : Bool = false) -> String {
  name.module_name
  .to_canonical()
  .split("/")
  .map(part => capitalize(part.to_owned()))
  .collect()
  .join(".") +
  "." +
  display_name(name.local_name, upper~)
}

///|
/// Parenthesize arguments and function inputs so higher-order signatures are unambiguous.
pub fn type_label(tpe : @ir.Type) -> String {
  match tpe {
    Variable(_, name) => display_name(name)
    Reference(_, name, args) => {
      let label = qualified(name, upper=true)
      if args.is_empty() {
        label
      } else {
        label + " " + args.map(type_argument).join(" ")
      }
    }
    Tuple(_, items) => "( " + items.map(type_label).join(", ") + " )"
    Record(_, fields) => "{ " + field_labels(fields).join(", ") + " }"
    ExtensibleRecord(_, name, fields) =>
      "{ " + display_name(name) + " | " + field_labels(fields).join(", ") + " }"
    Function(_, input, output) =>
      type_argument(input) + " → " + type_label(output)
    Unit(_) => "()"
  }
}

///|
fn type_argument(tpe : @ir.Type) -> String {
  match tpe {
    Function(_, _, _) | Reference(_, _, [_, ..]) => "(" + type_label(tpe) + ")"
    _ => type_label(tpe)
  }
}

///|
fn field_labels(fields : Map[@ir.Name, @ir.Type]) -> Array[String] {
  let result = fields
    .iter()
    .map(pair => display_name(pair.0) + " : " + type_label(pair.1))
    .collect()
  result.sort_by((a, b) => a.lexical_compare(b))
  result
}

///|
fn type_refs(tpe : @ir.Type, refs : Map[String, String]) -> Unit {
  match tpe {
    Reference(_, name, args) => {
      refs["type|" + name.to_canonical()] = qualified(name, upper=true)
      for arg in args {
        type_refs(arg, refs)
      }
    }
    Tuple(_, items) =>
      for item in items {
        type_refs(item, refs)
      }
    Record(_, fields) | ExtensibleRecord(_, _, fields) =>
      for _, item in fields {
        type_refs(item, refs)
      }
    Function(_, input, output) => {
      type_refs(input, refs)
      type_refs(output, refs)
    }
    Variable(_, _) | Unit(_) => ()
  }
}

///|
fn pattern_refs(pattern : @ir.Pattern, refs : Map[String, String]) -> Unit {
  match pattern {
    ConstructorPattern(_, name, args) => {
      refs["constructor|" + name.to_canonical()] = qualified(name, upper=true)
      for arg in args {
        pattern_refs(arg, refs)
      }
    }
    AsPattern(_, inner, _) => pattern_refs(inner, refs)
    TuplePattern(_, items) =>
      for item in items {
        pattern_refs(item, refs)
      }
    HeadTailPattern(_, head, tail) => {
      pattern_refs(head, refs)
      pattern_refs(tail, refs)
    }
    _ => ()
  }
}

///|
fn value_refs(value : @ir.Value, refs : Map[String, String]) -> Unit {
  match value {
    Reference(_, name) => refs["value|" + name.to_canonical()] = qualified(name)
    Constructor(_, name) =>
      refs["constructor|" + name.to_canonical()] = qualified(name, upper=true)
    Tuple(_, items) | List(_, items) =>
      for item in items {
        value_refs(item, refs)
      }
    Record(_, fields) =>
      for _, item in fields {
        value_refs(item, refs)
      }
    Field(_, inner, _) => value_refs(inner, refs)
    Apply(_, f, arg) => {
      value_refs(f, refs)
      value_refs(arg, refs)
    }
    Lambda(_, pattern, body) => {
      pattern_refs(pattern, refs)
      value_refs(body, refs)
    }
    LetDefinition(_, _, definition, body) => {
      definition_refs(definition, refs)
      value_refs(body, refs)
    }
    LetRecursion(_, definitions, body) => {
      for _, definition in definitions {
        definition_refs(definition, refs)
      }
      value_refs(body, refs)
    }
    Destructure(_, pattern, value, body) => {
      pattern_refs(pattern, refs)
      value_refs(value, refs)
      value_refs(body, refs)
    }
    IfThenElse(_, condition, yes, no) => {
      value_refs(condition, refs)
      value_refs(yes, refs)
      value_refs(no, refs)
    }
    PatternMatch(_, value, cases) => {
      value_refs(value, refs)
      for pair in cases {
        pattern_refs(pair.0, refs)
        value_refs(pair.1, refs)
      }
    }
    UpdateRecord(_, base, fields) => {
      value_refs(base, refs)
      for _, item in fields {
        value_refs(item, refs)
      }
    }
    Hole(_, UnresolvedReference(name), tpe) => {
      refs["value|" + name.to_canonical()] = qualified(name)
      if tpe is Some(tpe) {
        type_refs(tpe, refs)
      }
    }
    Hole(_, _, Some(tpe)) => type_refs(tpe, refs)
    _ => ()
  }
}

///|
fn definition_parts(
  definition : @ir.ValueDefinition,
) -> (Array[(@ir.Name, @ir.Type)], @ir.Type?, @ir.Value?, String) {
  match definition {
    ExpressionBody(inputs, output, body) =>
      (inputs, Some(output), Some(body), "Portable definition")
    NativeBody(inputs, output, _) =>
      (inputs, Some(output), None, "Native definition")
    ExternalBody(inputs, output, _, body) =>
      (inputs, Some(output), body, "External definition")
    IncompleteBody(inputs, output, _, body) =>
      (inputs, output, body, "Incomplete definition")
  }
}

///|
fn definition_refs(
  definition : @ir.ValueDefinition,
  refs : Map[String, String],
) -> Unit {
  let (inputs, output, body, _) = definition_parts(definition)
  for pair in inputs {
    type_refs(pair.1, refs)
  }
  if output is Some(tpe) {
    type_refs(tpe, refs)
  }
  if body is Some(value) {
    value_refs(value, refs)
  }
}

///|
fn rows(fields : Array[(@ir.Name, @ir.Type)]) -> Json {
  Json::array(
    fields.map(pair => {
      @wire.obj([
        ("name", @wire.text(display_name(pair.0))),
        ("type", @wire.text(type_label(pair.1))),
      ])
    }),
  )
}

///|
fn references(refs : Map[String, String]) -> Json {
  let keys = refs.keys().collect()
  keys.sort_by((a, b) => a.lexical_compare(b))
  Json::array(
    keys.map(key => {
      let parts = key.split("|").collect()
      @wire.obj([
        ("key", @wire.text(key)),
        ("kind", @wire.text(parts[0].to_owned())),
        ("id", @wire.text(parts[1].to_owned())),
        ("label", @wire.text(refs[key])),
      ])
    }),
  )
}

///|
fn declaration(
  id : String,
  label : String,
  kind : String,
  doc : String?,
  access : @ir.Access,
  body : Json,
  details : Array[(String, Json)],
) -> Json {
  let fields = [
    ("id", @wire.text(id)),
    ("key", @wire.text(kind + "|" + id)),
    (
      "name",
      @wire.text(
        if kind == "module" {
          id.split(":").collect()[1].to_owned()
        } else {
          id.split("#").collect()[1].to_owned()
        },
      ),
    ),
    ("label", @wire.text(label)),
    ("kind", @wire.text(kind)),
    ("module", @wire.text(id.split("#").collect()[0].to_owned())),
    ("doc", @wire.text(doc.unwrap_or(""))),
    ("access", @wire.text(if access == Public { "Public" } else { "Private" })),
    ("body", body),
    ("bodySource", @wire.text(body.stringify())),
  ]
  fields.append(details)
  @wire.obj(fields)
}

///|
fn signature(
  name : @ir.Name,
  inputs : Array[(@ir.Name, @ir.Type)],
  output : @ir.Type?,
) -> String {
  let parts = inputs.map(pair => type_argument(pair.1))
  parts.push(
    match output {
      Some(tpe) => type_label(tpe)
      None => "?"
    },
  )
  display_name(name) + " : " + parts.join(" → ")
}

///|
fn value_details(
  name : @ir.Name,
  inputs : Array[(@ir.Name, @ir.Type)],
  output : @ir.Type?,
  body : @ir.Value?,
  flavor : String,
) -> Array[(String, Json)] {
  let refs : Map[String, String] = Map([])
  for pair in inputs {
    type_refs(pair.1, refs)
  }
  if output is Some(tpe) {
    type_refs(tpe, refs)
  }
  if body is Some(value) {
    value_refs(value, refs)
  }
  [
    ("flavor", @wire.text(flavor)),
    ("signature", @wire.text(signature(name, inputs, output))),
    ("inputs", rows(inputs)),
    (
      "output",
      @wire.text(
        match output {
          Some(tpe) => type_label(tpe)
          None => "Unknown"
        },
      ),
    ),
    ("references", references(refs)),
  ]
}

///|
fn type_details(
  path : String,
  name : @ir.Name,
  params : Array[@ir.Name],
  alias_type : @ir.Type?,
  constructors : @ir.Constructors?,
  flavor : String,
) -> Array[(String, Json)] {
  let refs : Map[String, String] = Map([])
  let fields : Array[(@ir.Name, @ir.Type)] = []
  if alias_type is Some(tpe) {
    type_refs(tpe, refs)
    match tpe {
      Record(_, items) | ExtensibleRecord(_, _, items) =>
        for name, field in items {
          fields.push((name, field))
        }
      _ => ()
    }
  }
  fields.sort_by((a, b) => {
    a.0.to_canonical().lexical_compare(b.0.to_canonical())
  })
  let variants : Array[Json] = []
  if constructors is Some(items) {
    let names = items.keys().collect()
    names.sort_by((a, b) => a.to_canonical().lexical_compare(b.to_canonical()))
    for name in names {
      let args = items[name]
      for pair in args {
        type_refs(pair.1, refs)
      }
      variants.push(
        @wire.obj([
          ("id", @wire.text(path + "#" + name.to_canonical())),
          ("name", @wire.text(display_name(name, upper=true))),
          ("arguments", rows(args)),
        ]),
      )
    }
  }
  let parameter_text = if params.is_empty() {
    ""
  } else {
    " " + params.map(param => display_name(param)).join(" ")
  }
  let heading = display_name(name, upper=true) + parameter_text
  [
    ("flavor", @wire.text(flavor)),
    (
      "signature",
      @wire.text(
        match alias_type {
          Some(tpe) => heading + " = " + type_label(tpe)
          None => heading
        },
      ),
    ),
    ("fields", rows(fields)),
    ("constructors", Json::array(variants)),
    ("references", references(refs)),
  ]
}

///|
/// This projection is UI data, built from the decoded current semantic model.
/// Keys include kind because a type and value may share a fully qualified name.
fn describe(file : @ir.IRFile) -> Array[Json] raise {
  let nodes : Array[Json] = []
  match file.distribution {
    Library(package_name, _, package_def)
    | Application(package_name, _, package_def, _) =>
      for module_name, module_def in package_def.modules {
        let path = package_name.to_canonical() +
          ":" +
          module_name.to_canonical()
        nodes.push(
          declaration(
            path,
            module_name.to_canonical(),
            "module",
            module_def.value.doc,
            module_def.access,
            @codec.write_module_definition(module_def.value),
            [],
          ),
        )
        for name, item in module_def.value.types {
          let (params, alias_type, constructors, flavor) = match
            item.value.value {
            TypeAliasDefinition(params, body) =>
              (params, Some(body), None, "Type alias")
            CustomTypeDefinition(params, constructors) =>
              (
                params,
                None,
                Some(constructors.value),
                if constructors.access == Public {
                  "Custom type"
                } else {
                  "Custom type · private constructors"
                },
              )
            IncompleteTypeDefinition(params, _, body) =>
              (params, body, None, "Incomplete type")
          }
          nodes.push(
            declaration(
              path + "#" + name.to_canonical(),
              display_name(name, upper=true),
              "type",
              item.value.doc,
              item.access,
              @codec.write_type_definition(item.value.value),
              type_details(path, name, params, alias_type, constructors, flavor),
            ),
          )
        }
        for name, item in module_def.value.values {
          let (inputs, output, body, flavor) = definition_parts(
            item.value.value,
          )
          nodes.push(
            declaration(
              path + "#" + name.to_canonical(),
              display_name(name),
              "value",
              item.value.doc,
              item.access,
              @codec.write_definition(item.value.value),
              value_details(name, inputs, output, body, flavor),
            ),
          )
        }
      }
    Specs(package_name, _, package_spec) =>
      for module_name, module_spec in package_spec.modules {
        let path = package_name.to_canonical() +
          ":" +
          module_name.to_canonical()
        nodes.push(
          declaration(
            path,
            module_name.to_canonical(),
            "module",
            module_spec.doc,
            Public,
            @codec.write_module_specification(module_spec),
            [],
          ),
        )
        for name, item in module_spec.types {
          let (params, alias_type, constructors, flavor) = match
            item.value.body {
            TypeAliasSpecification(params, body) =>
              (params, Some(body), None, "Type alias specification")
            CustomTypeSpecification(params, constructors) =>
              (params, None, Some(constructors), "Custom type specification")
            OpaqueTypeSpecification(params) =>
              (params, None, None, "Opaque type specification")
            DerivedTypeSpecification(params, details) =>
              (
                params,
                Some(details.base_type),
                None,
                "Derived type specification",
              )
          }
          nodes.push(
            declaration(
              path + "#" + name.to_canonical(),
              display_name(name, upper=true),
              "type",
              item.doc,
              Public,
              @codec.write_type_specification(item.value),
              type_details(path, name, params, alias_type, constructors, flavor),
            ),
          )
        }
        for name, item in module_spec.values {
          nodes.push(
            declaration(
              path + "#" + name.to_canonical(),
              display_name(name),
              "value",
              item.doc,
              Public,
              @codec.write_value_specification(item.value),
              value_details(
                name,
                item.value.inputs,
                Some(item.value.output),
                None,
                "Value specification",
              ),
            ),
          )
        }
      }
  }
  nodes.sort_by((a, b) => {
    let am = node_text(a, "module")
    let bm = node_text(b, "module")
    if am != bm {
      am.lexical_compare(bm)
    } else {
      let ak = node_text(a, "kind")
      let bk = node_text(b, "kind")
      if ak != bk {
        ak.lexical_compare(bk)
      } else {
        node_text(a, "id").lexical_compare(node_text(b, "id"))
      }
    }
  })
  nodes
}

///|
fn node_text(node : Json, key : String) -> String {
  match node {
    Object(fields) =>
      match fields.get(key) {
        Some(String(value)) => value
        _ => ""
      }
    _ => ""
  }
}
