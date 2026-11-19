///|
fn pointer_value(document : Json, pointer : String) -> Json raise {
  if pointer == "" {
    return document
  }
  let parts = pointer.split("/").collect()
  let mut value = document
  for raw in parts[1:] {
    let token = StringBuilder()
    let mut i = 0
    while i < raw.length() {
      if raw[i] == '~' {
        require(i + 1 < raw.length(), "Invalid JSON pointer escape")
        match raw[i + 1] {
          '0' => token.write_char('~')
          '1' => token.write_char('/')
          _ => fail("Invalid JSON pointer escape")
        }
        i += 2
      } else {
        token.write_string(raw[i:i + 1].to_owned())
        i += 1
      }
    }
    let key = token.to_string()
    value = match value {
      Object(fields) =>
        fields.get(key).unwrap_or_else(() => fail("JSON pointer member absent"))
      Array(items) => {
        require(
          key != "" &&
          (key == "0" || !key.has_prefix("0")) &&
          key.iter().all(ch => ch >= '0' && ch <= '9'),
          "Invalid JSON pointer array index",
        )
        let index = @string.parse_int(key)
        require(index < items.length(), "JSON pointer index absent")
        items[index]
      }
      _ => fail("JSON pointer crosses a scalar")
    }
  }
  value
}

///|
fn observe(request : Request, files : Array[(String, Bytes)]) -> Json raise {
  require(
    files.all(file => file.0.has_suffix(request.extension)),
    "Files do not match selected codec",
  )
  let reader = @yaml.open_bounded_tree(
    captured_source(files, request.snapshot),
    encoding=request.encoding,
    limits={ ..@yaml.Limits::default(), max_bytes: request.document_limit, },
  )
  require(
    reader.format_version().to_release_string() == request.ir_version,
    "IR version mismatch",
  )
  let manifest = reader.observation()
  let modules : Array[Json] = []
  let mut selected : (@ir.Path, @ir.Path)? = None
  let artifacts : Map[String, @yaml.TreeArtifact] = Map([])
  artifacts["manifest"] = @yaml.ManifestArtifact
  let packages = [reader.package_name()] +
    reader.dependency_packages().collect()
  for package_name in packages {
    let mut cursor = None
    while true {
      let page = reader.modules(package_name, limit=request.page_size, cursor?)
      for module_info in page.items {
        if module_info.document == request.selection {
          require(selected is None, "Ambiguous module document selection")
          selected = Some((module_info.package_name, module_info.path))
        }
        artifacts[module_info.document] = @yaml.ModuleArtifact(
          package_name,
          module_info.path,
        )
        let fields = @wire.object(module_info.observation()).copy()
        let members : Array[Json] = []
        let mut cursor = None
        while true {
          let member_page = reader.members(
            package_name,
            module_info.path,
            limit=request.page_size,
            cursor?,
          )
          for entry in member_page.items {
            members.push(entry.observation())
            artifacts[entry.document] = @yaml.MemberArtifact(
              package_name,
              module_info.path,
              entry.kind,
              entry.name,
            )
            // Decode every listed member under the selected version/role.
            ignore(
              reader.read_member(
                package_name,
                module_info.path,
                entry.kind,
                entry.name,
              ),
            )
          }
          cursor = member_page.next
          if cursor is None {
            break
          }
        }
        fields["members"] = Json::array(members)
        modules.push(Json::object(fields))
      }
      cursor = page.next
      if cursor is None {
        break
      }
    }
  }
  guard selected is Some((selected_package, selected_module)) else {
    fail("Selection absent from admitted module inventory")
  }
  let pages : Array[Json] = []
  let mut cursor = None
  let mut final_member : @yaml.TreeMember? = None
  while true {
    let page = reader.members(
      selected_package,
      selected_module,
      limit=request.page_size,
      cursor?,
    )
    pages.push(Json::array(page.items.map(entry => @wire.text(entry.document))))
    for entry in page.items {
      final_member = Some(entry)
    }
    cursor = page.next
    if cursor is None {
      break
    }
  }
  guard final_member is Some(final_member) && final_member.kind is ValueMember else {
    fail("Selected final page has no value")
  }
  let body = reader.read_member(
    selected_package,
    selected_module,
    final_member.kind,
    final_member.name,
  )
  guard body.direct_value_reference() is Some(reference) else {
    fail("Final value has no direct typed reference")
  }
  let final_fact = reader.observe_member(
    selected_package,
    selected_module,
    final_member.kind,
    final_member.name,
  )
  let resolved = reader.observe_member(
    reference.package_name,
    reference.module_name,
    ValueMember,
    reference.local_name,
  )
  let attributes = request.attributes.map(item => {
    guard artifacts.get(item.document) is Some(artifact) else {
      fail("Attribute document absent from inventory")
    }
    let (_, expanded) = reader.read_expanded_document(
      artifact,
      max_output_bytes=request.document_limit,
    )
    let document = @wire.parse_bounded(
      expanded,
      max_depth=128,
      max_nodes=100000,
      max_string_units=65536,
    )
    @wire.obj([
      ("document", @wire.text(item.document)),
      ("pointer", @wire.text(item.pointer)),
      ("value", pointer_value(document, item.pointer)),
    ])
  })
  let fields = @wire.object(manifest).copy()
  fields["scope"] = @wire.text("native-reader")
  fields["revision"] = @wire.text(request.snapshot)
  fields["modules"] = Json::array(modules)
  fields["pages"] = Json::array(pages)
  fields["finalPageBody"] = @wire.obj([
    ("document", @wire.field(final_fact, "document")),
    ("outputType", @wire.field(final_fact, "outputType")),
    ("reference", @wire.text(reference.to_canonical())),
    ("referenceKind", @wire.text("value")),
    ("referencedIntegerLiteral", @wire.field(resolved, "integerLiteral")),
  ])
  fields["classicAttributes"] = Json::array(attributes)
  Json::object(fields)
}
