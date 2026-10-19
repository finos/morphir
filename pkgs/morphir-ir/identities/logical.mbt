///|
/// One identity of `nodes`, with a logical path that does not depend on the encoding.
///
/// - Inside a value definition of the file's own package, `path` uses the grammar of `paths.mbt` from the root of
///   the identity family, and the JSON inside a node has the path `<node path>!<suffix>`, where `<suffix>` is the
///   JSON-pointer suffix in the expanded form of the node. A node therefore has the same logical paths in its
///   compact and in its expanded form.
/// - Everywhere else, `path` is the identity.
/// - `tag` is the variant name of a Value, Pattern or Type node, `"declaration"` for a declaration identity with
///   no JSON, else empty.
/// - `attribute` is true inside the attributes of a node.
/// - `marker` is true for a type variable or extensible record with the unknown marker.
/// - `leaf` is the logical path and the value of a JSON scalar, as the expanded form places it.
pub(all) struct LogicalNode {
  path : String
  id : String
  tag : String
  attribute : Bool
  marker : Bool
  leaf : (String, Json)?
} derive(Eq, Debug)

///|
pub extend LogicalNode with Eq::{equal, not_equal}

///|
pub extend LogicalNode with @debug.Debug::{to_repr}

///|
priv struct Walk {
  out : Map[String, LogicalNode]
}

///|
fn Walk::add(
  self : Walk,
  id : String,
  path : String,
  tag~ : String = "",
  attribute~ : Bool = false,
  marker~ : Bool = false,
  leaf~ : (String, Json)? = None,
) -> Unit {
  self.out[id] = { path, id, tag, attribute, marker, leaf, }
}

///|
/// Every JSON node of `json`, at `id` and below, with the same suffix on `path`.
fn Walk::content(
  self : Walk,
  json : Json,
  id : String,
  path : String,
  attribute~ : Bool = false,
) -> Unit {
  match json {
    Object(fields) => {
      self.add(id, path, attribute~)
      for key, item in fields {
        self.content(
          item,
          id + "/" + part(key),
          path + "/" + part(key),
          attribute~,
        )
      }
    }
    Array(items) => {
      self.add(id, path, attribute~)
      for i, item in items {
        self.content(item, id + "/\{i}", path + "/\{i}", attribute~)
      }
    }
    _ => self.add(id, path, attribute~, leaf=Some((path, json)))
  }
}

///|
fn field(json : Json, key : String) -> Json raise {
  match json {
    Object(fields) =>
      match fields.get(key) {
        Some(item) => item
        None => raise @codec_boundary.Invalid("identity.layout", key)
      }
    _ => raise @codec_boundary.Invalid("identity.layout", key)
  }
}

///|
fn index(json : Json, i : Int32) -> Json raise {
  match json {
    Array(items) if i < items.length() => items[i]
    _ => raise @codec_boundary.Invalid("identity.layout", i.to_string())
  }
}

///|
fn key_text(json : Json) -> String raise {
  match json {
    String(text) => text
    _ => raise @codec_boundary.Invalid("identity.layout", "key")
  }
}

///|
fn name_key(name : @ir.Name) -> String raise {
  key_text(@codec_boundary.write_name(name))
}

///|
/// The payload of a tagged node `{tag: payload}`. Its id is `id/tag` and its expanded path is `path!/tag`. The
/// payload's `attributes`, when present, are attribute content. Every key of `skip` is a child that the caller
/// walks; every other key is content.
fn Walk::payload(
  self : Walk,
  json : Json,
  id : String,
  path : String,
  tag : String,
  skip : Array[String],
) -> Json raise {
  let payload = field(json, tag)
  let pid = id + "/" + tag
  let ppath = path + "!/" + tag
  self.add(pid, ppath)
  match payload {
    Object(fields) =>
      for key, item in fields {
        if skip.contains(key) {
          continue
        }
        self.content(
          item,
          pid + "/" + part(key),
          ppath + "/" + part(key),
          attribute=key == "attributes",
        )
      }
    _ => ()
  }
  payload
}

///|
/// A compact payload: the expanded form keeps it under `field`.
fn Walk::compact(
  self : Walk,
  json : Json,
  id : String,
  path : String,
  tag : String,
  expanded_field : String,
) -> Json raise {
  let payload = field(json, tag)
  self.content(
    payload,
    id + "/" + tag,
    path + "!/" + tag + "/" + expanded_field,
  )
  payload
}

///|
fn empty_value_attributes(a : @ir.ValueAttributes) -> Bool {
  a.source is None && a.inferred_type is None && a.extensions.is_empty()
}

///|
fn empty_type_attributes(a : @ir.TypeAttributes) -> Bool {
  a.source is None && a.constraints.is_empty() && a.extensions.is_empty()
}

///|
fn Walk::value(
  self : Walk,
  v : @ir.Value,
  json : Json,
  id : String,
  path : String,
) -> Unit raise {
  let (tag, attrs) = value_tag(v)
  self.add(id, path, tag~)
  let compact = empty_value_attributes(attrs)
  match v {
    Literal(_, _) if compact =>
      ignore(self.compact(json, id, path, tag, "literal"))
    Constructor(_, _) if compact =>
      ignore(self.compact(json, id, path, tag, "fqname"))
    Variable(_, _) if compact =>
      ignore(self.compact(json, id, path, tag, "name"))
    Reference(_, _) if compact =>
      ignore(self.compact(json, id, path, tag, "fqname"))
    FieldFunction(_, _) if compact =>
      ignore(self.compact(json, id, path, tag, "name"))
    Tuple(_, items) if compact => {
      let payload = field(json, tag)
      self.add(id + "/" + tag, path + "!/Tuple/elements")
      for i, item in items {
        self.value(
          item,
          index(payload, i),
          id + "/" + tag + "/\{i}",
          path_item(path, i),
        )
      }
    }
    List(_, items) if compact => {
      let payload = field(json, tag)
      self.add(id + "/" + tag, path + "!/List/items")
      for i, item in items {
        self.value(
          item,
          index(payload, i),
          id + "/" + tag + "/\{i}",
          path_item(path, i),
        )
      }
    }
    _ => self.value_expanded(v, json, id, path, tag)
  }
}

///|
fn value_tag(v : @ir.Value) -> (String, @ir.ValueAttributes) {
  match v {
    Literal(a, _) => ("Literal", a)
    Constructor(a, _) => ("Constructor", a)
    Tuple(a, _) => ("Tuple", a)
    List(a, _) => ("List", a)
    Record(a, _) => ("Record", a)
    Variable(a, _) => ("Variable", a)
    Reference(a, _) => ("Reference", a)
    Field(a, _, _) => ("Field", a)
    FieldFunction(a, _) => ("FieldFunction", a)
    Apply(a, _, _) => ("Apply", a)
    Lambda(a, _, _) => ("Lambda", a)
    LetDefinition(a, _, _, _) => ("LetDefinition", a)
    LetRecursion(a, _, _) => ("LetRecursion", a)
    Destructure(a, _, _, _) => ("Destructure", a)
    IfThenElse(a, _, _, _) => ("IfThenElse", a)
    PatternMatch(a, _, _) => ("PatternMatch", a)
    UpdateRecord(a, _, _) => ("UpdateRecord", a)
    Unit(a) => ("Unit", a)
    Hole(a, _, _) => ("Hole", a)
  }
}

///|
/// A child container of a payload: an array or a map of child nodes. The container itself is content.
fn Walk::container(
  self : Walk,
  payload : Json,
  id : String,
  path : String,
  tag : String,
  key : String,
) -> Json raise {
  let json = field(payload, key)
  self.add(id + "/" + tag + "/" + key, path + "!/" + tag + "/" + key)
  json
}

///|
fn Walk::value_expanded(
  self : Walk,
  v : @ir.Value,
  json : Json,
  id : String,
  path : String,
  tag : String,
) -> Unit raise {
  let at = fn(key : String) { id + "/" + tag + "/" + key }
  match v {
    Literal(_, _)
    | Constructor(_, _)
    | Variable(_, _)
    | Reference(_, _)
    | FieldFunction(_, _)
    | Unit(_) => ignore(self.payload(json, id, path, tag, []))
    Tuple(_, items) | List(_, items) => {
      let key = if v is Tuple(_, _) { "elements" } else { "items" }
      let payload = self.payload(json, id, path, tag, [key])
      let list = self.container(payload, id, path, tag, key)
      for i, item in items {
        self.value(item, index(list, i), at(key) + "/\{i}", path_item(path, i))
      }
    }
    Record(_, fields) => {
      let payload = self.payload(json, id, path, tag, ["fields"])
      let map = self.container(payload, id, path, tag, "fields")
      for n, item in fields {
        let k = name_key(n)
        self.value(
          item,
          field(map, k),
          at("fields") + "/" + part(k),
          path_field(path, n),
        )
      }
    }
    Field(_, record, _) => {
      let payload = self.payload(json, id, path, tag, ["target"])
      self.value(
        record,
        field(payload, "target"),
        at("target"),
        path_record(path),
      )
    }
    Apply(_, f, a) => {
      let payload = self.payload(json, id, path, tag, ["function", "argument"])
      self.value(
        f,
        field(payload, "function"),
        at("function"),
        path_function(path),
      )
      self.value(
        a,
        field(payload, "argument"),
        at("argument"),
        path_argument(path),
      )
    }
    Lambda(_, p, body) => {
      let payload = self.payload(json, id, path, tag, ["pattern", "body"])
      self.pattern(
        p,
        field(payload, "pattern"),
        at("pattern"),
        path_pattern(path),
      )
      self.value(body, field(payload, "body"), at("body"), path_body(path))
    }
    LetDefinition(_, _, def, rest) => {
      let payload = self.payload(json, id, path, tag, ["definition", "in"])
      self.definition(
        def,
        field(payload, "definition"),
        at("definition"),
        path_definition(path),
      )
      self.value(rest, field(payload, "in"), at("in"), path_in(path))
    }
    LetRecursion(_, defs, rest) => {
      let payload = self.payload(json, id, path, tag, ["definitions", "in"])
      let map = self.container(payload, id, path, tag, "definitions")
      for n, def in defs {
        let k = name_key(n)
        self.definition(
          def,
          field(map, k),
          at("definitions") + "/" + part(k),
          path_definitions(path, n),
        )
      }
      self.value(rest, field(payload, "in"), at("in"), path_in(path))
    }
    Destructure(_, p, value, rest) => {
      let payload = self.payload(json, id, path, tag, ["pattern", "value", "in"])
      self.pattern(
        p,
        field(payload, "pattern"),
        at("pattern"),
        path_pattern(path),
      )
      self.value(value, field(payload, "value"), at("value"), path_value(path))
      self.value(rest, field(payload, "in"), at("in"), path_in(path))
    }
    IfThenElse(_, c, t, e) => {
      let payload = self.payload(json, id, path, tag, [
        "condition", "then", "else",
      ])
      self.value(
        c,
        field(payload, "condition"),
        at("condition"),
        path_condition(path),
      )
      self.value(t, field(payload, "then"), at("then"), path_then(path))
      self.value(e, field(payload, "else"), at("else"), path_else(path))
    }
    PatternMatch(_, subject, cases) => {
      let payload = self.payload(json, id, path, tag, ["value", "cases"])
      self.value(
        subject,
        field(payload, "value"),
        at("value"),
        path_subject(path),
      )
      let list = self.container(payload, id, path, tag, "cases")
      for i, case in cases {
        let cid = at("cases") + "/\{i}"
        let item = index(list, i)
        self.add(cid, path + "!/PatternMatch/cases/\{i}")
        self.pattern(
          case.0,
          field(item, "pattern"),
          cid + "/pattern",
          path_case_pattern(path, i),
        )
        self.value(
          case.1,
          field(item, "body"),
          cid + "/body",
          path_case_body(path, i),
        )
      }
    }
    UpdateRecord(_, record, fields) => {
      let payload = self.payload(json, id, path, tag, ["target", "fields"])
      self.value(
        record,
        field(payload, "target"),
        at("target"),
        path_record(path),
      )
      let map = self.container(payload, id, path, tag, "fields")
      for n, item in fields {
        let k = name_key(n)
        self.value(
          item,
          field(map, k),
          at("fields") + "/" + part(k),
          path_field(path, n),
        )
      }
    }
    Hole(_, _, expected) => {
      let payload = self.payload(json, id, path, tag, ["expectedType"])
      if expected is Some(t) {
        self.type_(
          t,
          field(payload, "expectedType"),
          at("expectedType"),
          path_expected(path),
        )
      }
    }
  }
}

///|
fn pattern_tag(p : @ir.Pattern) -> (String, @ir.ValueAttributes) {
  match p {
    WildcardPattern(a) => ("WildcardPattern", a)
    AsPattern(a, _, _) => ("AsPattern", a)
    TuplePattern(a, _) => ("TuplePattern", a)
    ConstructorPattern(a, _, _) => ("ConstructorPattern", a)
    EmptyListPattern(a) => ("EmptyListPattern", a)
    HeadTailPattern(a, _, _) => ("HeadTailPattern", a)
    LiteralPattern(a, _) => ("LiteralPattern", a)
    UnitPattern(a) => ("UnitPattern", a)
  }
}

///|
fn Walk::pattern(
  self : Walk,
  p : @ir.Pattern,
  json : Json,
  id : String,
  path : String,
) -> Unit raise {
  let (tag, attrs) = pattern_tag(p)
  self.add(id, path, tag~)
  let compact = empty_value_attributes(attrs)
  let at = fn(key : String) { id + "/" + tag + "/" + key }
  match p {
    LiteralPattern(_, _) if compact =>
      ignore(self.compact(json, id, path, tag, "literal"))
    TuplePattern(_, items) if compact => {
      let payload = field(json, tag)
      self.add(id + "/" + tag, path + "!/TuplePattern/patterns")
      for i, item in items {
        self.pattern(
          item,
          index(payload, i),
          id + "/" + tag + "/\{i}",
          path_item(path, i),
        )
      }
    }
    TuplePattern(_, items) => {
      let payload = self.payload(json, id, path, tag, ["patterns"])
      let list = self.container(payload, id, path, tag, "patterns")
      for i, item in items {
        self.pattern(
          item,
          index(list, i),
          at("patterns") + "/\{i}",
          path_item(path, i),
        )
      }
    }
    ConstructorPattern(_, _, args) => {
      let payload = self.payload(json, id, path, tag, ["patterns"])
      let list = self.container(payload, id, path, tag, "patterns")
      for i, item in args {
        self.pattern(
          item,
          index(list, i),
          at("patterns") + "/\{i}",
          path_arg(path, i),
        )
      }
    }
    AsPattern(_, inner, _) => {
      let payload = self.payload(json, id, path, tag, ["pattern"])
      self.pattern(
        inner,
        field(payload, "pattern"),
        at("pattern"),
        path_pattern(path),
      )
    }
    HeadTailPattern(_, head, tail) => {
      let payload = self.payload(json, id, path, tag, ["head", "tail"])
      self.pattern(head, field(payload, "head"), at("head"), path_head(path))
      self.pattern(tail, field(payload, "tail"), at("tail"), path_tail(path))
    }
    _ => ignore(self.payload(json, id, path, tag, []))
  }
}

///|
fn type_tag(t : @ir.Type) -> (String, @ir.TypeAttributes) {
  match t {
    Union(a, _) => ("Union", a)
    Variable(a, _) => ("Variable", a)
    Reference(a, _, _) => ("Reference", a)
    Tuple(a, _) => ("Tuple", a)
    Record(a, _) => ("Record", a)
    ExtensibleRecord(a, _, _) => ("ExtensibleRecord", a)
    Function(a, _, _) => ("Function", a)
    Unit(a) => ("Unit", a)
  }
}

///|
fn Walk::type_(
  self : Walk,
  t : @ir.Type,
  json : Json,
  id : String,
  path : String,
) -> Unit raise {
  let (tag, attrs) = type_tag(t)
  let marker = (t is Variable(_, _) || t is ExtensibleRecord(_, _, _)) &&
    attrs.is_unknown()
  let compact = empty_type_attributes(attrs)
  let at = fn(key : String) { id + "/" + tag + "/" + key }
  match t {
    Variable(_, _) if compact =>
      self.add(id, path, tag~, leaf=Some((path + "!/Variable/name", json)))
    Reference(_, _, []) if compact =>
      self.add(id, path, tag~, leaf=Some((path + "!/Reference/fqname", json)))
    Reference(_, _, args) if compact => {
      self.add(id, path, tag~)
      let payload = field(json, tag)
      self.add(id + "/" + tag, path + "!/Reference/args")
      self.content(
        index(payload, 0),
        id + "/" + tag + "/0",
        path + "!/Reference/fqname",
      )
      for i, arg in args {
        self.type_(
          arg,
          index(payload, i + 1),
          id + "/" + tag + "/\{i + 1}",
          path_arg(path, i),
        )
      }
    }
    Union(_, items) if compact => {
      self.add(id, path, tag~)
      let payload = field(json, tag)
      self.add(id + "/" + tag, path + "!/Union/alternatives")
      for i, item in items {
        self.type_(
          item,
          index(payload, i),
          id + "/" + tag + "/\{i}",
          path_alternative(path, i),
        )
      }
    }
    Union(_, items) => {
      self.add(id, path, tag~)
      let payload = self.payload(json, id, path, tag, ["alternatives"])
      let list = self.container(payload, id, path, tag, "alternatives")
      for i, item in items {
        self.type_(
          item,
          index(list, i),
          at("alternatives") + "/\{i}",
          path_alternative(path, i),
        )
      }
    }
    Tuple(_, items) if compact => {
      self.add(id, path, tag~)
      let payload = field(json, tag)
      self.add(id + "/" + tag, path + "!/Tuple/elements")
      for i, item in items {
        self.type_(
          item,
          index(payload, i),
          id + "/" + tag + "/\{i}",
          path_item(path, i),
        )
      }
    }
    Reference(_, _, args) => {
      self.add(id, path, tag~)
      let payload = self.payload(json, id, path, tag, ["args"])
      let list = self.container(payload, id, path, tag, "args")
      for i, arg in args {
        self.type_(arg, index(list, i), at("args") + "/\{i}", path_arg(path, i))
      }
    }
    Tuple(_, items) => {
      self.add(id, path, tag~)
      let payload = self.payload(json, id, path, tag, ["elements"])
      let list = self.container(payload, id, path, tag, "elements")
      for i, item in items {
        self.type_(
          item,
          index(list, i),
          at("elements") + "/\{i}",
          path_item(path, i),
        )
      }
    }
    Record(_, fields) | ExtensibleRecord(_, _, fields) => {
      self.add(id, path, tag~, marker~)
      let payload = self.payload(json, id, path, tag, ["fields"])
      let map = self.container(payload, id, path, tag, "fields")
      for n, item in fields {
        let k = name_key(n)
        self.type_(
          item,
          field(map, k),
          at("fields") + "/" + part(k),
          path_field(path, n),
        )
      }
    }
    Function(_, input, output) => {
      self.add(id, path, tag~)
      let payload = self.payload(json, id, path, tag, [
        "parameterType", "returnType",
      ])
      self.type_(
        input,
        field(payload, "parameterType"),
        at("parameterType"),
        path_parameter(path),
      )
      self.type_(
        output,
        field(payload, "returnType"),
        at("returnType"),
        path_return(path),
      )
    }
    Variable(_, _) | Unit(_) => {
      self.add(id, path, tag~, marker~)
      ignore(self.payload(json, id, path, tag, []))
    }
  }
}

///|
fn definition_tag(def : @ir.ValueDefinition) -> String {
  match def {
    ExpressionBody(_, _, _) => "ExpressionBody"
    NativeBody(_, _, _) => "NativeBody"
    ExternalBody(_, _, _, _) => "ExternalBody"
    IncompleteBody(_, _, _, _) => "IncompleteBody"
  }
}

///|
/// A value definition. `json` is `{tag: payload}`, with a `doc` key beside the tag in the file's own encoding.
fn Walk::definition(
  self : Walk,
  def : @ir.ValueDefinition,
  json : Json,
  id : String,
  path : String,
) -> Unit raise {
  let tag = definition_tag(def)
  self.add(id, path)
  if json is Object(fields) && fields.get("doc") is Some(doc) {
    self.content(doc, id + "/doc", path + "!/doc")
  }
  let (inputs, output, body) = match def {
    ExpressionBody(xs, out, b) => (xs, Some(out), Some(b))
    NativeBody(xs, out, _) => (xs, Some(out), None)
    ExternalBody(xs, out, _, b) => (xs, Some(out), b)
    IncompleteBody(xs, out, _, b) => (xs, out, b)
  }
  let body_key = if def is IncompleteBody(_, _, _, _) {
    "partialBody"
  } else {
    "body"
  }
  let payload = self.payload(json, id, path, tag, [
    "inputTypes", "outputType", body_key,
  ])
  let at = fn(key : String) { id + "/" + tag + "/" + key }
  let ins = self.container(payload, id, path, tag, "inputTypes")
  match ins {
    Object(_) =>
      for input in inputs {
        let k = name_key(input.0)
        self.type_(
          input.1,
          field(ins, k),
          at("inputTypes") + "/" + part(k),
          path_input(path, input.0),
        )
      }
    _ =>
      for i, input in inputs {
        let pid = at("inputTypes") + "/\{i}"
        let pair = index(ins, i)
        self.add(pid, path + "!/" + tag + "/inputTypes/\{i}")
        self.content(
          index(pair, 0),
          pid + "/0",
          path + "!/" + tag + "/inputTypes/\{i}/0",
        )
        self.type_(
          input.1,
          index(pair, 1),
          pid + "/1",
          path_input(path, input.0),
        )
      }
  }
  if output is Some(t) {
    self.type_(
      t,
      field(payload, "outputType"),
      at("outputType"),
      path_output(path),
    )
  }
  if body is Some(b) {
    self.value(b, field(payload, body_key), at(body_key), path_body(path))
  }
}

///|
fn access_tag(access : @ir.Access) -> String {
  match access {
    Public => "Public"
    Private => "Private"
  }
}

///|
/// One logical node for each identity of `nodes(unit_id, file)`, in the same order. The logical paths are unique
/// within one file. See `LogicalNode`.
pub fn logical_nodes(
  unit_id : String,
  file : @ir.IRFile,
) -> Array[LogicalNode] raise {
  let ids = nodes(unit_id, file)
  let walk : Walk = { out: Map([]), }
  let root = "unit:" + unit_id + "/ir"
  let json = @ir_json.to_json(file)
  walk.content(json, root, root)
  let (dist_tag, own) = match file.distribution {
    Library(name, _, def) => ("Library", Some((name, def)))
    Application(name, _, def, _) => ("Application", Some((name, def)))
    Specs(_, _, _) => ("Specs", None)
  }
  if own is Some((package_name, def)) {
    let modules = field(
      field(field(field(json, "distribution"), dist_tag), "def"),
      "modules",
    )
    for module_name, m in def.modules {
      let mkey = key_text(@codec_boundary.write_path(module_name))
      let macc = access_tag(m.access)
      let values = field(field(field(modules, mkey), macc), "values")
      for value_name, v in m.value.values {
        let vkey = name_key(value_name)
        let vacc = access_tag(v.access)
        let id = root +
          "/distribution/" +
          dist_tag +
          "/def/modules/" +
          part(mkey) +
          "/" +
          macc +
          "/values/" +
          part(vkey) +
          "/" +
          vacc
        walk.definition(v.value.value, field(field(values, vkey), vacc), id, id)
        if dist_tag == "Library" {
          let decl = "value:" +
            package_name.to_canonical() +
            ":" +
            module_name.to_canonical() +
            "#" +
            value_name.to_canonical()
          let d = v.value.value
          walk.definition(
            d,
            @codec.write_definition(d),
            decl + "/definition",
            decl + "/definition",
          )
          if d is ExpressionBody(inputs, output, body) {
            walk.type_(
              output,
              @codec.write_type(output),
              decl + "/output",
              decl + "/output",
            )
            walk.value(
              body,
              @codec.write_value(body),
              decl + "/body",
              decl + "/body",
            )
            for input in inputs {
              let iid = decl + "/input/" + part(input.0.to_canonical())
              walk.type_(input.1, @codec.write_type(input.1), iid, iid)
            }
          }
        }
      }
    }
  }
  ids.map(id => {
    match walk.out.get(id) {
      Some(node) => node
      None =>
        {
          path: id,
          id,
          tag: "declaration",
          attribute: false,
          marker: false,
          leaf: None,
        }
    }
  })
}
