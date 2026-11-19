///|
fn json_pointer(value : Json, pointer : String) -> Json raise {
  let mut selected = value
  let tokens = pointer.split("/").collect()
  for token in tokens[1:] {
    let key = token
      .to_owned()
      .replace_all(old="~1", new="/")
      .replace_all(old="~0", new="~")
    selected = match selected {
      Object(fields) =>
        fields
        .get(key)
        .unwrap_or_else(() => {
          abort("missing pointer token " + key + " in " + selected.stringify())
        })
      Array(items) => items[@string.parse_int(key)]
      _ => fail("pointer crosses scalar")
    }
  }
  selected
}

///|
fn check_observation_profile(index : Int32) -> Unit raise {
  let (profile, files, encoding) = observation_profiles()[index]
  let expected = observation_expected()
  let source = recording_tree(files)
  let reader = @yaml.open_bounded_tree(source.source(), encoding~, limits={
    ..@yaml.Limits::default(),
    max_bytes: 2048,
  })
  let manifest = reader.observation()
  for field in ["distribution", "package", "pathBudget", "dependencies"] {
    assert_eq(@wire.field(manifest, field), @wire.field(expected, field))
  }
  let all_modules : Array[Json] = []
  let all_pages : Array[Json] = []
  let packages = [reader.package_name()] +
    reader.dependency_packages().collect()
  // Walk actual module pages, reusing only the reader's opaque continuation.
  for package_name in packages {
    let mut cursor = None
    while true {
      let page = reader.modules(package_name, limit=1, cursor?)
      assert_true(page.items.length() <= 1)
      for entry in page.items {
        all_modules.push(entry.observation())
      }
      cursor = page.next
      if cursor is None {
        break
      }
    }
  }
  let expected_modules = @wire.array(@wire.field(expected, "modules"))
  assert_eq(
    all_modules,
    expected_modules.map(entry => {
      let metadata = @wire.object(entry).copy()
      ignore(metadata.remove("members"))
      Json::object(metadata)
    }),
  )
  for expected_module in expected_modules {
    let package_name = @ir.Path::parse(
      @wire.string(@wire.field(expected_module, "package")),
    )
    let module_name = @ir.Path::parse(
      @wire.string(@wire.field(expected_module, "path")),
    )
    let expected_members = @wire.array(@wire.field(expected_module, "members"))
    let observed_members : Array[Json] = []
    let mut cursor = None
    while true {
      let page = reader.members(package_name, module_name, limit=2, cursor?)
      assert_true(page.items.length() <= 2)
      let documents = page.items.map(item => @wire.text(item.document))
      if module_name.to_canonical() == "domain" {
        all_pages.push(Json::array(documents))
      }
      for entry in page.items {
        observed_members.push(entry.observation())
      }
      cursor = page.next
      if cursor is None {
        break
      }
    }
    assert_eq(observed_members, expected_members)
  }
  // Inventory must not preload any type or value body.
  assert_false(
    source.opens.any(path => path.contains(".value.") || path.contains(".type.")),
  )
  assert_eq(
    all_pages,
    @wire.array(json_pointer(expected, "/domainInventory/pages")),
  )
  let own = reader.package_name()
  let domain = @ir.Path::parse("domain")
  let final_member = reader.members(own, domain, limit=2)
  let final_member = reader.members(
      own,
      domain,
      limit=2,
      cursor=final_member.next.unwrap(),
    ).items[0]
  let final_body = reader.read_member(
    own,
    domain,
    final_member.kind,
    final_member.name,
  )
  // Resolve via the decoded FQName's package/module/local-name and value role.
  let reference = final_body.direct_value_reference().unwrap()
  let final_fact = reader.observe_member(
    own,
    domain,
    final_member.kind,
    final_member.name,
  )
  let resolved = reader.observe_member(
    reference.package_name,
    reference.module_name,
    ValueMember,
    reference.local_name,
  )
  let final_expected = json_pointer(expected, "/domainInventory/finalPageBody")
  for field in ["document", "outputType", "reference", "referenceKind"] {
    assert_eq(
      @wire.field(final_fact, field),
      @wire.field(final_expected, field),
    )
  }
  assert_eq(
    @wire.field(resolved, "integerLiteral"),
    @wire.field(final_expected, "referencedIntegerLiteral"),
  )
  // Following this reference opens only its value body, never the homonymous type.
  let selected_bodies = source.opens.filter(path => {
    path.contains(".value.") || path.contains(".type.")
  })
  let extension = if profile.has_suffix("json") { ".json" } else { ".yaml" }
  assert_eq(selected_bodies, [
    "pkg/acme/orders/domain/total-in-_usd.value" + extension,
    "pkg/acme/orders/domain/total-in-_usd.value" + extension,
    "pkg/acme/orders/domain/order.value" + extension,
  ])
  // All selected variants are actually decoded, including specifications and the homonymous type.
  let selected : Array[Json] = []
  for expected_module in @wire.array(@wire.field(expected, "modules")) {
    let package_name = @ir.Path::parse(
      @wire.string(@wire.field(expected_module, "package")),
    )
    let module_name = @ir.Path::parse(
      @wire.string(@wire.field(expected_module, "path")),
    )
    for expected_entry in @wire.array(@wire.field(expected_module, "members")) {
      let kind = if @wire.string(@wire.field(expected_entry, "kind")) == "type" {
        @yaml.TypeMember
      } else {
        @yaml.ValueMember
      }
      let name = @ir.Name::parse(
        @wire.string(@wire.field(expected_entry, "name")),
      )
      let observation = reader.observe_member(
        package_name, module_name, kind, name,
      )
      for field in ["name", "kind", "role", "document"] {
        assert_eq(
          @wire.field(observation, field),
          @wire.field(expected_entry, field),
        )
      }
      let (physical, original) = reader.read_original_document(
        MemberArtifact(package_name, module_name, kind, name),
      )
      assert_eq(original, files.filter(file => file.0 == physical)[0].1)
      selected.push(observation)
    }
  }
  if reader.format_version().major == 3U {
    for attribute in @wire.array(@wire.field(expected, "classicAttributes")) {
      let document = @wire.field(attribute, "document")
      let observation = selected.filter(item => {
          @wire.optional(item, "document") == Some(document)
        })[0]
      let slot = if @wire.string(@wire.field(observation, "role")) ==
        "definition" {
        "def"
      } else {
        "spec"
      }
      let expanded = @wire.obj([(slot, @wire.field(observation, "payload"))])
      assert_eq(
        json_pointer(expanded, @wire.string(@wire.field(attribute, "pointer"))),
        @wire.field(attribute, "value"),
      )
    }
  }
  // This is adapter input data, not a published receipt or a kit verdict.
  println(
    @wire.obj([
      ("profile", @wire.text(profile)),
      ("manifest", manifest),
      ("modules", Json::array(all_modules)),
      ("domainPages", Json::array(all_pages)),
      ("members", Json::array(selected)),
      ("finalValue", final_fact),
      ("resolvedValue", resolved),
    ]).stringify(),
  )
}

///|
test "reader observations frozen v3 plain JSON" {
  check_observation_profile(0)
}

///|
test "reader observations frozen v3 plain YAML" {
  check_observation_profile(1)
}

///|
test "reader observations frozen v3 contextual JSON" {
  check_observation_profile(2)
}

///|
test "reader observations frozen v3 contextual YAML" {
  check_observation_profile(3)
}

///|
test "reader observations frozen v4 plain JSON" {
  check_observation_profile(4)
}

///|
test "reader observations frozen v4 plain YAML" {
  check_observation_profile(5)
}

///|
test "reader observations frozen v4 contextual JSON" {
  check_observation_profile(6)
}

///|
test "reader observations frozen v4 contextual YAML" {
  check_observation_profile(7)
}

///|
test "reader observations refuse cursor selection and stale source before reads" {
  let source = recording_tree(observation_profiles()[6].1)
  let reader = @yaml.open_bounded_tree(
    source.source(),
    encoding=ContextualDraft1,
  )
  let own = reader.package_name()
  let domain = @ir.Path::parse("domain")
  let page = reader.members(own, domain, limit=2)
  let cursor = page.next.unwrap()
  let before = source.opens.copy()
  assert_tree_error(
    () => reader.members(own, @ir.Path::parse("audit"), limit=2, cursor~),
    "invalid_cursor",
    "manifest",
  )
  let other = @yaml.open_bounded_tree(
    source.source(),
    encoding=ContextualDraft1,
  )
  assert_tree_error(
    () => other.members(own, domain, limit=2, cursor~),
    "invalid_cursor",
    "manifest",
  )
  assert_eq(source.opens, before + ["manifest.json"])
  source.revision.val = "changed"
  guard tree_failure(() => {
      reader.observe_member(own, domain, ValueMember, @ir.Name::parse("order"))
    })
    is Some(@yaml.TreeSourceError::RevisionChanged) else {
    fail("expected stale observation refusal")
  }
  assert_eq(source.opens, before + ["manifest.json"])
}

///|
test "reader observations derive integers from the selected body" {
  for index in [0, 1, 2, 3, 4, 5, 6, 7] {
    let (_, files, encoding) = observation_profiles()[index]
    let changed = files.map(file => {
      if file.0.contains("/order.value.") {
        (file.0, file.1.replace_all(old="73", new="74"))
      } else {
        file
      }
    })
    let reader = @yaml.open_bounded_tree(
      recording_tree(changed).source(),
      encoding~,
    )
    let own = reader.package_name()
    let domain = @ir.Path::parse("domain")
    let body = reader.read_member(
      own,
      domain,
      ValueMember,
      @ir.Name::parse("total-in-USD"),
    )
    let reference = body.direct_value_reference().unwrap()
    let observed = reader.observe_member(
      reference.package_name,
      reference.module_name,
      ValueMember,
      reference.local_name,
    )
    let literal = @wire.field(observed, "integerLiteral")
    assert_eq(literal, @wire.number("74"))
    assert_false(
      literal ==
      json_pointer(
        observation_expected(),
        "/domainInventory/finalPageBody/referencedIntegerLiteral",
      ),
    )
    let homonym = reader.read_member(
      own,
      domain,
      TypeMember,
      reference.local_name,
    )
    assert_true(homonym.direct_value_reference() is None)
  }
}

///|
test "reader observations preserve selected admission refusals" {
  let files = observation_profiles()[4].1
  let physical = "pkg/acme/orders/domain/order.value.json"
  let own = @ir.Path::parse("acme/orders")
  let domain = @ir.Path::parse("domain")
  let order = @ir.Name::parse("order")
  let oversized = recording_tree(
    files.map(file => {
      if file.0 == physical {
        (physical, " ".repeat(257))
      } else {
        file
      }
    }),
  )
  let reader = @yaml.open_bounded_tree(oversized.source(), limits={
    ..@yaml.Limits::default(),
    max_bytes: 256,
  })
  assert_tree_error(
    () => reader.observe_member(own, domain, ValueMember, order),
    "document_size_limit",
    "pkg/acme/orders/domain/order.value",
  )
  assert_false(oversized.delivered.contains(physical))
  let missing = @yaml.open_bounded_tree(
    recording_tree(files.filter(file => file.0 != physical)).source(),
  )
  assert_tree_error(
    () => missing.observe_member(own, domain, ValueMember, order),
    "missing_member",
    "pkg/acme/orders/domain/order.value",
  )
  let original = @yaml.open_bounded_tree(recording_tree(files).source())
  assert_tree_error(
    () => {
      original.observe_member(
        own,
        domain,
        ValueMember,
        @ir.Name::parse("absent"),
      )
    },
    "missing_member",
    "pkg/acme/orders/domain/absent.value",
  )
}
