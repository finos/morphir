///|
pub fn read_module_definition(json : Json) -> @model.ModuleDefinition raise {
  @wire.fields(json, ["types", "values", "doc"])
  {
    types: @wire.read_map(optional_object(json, "types"), @wire.read_name, fn(
      item,
    ) raise {
      read_access(item, fn(item) raise {
        read_documented(item, read_type_definition)
      })
    }),
    values: @wire.read_map(optional_object(json, "values"), @wire.read_name, fn(
      item,
    ) raise {
      read_access(item, fn(item) raise {
        read_documented(item, read_definition)
      })
    }),
    doc: match @wire.optional(json, "doc") {
      None => None
      Some(doc) => Some(@wire.string(doc))
    },
  }
}

///|
pub fn write_module_definition(value : @model.ModuleDefinition) -> Json raise {
  let fields : Array[(String, Json)] = []
  fields.push(
    (
      "types",
      @wire.write_map(value.types, name_key, fn(item) raise {
        write_access(item, fn(item) raise {
          write_documented(item, write_type_definition)
        })
      }),
    ),
  )
  fields.push(
    (
      "values",
      @wire.write_map(value.values, name_key, fn(item) raise {
        write_access(item, fn(item) raise {
          write_documented(item, write_definition)
        })
      }),
    ),
  )
  if value.doc is Some(doc) {
    fields.push(("doc", @wire.text(doc)))
  }
  @wire.obj(fields)
}

///|
pub fn read_package_definition(json : Json) -> @model.PackageDefinition raise {
  @wire.fields(json, ["modules"])
  {
    modules: @wire.read_map(optional_object(json, "modules"), @wire.read_path, fn(
      item,
    ) raise {
      read_access(item, read_module_definition)
    }),
  }
}

///|
pub fn write_package_definition(value : @model.PackageDefinition) -> Json raise {
  @wire.obj([
    (
      "modules",
      @wire.write_map(value.modules, path_key, fn(item) raise {
        write_access(item, write_module_definition)
      }),
    ),
  ])
}

///|
pub fn read_module_specification(
  json : Json,
) -> @model.ModuleSpecification raise {
  @wire.fields(json, ["types", "values", "doc", "annotations"])
  {
    annotations: read_annotations(json, None),
    types: @wire.read_map(optional_object(json, "types"), @wire.read_name, fn(
      item,
    ) raise {
      read_documented(item, read_type_specification)
    }),
    values: @wire.read_map(optional_object(json, "values"), @wire.read_name, fn(
      item,
    ) raise {
      read_documented(item, read_value_specification)
    }),
    doc: match @wire.optional(json, "doc") {
      None => None
      Some(doc) => Some(@wire.string(doc))
    },
  }
}

///|
pub fn write_module_specification(
  value : @model.ModuleSpecification,
) -> Json raise {
  let fields : Array[(String, Json)] = []
  put_annotations(fields, value.annotations)
  fields.push(
    (
      "types",
      @wire.write_map(value.types, name_key, fn(item) raise {
        write_documented(item, write_type_specification)
      }),
    ),
  )
  fields.push(
    (
      "values",
      @wire.write_map(value.values, name_key, fn(item) raise {
        write_documented(item, write_value_specification)
      }),
    ),
  )
  if value.doc is Some(doc) {
    fields.push(("doc", @wire.text(doc)))
  }
  @wire.obj(fields)
}

///|
pub fn read_package_specification(
  json : Json,
) -> @model.PackageSpecification raise {
  @wire.fields(json, ["modules"])
  {
    modules: @wire.read_map(optional_object(json, "modules"), @wire.read_path, fn(
      item,
    ) raise {
      read_module_specification(item)
    }),
  }
}

///|
pub fn write_package_specification(
  value : @model.PackageSpecification,
) -> Json raise {
  @wire.obj([
    (
      "modules",
      @wire.write_map(value.modules, path_key, fn(item) raise {
        write_module_specification(item)
      }),
    ),
  ])
}

///|
fn read_entry_point(
  json : Json,
  context : @wire.DocumentNameContext?,
) -> @model.EntryPoint raise {
  @wire.fields(json, ["target", "kind", "doc"])
  let kind = match @wire.string(@wire.field(json, "kind")) {
    "main" => @model.Main
    "command" => @model.Command
    "handler" => @model.Handler
    "job" => @model.Job
    "policy" => @model.Policy
    other => raise @wire.Invalid("invalid_type", other)
  }
  {
    target: @wire.read_context_fqname(@wire.field(json, "target"), context),
    kind,
    doc: match @wire.optional(json, "doc") {
      None => None
      Some(doc) => Some(@wire.string(doc))
    },
  }
}

///|
fn write_entry_point(value : @model.EntryPoint) -> Json raise {
  let kind = match value.kind {
    Main => "main"
    Command => "command"
    Handler => "handler"
    Job => "job"
    Policy => "policy"
  }
  let fields = [
    ("target", @wire.write_fqname(value.target)),
    ("kind", @wire.text(kind)),
  ]
  if value.doc is Some(doc) {
    fields.push(("doc", @wire.text(doc)))
  }
  let json = @wire.obj(fields)
  ignore(read_entry_point(json, None))
  json
}

///|
fn string_key(value : String) -> Json raise {
  @wire.text(@wire.string(@wire.text(value)))
}

///|
fn read_string_key(value : Json) -> String raise {
  @wire.string(value)
}

///|
pub fn read_entry_points(
  json : Json,
  context~ : @wire.DocumentNameContext? = None,
) -> Map[String, @model.EntryPoint] raise {
  @wire.read_map(json, read_string_key, point => {
    read_entry_point(point, context)
  })
}

///|
pub fn read_distribution(json : Json) -> @model.Distribution raise {
  if !(json is Object(_)) {
    raise @wire.Invalid(
      "invalid_distribution_shape", "Expected v4 distribution object",
    )
  }
  let (tag, payload) = variant(json)
  let name = @wire.read_path(@wire.field(payload, "packageName"))
  match tag {
    "Library" => {
      @wire.fields(payload, ["packageName", "dependencies", "def"])
      @model.Library(
        name,
        @wire.read_map(
          optional_object(payload, "dependencies"),
          @wire.read_path,
          read_package_specification,
        ),
        read_package_definition(optional_object(payload, "def")),
      )
    }
    "Specs" => {
      @wire.fields(payload, ["packageName", "dependencies", "spec"])
      @model.Specs(
        name,
        @wire.read_map(
          optional_object(payload, "dependencies"),
          @wire.read_path,
          read_package_specification,
        ),
        read_package_specification(optional_object(payload, "spec")),
      )
    }
    "Application" => {
      @wire.fields(payload, [
        "packageName", "dependencies", "def", "entryPoints",
      ])
      @model.Application(
        name,
        @wire.read_map(
          optional_object(payload, "dependencies"),
          @wire.read_path,
          read_package_definition,
        ),
        read_package_definition(optional_object(payload, "def")),
        read_entry_points(@wire.field(payload, "entryPoints")),
      )
    }
    _ => raise @wire.Invalid("unknown_node", tag)
  }
}

///|
pub fn write_distribution(value : @model.Distribution) -> Json raise {
  match value {
    Library(name, dependencies, body) =>
      @wire.tag(
        "Library",
        @wire.obj([
          ("packageName", path_key(name)),
          (
            "dependencies",
            @wire.write_map(dependencies, path_key, write_package_specification),
          ),
          ("def", write_package_definition(body)),
        ]),
      )
    Specs(name, dependencies, body) =>
      @wire.tag(
        "Specs",
        @wire.obj([
          ("packageName", path_key(name)),
          (
            "dependencies",
            @wire.write_map(dependencies, path_key, write_package_specification),
          ),
          ("spec", write_package_specification(body)),
        ]),
      )
    Application(name, dependencies, body, entries) =>
      @wire.tag(
        "Application",
        @wire.obj([
          ("packageName", path_key(name)),
          (
            "dependencies",
            @wire.write_map(dependencies, path_key, write_package_definition),
          ),
          ("def", write_package_definition(body)),
          (
            "entryPoints",
            @wire.write_map(entries, string_key, write_entry_point),
          ),
        ]),
      )
  }
}

///|
pub fn from_json(json : Json) -> @model.IRFile raise {
  let format_version = @wire.read_version(@wire.field(json, "formatVersion"))
  format_version.check_family(4U)
  @wire.fields(json, ["formatVersion", "distribution"])
  @model.IRFile::new(
    read_distribution(@wire.field(json, "distribution")),
    format_version~,
  )
}

///|
pub fn to_json(file : @model.IRFile) -> Json raise {
  @wire.obj([
    ("formatVersion", @wire.write_version(file.format_version)),
    ("distribution", write_distribution(file.distribution)),
  ])
}

///|
pub fn read(text : String) -> @model.IRFile raise {
  from_json(@wire.parse(text))
}

///|
pub fn write(file : @model.IRFile) -> String raise {
  to_json(file).stringify()
}
