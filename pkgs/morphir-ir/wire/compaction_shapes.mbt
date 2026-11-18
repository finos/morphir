///|
priv enum CompactionTable {
  NameTable
  PackagePathTable
  ModulePathTable
  FQNameTable
}

///|
priv enum CompactionSpelling {
  CanonicalSpelling
  ClassicSpelling
}

///|
/// Describes typed slots in the original wire tree. The writer still emits
/// unmarked children, applying its ordinary JSON ordering to them.
priv struct CompactionShape {
  reference : (CompactionTable, CompactionSpelling)?
  keep_order : Bool
  verbatim : Bool
  member_shape : (Json, String, Json) -> CompactionShape?
  item_shape : (Json, Int32, Json) -> CompactionShape?
}

///|
type CompactionRule = (Json) -> CompactionShape

///|
fn compaction_plain_shape() -> CompactionShape {
  {
    reference: None,
    keep_order: false,
    verbatim: false,
    member_shape: (_, _, _) => None,
    item_shape: (_, _, _) => None,
  }
}

///|
fn compaction_slot(
  table : CompactionTable,
  spelling : CompactionSpelling,
) -> CompactionShape {
  { ..compaction_plain_shape(), reference: Some((table, spelling)), }
}

///|
fn canonical_name_shape(_json : Json) -> CompactionShape {
  compaction_slot(NameTable, CanonicalSpelling)
}

///|
fn package_path_shape(_json : Json) -> CompactionShape {
  compaction_slot(PackagePathTable, CanonicalSpelling)
}

///|
fn module_path_shape(_json : Json) -> CompactionShape {
  compaction_slot(ModulePathTable, CanonicalSpelling)
}

///|
fn canonical_fqname_shape(_json : Json) -> CompactionShape {
  compaction_slot(FQNameTable, CanonicalSpelling)
}

///|
fn classic_name_shape(_json : Json) -> CompactionShape {
  compaction_slot(NameTable, ClassicSpelling)
}

///|
fn classic_package_shape(_json : Json) -> CompactionShape {
  compaction_slot(PackagePathTable, ClassicSpelling)
}

///|
fn classic_module_shape(_json : Json) -> CompactionShape {
  compaction_slot(ModulePathTable, ClassicSpelling)
}

///|
fn classic_fqname_shape(_json : Json) -> CompactionShape {
  compaction_slot(FQNameTable, ClassicSpelling)
}

///|
fn compaction_members(
  rules : Array[(String, CompactionRule)],
) -> CompactionShape {
  {
    ..compaction_plain_shape(),
    member_shape: (_, key, child) => {
      for rule in rules {
        if key == rule.0 {
          return Some((rule.1)(child))
        }
      }
      None
    },
  }
}

///|
fn compaction_items(rules : Array[(Int32, CompactionRule)]) -> CompactionShape {
  {
    ..compaction_plain_shape(),
    item_shape: (_, index, child) => {
      for rule in rules {
        if index == rule.0 {
          return Some((rule.1)(child))
        }
      }
      None
    },
  }
}

///|
fn compaction_list(item : CompactionRule) -> CompactionShape {
  {
    ..compaction_plain_shape(),
    item_shape: (_, _, child) => Some(item(child)),
  }
}

///|
/// Map member names stay expanded. A classic pair's first element has its own
/// wire schema, so only schemas that type it as a name supply a key rule.
fn compaction_map(
  value : CompactionRule,
  pair_key~ : Array[(Int32, CompactionRule)] = [],
  keep_order~ : Bool = false,
) -> CompactionShape {
  {
    ..compaction_plain_shape(),
    keep_order,
    member_shape: (_, _, child) => Some(value(child)),
    item_shape: (_, _, _) => Some(compaction_items(pair_key + [(1, value)])),
  }
}

///|
fn compaction_has(json : Json, key : String) -> Bool {
  json is Object(fields) && fields.contains(key)
}

///|
fn compaction_classic_tag(json : Json) -> String {
  match json {
    Array([String(tag), ..]) => tag
    _ => ""
  }
}

///|
fn v3_compaction_documented(
  json : Json,
  payload : CompactionRule,
) -> CompactionShape {
  if compaction_has(json, "doc") && compaction_has(json, "value") {
    compaction_members([("value", payload)])
  } else {
    payload(json)
  }
}

///|
fn v3_compaction_definition(
  _json : Json,
  payload : CompactionRule,
) -> CompactionShape {
  compaction_members([("value", doc => v3_compaction_documented(doc, payload))])
}

///|
fn v3_compaction_type(json : Json) -> CompactionShape {
  let fields = fn(_) {
    compaction_list(_ => {
      compaction_members([
        ("name", classic_name_shape),
        ("tpe", v3_compaction_type),
      ])
    })
  }
  match compaction_classic_tag(json) {
    "Variable" => compaction_items([(2, classic_name_shape)])
    "Reference" =>
      compaction_items([
        (2, classic_fqname_shape),
        (3, _ => compaction_list(v3_compaction_type)),
      ])
    "Tuple" => compaction_items([(2, _ => compaction_list(v3_compaction_type))])
    "Record" => compaction_items([(2, fields)])
    "ExtensibleRecord" =>
      compaction_items([(2, classic_name_shape), (3, fields)])
    "Function" =>
      compaction_items([(2, v3_compaction_type), (3, v3_compaction_type)])
    _ => compaction_plain_shape()
  }
}

///|
fn v3_compaction_pattern(json : Json) -> CompactionShape {
  let positions : Array[(Int32, CompactionRule)] = match
    compaction_classic_tag(json) {
    "AsPattern" => [(2, v3_compaction_pattern), (3, classic_name_shape)]
    "TuplePattern" => [(2, _ => compaction_list(v3_compaction_pattern))]
    "ConstructorPattern" =>
      [
        (2, classic_fqname_shape),
        (3, _ => compaction_list(v3_compaction_pattern)),
      ]
    "HeadTailPattern" =>
      [(2, v3_compaction_pattern), (3, v3_compaction_pattern)]
    _ => []
  }
  // Classic value and pattern attributes may themselves carry an inferred type.
  compaction_items([(1, v3_compaction_type)] + positions)
}

///|
fn v3_compaction_value(json : Json) -> CompactionShape {
  let values = fn(_) { compaction_list(v3_compaction_value) }
  let entries = fn(_) {
    compaction_map(v3_compaction_value, pair_key=[(0, classic_name_shape)])
  }
  let positions : Array[(Int32, CompactionRule)] = match
    compaction_classic_tag(json) {
    "Constructor" | "Reference" => [(2, classic_fqname_shape)]
    "Tuple" | "List" => [(2, values)]
    "Record" => [(2, entries)]
    "Variable" | "FieldFunction" => [(2, classic_name_shape)]
    "Field" => [(2, v3_compaction_value), (3, classic_name_shape)]
    "Apply" => [(2, v3_compaction_value), (3, v3_compaction_value)]
    "Lambda" => [(2, v3_compaction_pattern), (3, v3_compaction_value)]
    "LetDefinition" =>
      [
        (2, classic_name_shape),
        (3, v3_compaction_value_definition),
        (4, v3_compaction_value),
      ]
    "LetRecursion" =>
      [
        (
          2,
          _ => {
            compaction_map(v3_compaction_value_definition, pair_key=[
              (0, classic_name_shape),
            ])
          },
        ),
        (3, v3_compaction_value),
      ]
    "Destructure" =>
      [
        (2, v3_compaction_pattern),
        (3, v3_compaction_value),
        (4, v3_compaction_value),
      ]
    "IfThenElse" =>
      [
        (2, v3_compaction_value),
        (3, v3_compaction_value),
        (4, v3_compaction_value),
      ]
    "PatternMatch" =>
      [
        (2, v3_compaction_value),
        (
          3,
          _ => {
            compaction_list(_ => {
              compaction_items([
                (0, v3_compaction_pattern),
                (1, v3_compaction_value),
              ])
            })
          },
        ),
      ]
    "UpdateRecord" => [(2, v3_compaction_value), (3, entries)]
    _ => []
  }
  compaction_items([(1, v3_compaction_type)] + positions)
}

///|
fn v3_compaction_value_definition(_json : Json) -> CompactionShape {
  compaction_members([
    (
      "inputTypes",
      _ => {
        compaction_list(_ => {
          compaction_items([
            (0, classic_name_shape),
            (1, v3_compaction_type),
            (2, v3_compaction_type),
          ])
        })
      },
    ),
    ("outputType", v3_compaction_type),
    ("body", v3_compaction_value),
  ])
}

///|
fn v3_compaction_value_specification(_json : Json) -> CompactionShape {
  compaction_members([
    (
      "inputs",
      _ => {
        compaction_list(_ => {
          compaction_items([(0, classic_name_shape), (1, v3_compaction_type)])
        })
      },
    ),
    ("output", v3_compaction_type),
  ])
}

///|
fn v3_compaction_constructors(_json : Json) -> CompactionShape {
  compaction_map(
    _ => {
      compaction_list(_ => {
        compaction_items([(0, classic_name_shape), (1, v3_compaction_type)])
      })
    },
    pair_key=[(0, classic_name_shape)],
  )
}

///|
fn v3_compaction_type_entry(json : Json) -> CompactionShape {
  let positions : Array[(Int32, CompactionRule)] = match
    compaction_classic_tag(json) {
    "TypeAliasDefinition" | "TypeAliasSpecification" =>
      [(2, v3_compaction_type)]
    "CustomTypeDefinition" =>
      [(2, _ => compaction_members([("value", v3_compaction_constructors)]))]
    "CustomTypeSpecification" => [(2, v3_compaction_constructors)]
    "DerivedTypeSpecification" =>
      [
        (
          2,
          _ => {
            compaction_members([
              ("baseType", v3_compaction_type),
              ("fromBaseType", classic_fqname_shape),
              ("toBaseType", classic_fqname_shape),
            ])
          },
        ),
      ]
    "OpaqueTypeSpecification" => []
    _ => return compaction_plain_shape()
  }
  compaction_items([(1, _ => compaction_list(classic_name_shape))] + positions)
}

///|
fn v3_compaction_module(definition : Bool) -> CompactionShape {
  let entry = fn(body : CompactionRule) {
    compaction_map(
      json => {
        if definition {
          v3_compaction_definition(json, body)
        } else {
          v3_compaction_documented(json, body)
        }
      },
      pair_key=[(0, classic_name_shape)],
    )
  }
  compaction_members([
    ("types", _ => entry(v3_compaction_type_entry)),
    (
      "values",
      _ => {
        if definition {
          entry(v3_compaction_value_definition)
        } else {
          entry(v3_compaction_value_specification)
        }
      },
    ),
  ])
}

///|
fn v3_compaction_package(definition : Bool) -> CompactionShape {
  compaction_members([
    (
      "modules",
      _ => {
        compaction_map(
          _ => {
            if definition {
              compaction_members([("value", _ => v3_compaction_module(true))])
            } else {
              v3_compaction_module(false)
            }
          },
          pair_key=[(0, classic_module_shape)],
        )
      },
    ),
  ])
}

///|
fn v3_compaction_distribution(json : Json) -> CompactionShape {
  let definition = match compaction_classic_tag(json) {
    "Library" => true
    "Specs" => false
    _ => return compaction_plain_shape()
  }
  compaction_items([
    (1, classic_package_shape),
    (
      2,
      _ => {
        compaction_map(_ => v3_compaction_package(false), pair_key=[
          (0, classic_package_shape),
        ])
      },
    ),
    (3, _ => v3_compaction_package(definition)),
  ])
}

///|
fn v4_compaction_variant_tag(json : Json, tag : String) -> CompactionShape {
  if compaction_has(json, tag) {
    compaction_members([
      ("attributes", v4_compaction_value_attributes),
      ("attrs", v4_compaction_value_attributes),
    ])
  } else {
    compaction_plain_shape()
  }
}

///|
fn v4_compaction_type(json : Json) -> CompactionShape {
  match json {
    Object(fields) if fields.contains("$name") => canonical_fqname_shape(json)
    String(spelling) =>
      // The Type grammar permits a bare FQName and draft.1 explicitly admits
      // that branch. The bare type-variable branch stays expanded.
      try {
        ignore(@common.FQName::parse(spelling))
        canonical_fqname_shape(json)
      } catch {
        _ => compaction_plain_shape()
      }
    Array(_) => compaction_list(v4_compaction_type)
    _ =>
      compaction_members([
        (
          "Variable",
          child => {
            v4_compaction_name_payload(
              child, "name", canonical_name_shape, false,
            )
          },
        ),
        ("Reference", v4_compaction_type_reference),
        (
          "Union",
          child => {
            v4_compaction_array_payload(
              child, "alternatives", v4_compaction_type, false,
            )
          },
        ),
        (
          "Tuple",
          child => {
            v4_compaction_array_payload(
              child, "elements", v4_compaction_type, false,
            )
          },
        ),
        (
          "Record",
          child => v4_compaction_record(child, v4_compaction_type, false),
        ),
        (
          "ExtensibleRecord",
          _ => {
            compaction_members([
              ("variable", canonical_name_shape),
              ("fields", _ => compaction_map(v4_compaction_type)),
            ])
          },
        ),
        (
          "Function",
          _ => {
            compaction_members([
              ("parameterType", v4_compaction_type),
              ("argumentType", v4_compaction_type),
              ("arg", v4_compaction_type),
              ("returnType", v4_compaction_type),
              ("result", v4_compaction_type),
            ])
          },
        ),
      ])
  }
}

///|
fn v4_compaction_type_reference(json : Json) -> CompactionShape {
  match json {
    Object(fields) if fields.contains("$name") => canonical_fqname_shape(json)
    String(_) => canonical_fqname_shape(json)
    Array(_) =>
      {
        ..compaction_plain_shape(),
        item_shape: (_, index, child) => {
          Some(
            if index == 0 {
              canonical_fqname_shape(child)
            } else {
              v4_compaction_type(child)
            },
          )
        },
      }
    _ =>
      compaction_members([
        ("fqname", canonical_fqname_shape),
        ("args", _ => compaction_list(v4_compaction_type)),
      ])
  }
}

///|
fn v4_compaction_value_attributes(_json : Json) -> CompactionShape {
  compaction_members([("inferredType", v4_compaction_type)])
}

///|
/// Only expression and pattern nodes have ValueAttributes. Type attributes
/// carry opaque data, so a field named inferredType inside them is ordinary JSON.
fn v4_compaction_value_members(
  rules : Array[(String, CompactionRule)],
) -> CompactionShape {
  compaction_members(
    [
      ("attributes", v4_compaction_value_attributes),
      ("attrs", v4_compaction_value_attributes),
    ] +
    rules,
  )
}

///|
fn v4_compaction_name_payload(
  json : Json,
  field : String,
  name : CompactionRule,
  value_attributes : Bool,
) -> CompactionShape {
  match json {
    String(_) | Array(_) => name(json)
    Object(fields) if fields.contains("$name") => name(json)
    _ =>
      if value_attributes {
        v4_compaction_value_members([(field, name)])
      } else {
        compaction_members([(field, name)])
      }
  }
}

///|
fn v4_compaction_array_payload(
  json : Json,
  field : String,
  item : CompactionRule,
  value_attributes : Bool,
) -> CompactionShape {
  if json is Array(_) {
    compaction_list(item)
  } else {
    let rules = [(field, _ => compaction_list(item))]
    if value_attributes {
      v4_compaction_value_members(rules)
    } else {
      compaction_members(rules)
    }
  }
}

///|
fn v4_compaction_record(
  json : Json,
  field_value : CompactionRule,
  value_attributes : Bool,
) -> CompactionShape {
  if compaction_has(json, "fields") {
    let rules = [("fields", _ => compaction_map(field_value))]
    if value_attributes {
      v4_compaction_value_members(rules)
    } else {
      compaction_members(rules)
    }
  } else {
    compaction_map(field_value)
  }
}

///|
fn v4_compaction_pattern(json : Json) -> CompactionShape {
  if json is Array(_) {
    return compaction_list(v4_compaction_pattern)
  }
  let patterns = fn(_) { compaction_list(v4_compaction_pattern) }
  compaction_members([
    ("WildcardPattern", _ => v4_compaction_value_members([])),
    (
      "AsPattern",
      _ => {
        v4_compaction_value_members([
          ("pattern", v4_compaction_pattern),
          ("name", canonical_name_shape),
        ])
      },
    ),
    (
      "TuplePattern",
      child => {
        v4_compaction_array_payload(
          child, "patterns", v4_compaction_pattern, true,
        )
      },
    ),
    (
      "ConstructorPattern",
      _ => {
        v4_compaction_value_members([
          ("fqname", canonical_fqname_shape),
          ("patterns", patterns),
        ])
      },
    ),
    ("EmptyListPattern", _ => v4_compaction_value_members([])),
    (
      "HeadTailPattern",
      _ => {
        v4_compaction_value_members([
          ("head", v4_compaction_pattern),
          ("tail", v4_compaction_pattern),
        ])
      },
    ),
    ("LiteralPattern", child => v4_compaction_variant_tag(child, "literal")),
    ("UnitPattern", _ => v4_compaction_value_members([])),
  ])
}

///|
fn v4_compaction_literal(_json : Json) -> CompactionShape {
  compaction_members([
    ("DocumentLiteral", _ => { ..compaction_plain_shape(), verbatim: true, }),
  ])
}

///|
fn v4_compaction_literal_value(json : Json) -> CompactionShape {
  if compaction_has(json, "literal") {
    v4_compaction_value_members([("literal", v4_compaction_literal)])
  } else {
    v4_compaction_literal(json)
  }
}

///|
fn v4_compaction_reason(_json : Json) -> CompactionShape {
  compaction_members([
    (
      "UnresolvedReference",
      _ => compaction_members([("target", canonical_fqname_shape)]),
    ),
  ])
}

///|
fn v4_compaction_incompleteness(_json : Json) -> CompactionShape {
  compaction_members([
    (
      "Hole",
      _ => {
        compaction_members([
          ("reason", v4_compaction_reason),
          ("partialBody", v4_compaction_type),
        ])
      },
    ),
  ])
}

///|
fn v4_compaction_value(json : Json) -> CompactionShape {
  if json is Array(_) {
    return compaction_list(v4_compaction_value)
  }
  compaction_members([
    ("Literal", v4_compaction_literal_value),
    (
      "Constructor",
      child => {
        v4_compaction_name_payload(
          child, "fqname", canonical_fqname_shape, true,
        )
      },
    ),
    (
      "Reference",
      child => {
        v4_compaction_name_payload(
          child, "fqname", canonical_fqname_shape, true,
        )
      },
    ),
    (
      "Variable",
      child => {
        v4_compaction_name_payload(child, "name", canonical_name_shape, true)
      },
    ),
    (
      "FieldFunction",
      child => {
        v4_compaction_name_payload(child, "name", canonical_name_shape, true)
      },
    ),
    (
      "Tuple",
      child => {
        v4_compaction_array_payload(
          child, "elements", v4_compaction_value, true,
        )
      },
    ),
    (
      "List",
      child => {
        v4_compaction_array_payload(child, "items", v4_compaction_value, true)
      },
    ),
    ("Record", child => v4_compaction_record(child, v4_compaction_value, true)),
    (
      "Field",
      _ => {
        v4_compaction_value_members([
          ("target", v4_compaction_value),
          ("subject", v4_compaction_value),
          ("name", canonical_name_shape),
          ("fieldName", canonical_name_shape),
        ])
      },
    ),
    (
      "Apply",
      _ => {
        v4_compaction_value_members([
          ("function", v4_compaction_value),
          ("argument", v4_compaction_value),
        ])
      },
    ),
    (
      "Lambda",
      _ => {
        v4_compaction_value_members([
          ("pattern", v4_compaction_pattern),
          ("body", v4_compaction_value),
        ])
      },
    ),
    (
      "LetDefinition",
      _ => {
        v4_compaction_value_members([
          ("name", canonical_name_shape),
          ("valueName", canonical_name_shape),
          ("definition", v4_compaction_value_definition),
          ("valueDefinition", v4_compaction_value_definition),
          ("in", v4_compaction_value),
          ("inValue", v4_compaction_value),
        ])
      },
    ),
    (
      "LetRecursion",
      _ => {
        v4_compaction_value_members([
          ("definitions", _ => compaction_map(v4_compaction_value_definition)),
          ("in", v4_compaction_value),
          ("inValue", v4_compaction_value),
        ])
      },
    ),
    (
      "Destructure",
      _ => {
        v4_compaction_value_members([
          ("pattern", v4_compaction_pattern),
          ("value", v4_compaction_value),
          ("valueToDestruct", v4_compaction_value),
          ("in", v4_compaction_value),
          ("inValue", v4_compaction_value),
        ])
      },
    ),
    (
      "IfThenElse",
      _ => {
        v4_compaction_value_members([
          ("condition", v4_compaction_value),
          ("then", v4_compaction_value),
          ("else", v4_compaction_value),
          ("thenBranch", v4_compaction_value),
          ("elseBranch", v4_compaction_value),
        ])
      },
    ),
    (
      "PatternMatch",
      _ => {
        v4_compaction_value_members([
          ("value", v4_compaction_value),
          ("branchOutOn", v4_compaction_value),
          (
            "cases",
            _ => {
              compaction_list(_ => {
                compaction_members([
                  ("pattern", v4_compaction_pattern),
                  ("body", v4_compaction_value),
                ])
              })
            },
          ),
        ])
      },
    ),
    (
      "UpdateRecord",
      _ => {
        v4_compaction_value_members([
          ("target", v4_compaction_value),
          ("subject", v4_compaction_value),
          ("fields", _ => compaction_map(v4_compaction_value)),
          ("fieldsToUpdate", _ => compaction_map(v4_compaction_value)),
        ])
      },
    ),
    ("Unit", _ => v4_compaction_value_members([])),
    (
      "Hole",
      _ => {
        v4_compaction_value_members([
          ("reason", v4_compaction_reason),
          ("expectedType", v4_compaction_type),
        ])
      },
    ),
  ])
}

///|
fn v4_compaction_inputs(_json : Json) -> CompactionShape {
  compaction_map(
    v4_compaction_type,
    pair_key=[(0, canonical_name_shape)],
    keep_order=true,
  )
}

///|
fn v4_compaction_value_definition(_json : Json) -> CompactionShape {
  compaction_members([
    (
      "ExpressionBody",
      _ => {
        compaction_members([
          ("inputTypes", v4_compaction_inputs),
          ("outputType", v4_compaction_type),
          ("body", v4_compaction_value),
        ])
      },
    ),
    (
      "NativeBody",
      _ => {
        compaction_members([
          ("inputTypes", v4_compaction_inputs),
          ("outputType", v4_compaction_type),
        ])
      },
    ),
    (
      "ExternalBody",
      _ => {
        compaction_members([
          ("inputTypes", v4_compaction_inputs),
          ("outputType", v4_compaction_type),
          ("body", v4_compaction_value),
        ])
      },
    ),
    (
      "IncompleteBody",
      _ => {
        compaction_members([
          ("inputTypes", v4_compaction_inputs),
          ("outputType", v4_compaction_type),
          ("incompleteness", v4_compaction_incompleteness),
          ("partialBody", v4_compaction_value),
        ])
      },
    ),
  ])
}

///|
fn v4_compaction_annotation_argument(json : Json) -> CompactionShape {
  if compaction_has(json, "name") && compaction_has(json, "value") {
    compaction_members([
      ("name", canonical_name_shape),
      ("value", v4_compaction_value),
    ])
  } else {
    v4_compaction_value(json)
  }
}

///|
fn v4_compaction_annotations(_json : Json) -> CompactionShape {
  compaction_list(_ => {
    compaction_members([
      ("name", canonical_fqname_shape),
      ("arguments", _ => compaction_list(v4_compaction_annotation_argument)),
    ])
  })
}

///|
fn v4_compaction_value_specification(_json : Json) -> CompactionShape {
  compaction_members([
    ("inputs", v4_compaction_inputs),
    ("output", v4_compaction_type),
    ("annotations", v4_compaction_annotations),
  ])
}

///|
fn v4_compaction_constructors(_json : Json) -> CompactionShape {
  compaction_map(
    _ => {
      compaction_map(v4_compaction_type, pair_key=[(0, canonical_name_shape)])
    },
    pair_key=[(0, canonical_name_shape)],
  )
}

///|
fn v4_compaction_derived_type(_json : Json) -> CompactionShape {
  compaction_members([
    ("annotations", v4_compaction_annotations),
    ("typeParams", _ => compaction_list(canonical_name_shape)),
    ("baseType", v4_compaction_type),
    ("fromBaseType", canonical_fqname_shape),
    ("toBaseType", canonical_fqname_shape),
  ])
}

///|
fn v4_compaction_type_entry(json : Json) -> CompactionShape {
  if json is Array(_) {
    let body : Array[(Int32, CompactionRule)] = match
      compaction_classic_tag(json) {
      "TypeAliasSpecification" => [(2, v4_compaction_type)]
      "CustomTypeSpecification" => [(2, v4_compaction_constructors)]
      "DerivedTypeSpecification" => [(2, v4_compaction_derived_type)]
      "OpaqueTypeSpecification" => []
      _ => return compaction_plain_shape()
    }
    return compaction_items(
      [(1, _ => compaction_list(canonical_name_shape))] + body,
    )
  }
  let params : Array[(String, CompactionRule)] = [
    ("typeParams", _ => compaction_list(canonical_name_shape)),
  ]
  let spec = params + [("annotations", v4_compaction_annotations)]
  compaction_members([
    (
      "TypeAliasDefinition",
      _ => compaction_members(params + [("typeExp", v4_compaction_type)]),
    ),
    (
      "CustomTypeDefinition",
      _ => {
        compaction_members(
          params + [("constructors", v4_compaction_constructors)],
        )
      },
    ),
    (
      "IncompleteTypeDefinition",
      _ => {
        compaction_members(
          params +
          [
            ("partialTypeExp", v4_compaction_type),
            ("incompleteness", v4_compaction_incompleteness),
          ],
        )
      },
    ),
    (
      "TypeAliasSpecification",
      _ => compaction_members(spec + [("typeExp", v4_compaction_type)]),
    ),
    (
      "CustomTypeSpecification",
      _ => {
        compaction_members(
          spec + [("constructors", v4_compaction_constructors)],
        )
      },
    ),
    ("OpaqueTypeSpecification", _ => compaction_members(spec)),
    ("DerivedTypeSpecification", v4_compaction_derived_type),
  ])
}

///|
fn v4_compaction_documented(
  json : Json,
  payload : CompactionRule,
) -> CompactionShape {
  if compaction_has(json, "value") {
    compaction_members([("value", payload)])
  } else {
    payload(json)
  }
}

///|
fn v4_compaction_access(
  json : Json,
  payload : CompactionRule,
) -> CompactionShape {
  if compaction_has(json, "access") {
    if compaction_has(json, "value") {
      compaction_members([("value", payload)])
    } else {
      payload(json)
    }
  } else {
    compaction_members([
      ("Public", payload),
      ("public", payload),
      ("pub", payload),
      ("Private", payload),
      ("private", payload),
    ])
  }
}

///|
fn v4_compaction_entry(
  json : Json,
  payload : CompactionRule,
  definition : Bool,
) -> CompactionShape {
  let documented = fn(child) { v4_compaction_documented(child, payload) }
  if definition {
    v4_compaction_access(json, documented)
  } else {
    documented(json)
  }
}

///|
fn v4_compaction_module(definition : Bool) -> CompactionShape {
  let types = fn(child) {
    v4_compaction_entry(child, v4_compaction_type_entry, definition)
  }
  let values = fn(child) {
    let payload = if definition {
      v4_compaction_value_definition
    } else {
      v4_compaction_value_specification
    }
    v4_compaction_entry(child, payload, definition)
  }
  let rules : Array[(String, CompactionRule)] = [
    ("types", _ => compaction_map(types)),
    ("values", _ => compaction_map(values)),
  ]
  if definition {
    compaction_members(rules)
  } else {
    compaction_members(rules + [("annotations", v4_compaction_annotations)])
  }
}

///|
fn v4_compaction_package(definition : Bool) -> CompactionShape {
  compaction_members([
    (
      "modules",
      _ => {
        compaction_map(child => {
          if definition {
            v4_compaction_access(child, _ => v4_compaction_module(true))
          } else {
            v4_compaction_module(false)
          }
        })
      },
    ),
  ])
}

///|
fn v4_compaction_entry_points(_json : Json) -> CompactionShape {
  compaction_map(_ => compaction_members([("target", canonical_fqname_shape)]))
}

///|
fn v4_compaction_distribution(_json : Json) -> CompactionShape {
  compaction_members([
    (
      "Library",
      _ => {
        compaction_members([
          ("packageName", package_path_shape),
          ("def", _ => v4_compaction_package(true)),
          (
            "dependencies",
            _ => compaction_map(_ => v4_compaction_package(false)),
          ),
        ])
      },
    ),
    (
      "Specs",
      _ => {
        compaction_members([
          ("packageName", package_path_shape),
          ("spec", _ => v4_compaction_package(false)),
          (
            "dependencies",
            _ => compaction_map(_ => v4_compaction_package(false)),
          ),
        ])
      },
    ),
    (
      "Application",
      _ => {
        compaction_members([
          ("packageName", package_path_shape),
          ("def", _ => v4_compaction_package(true)),
          (
            "dependencies",
            _ => compaction_map(_ => v4_compaction_package(true)),
          ),
          ("entryPoints", v4_compaction_entry_points),
        ])
      },
    ),
  ])
}

///|
fn v3_compaction_tree_body(json : Json, definition : Bool) -> CompactionShape {
  if json is Array(_) {
    v3_compaction_type_entry(json)
  } else if definition {
    v3_compaction_value_definition(json)
  } else {
    v3_compaction_value_specification(json)
  }
}

///|
fn v3_compaction_tree_entry(json : Json, definition : Bool) -> CompactionShape {
  let body = fn(child) { v3_compaction_tree_body(child, definition) }
  if definition {
    v3_compaction_definition(json, body)
  } else {
    v3_compaction_documented(json, body)
  }
}

///|
fn v4_compaction_tree_body(json : Json, definition : Bool) -> CompactionShape {
  if definition {
    if compaction_has(json, "ExpressionBody") ||
      compaction_has(json, "NativeBody") ||
      compaction_has(json, "ExternalBody") ||
      compaction_has(json, "IncompleteBody") {
      return v4_compaction_value_definition(json)
    }
  } else if compaction_has(json, "output") {
    return v4_compaction_value_specification(json)
  }
  v4_compaction_type_entry(json)
}

///|
fn v4_compaction_tree_entry(json : Json, definition : Bool) -> CompactionShape {
  v4_compaction_entry(
    json,
    child => v4_compaction_tree_body(child, definition),
    definition,
  )
}

///|
fn compaction_tree_listing(
  json : Json,
  definition : CompactionRule,
  specification : CompactionRule,
) -> CompactionShape {
  match json {
    Array(_) => compaction_list(canonical_name_shape)
    _ =>
      compaction_map(child => {
        // A standalone module file lacks its distribution role. The access
        // wrapper distinguishes inline definitions from specifications.
        if compaction_has(child, "access") ||
          compaction_has(child, "Public") ||
          compaction_has(child, "Private") ||
          compaction_has(child, "public") ||
          compaction_has(child, "private") ||
          compaction_has(child, "pub") {
          definition(child)
        } else {
          specification(child)
        }
      })
  }
}

///|
fn compaction_tree_manifest(v3 : Bool) -> CompactionShape {
  let rules : Array[(String, CompactionRule)] = [
    ("package", package_path_shape),
    ("dependencies", _ => compaction_list(package_path_shape)),
  ]
  if v3 {
    compaction_members(rules)
  } else {
    compaction_members(rules + [("entryPoints", v4_compaction_entry_points)])
  }
}

///|
fn compaction_tree_module(v3 : Bool) -> CompactionShape {
  let listing = if v3 {
    fn(json) {
      compaction_tree_listing(
        json,
        child => v3_compaction_tree_entry(child, true),
        child => v3_compaction_tree_entry(child, false),
      )
    }
  } else {
    fn(json) {
      compaction_tree_listing(
        json,
        child => v4_compaction_tree_entry(child, true),
        child => v4_compaction_tree_entry(child, false),
      )
    }
  }
  let rules = [
    ("path", module_path_shape),
    ("types", listing),
    ("values", listing),
  ]
  if v3 {
    compaction_members(rules)
  } else {
    compaction_members(rules + [("module", module_path_shape)])
  }
}

///|
fn compaction_tree_node(v3 : Bool) -> CompactionShape {
  if v3 {
    compaction_members([
      ("name", canonical_name_shape),
      ("def", child => v3_compaction_tree_entry(child, true)),
      ("spec", child => v3_compaction_tree_entry(child, false)),
    ])
  } else {
    compaction_members([
      ("name", canonical_name_shape),
      ("def", child => v4_compaction_tree_entry(child, true)),
      ("spec", child => v4_compaction_tree_entry(child, false)),
    ])
  }
}

///|
/// Choose the grammar of an already version-admitted ordinary document. Tree
/// node bodies have distinct type and value discriminants in both versions.
fn compaction_root_shape(document : Json, v3 : Bool) -> CompactionShape {
  guard document is Object(fields) else { return compaction_plain_shape() }
  match fields.get("distribution") {
    Some(String(_)) => compaction_tree_manifest(v3)
    Some(_) =>
      compaction_members([
        (
          "distribution",
          if v3 {
            v3_compaction_distribution
          } else {
            v4_compaction_distribution
          },
        ),
      ])
    None =>
      if fields.contains("path") || (!v3 && fields.contains("module")) {
        compaction_tree_module(v3)
      } else if fields.contains("name") {
        compaction_tree_node(v3)
      } else {
        compaction_plain_shape()
      }
  }
}
