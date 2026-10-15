///|
fn reject(code : String, action : () -> Unit raise) -> Unit raise {
  try {
    action()
    fail("Expected " + code)
  } catch {
    @metadata.Invalid(actual, _, fix) => {
      assert_eq(actual, code)
      assert_false(fix.is_empty())
    }
    other => raise other
  }
}

///|
fn consume(
  data : @ion.IonValue,
  capabilities? : @metadata.Capabilities = @fixtures.capabilities(),
) -> @metadata.Interpretation raise {
  @metadata.interpret(
    @fixtures.input(),
    "sample",
    [{ node_id: "value:example:main#ready", data, }],
    capabilities~,
  )
}

///|
test "declaration observations distinguish admission and preserve semantics when the sink fails" {
  let data = @fixtures.adapter("[" + @fixtures.row("ready") + "]")
  let events : Array[@metadata.ProviderSignal] = []
  let capabilities = {
    ..@fixtures.capabilities(),
    provider_observer: { notify: fn(signal) { events.push(signal) }, },
  }
  let accepted = consume(data, capabilities~)
  assert_eq(events, [@metadata.Started, @metadata.Succeeded])
  assert_eq(accepted.facts[0].names.backend["moonbit"], "wanted")
  let broken_sink = {
    ..capabilities,
    provider_observer: { notify: fn(_) raise { fail("sink unavailable") }, },
  }
  let unchanged = consume(data, capabilities=broken_sink)
  assert_eq(unchanged.facts[0].names, accepted.facts[0].names)
  assert_eq(
    unchanged.facts[0].provider_revision,
    accepted.facts[0].provider_revision,
  )
  events.clear()
  reject("metadata.invalid_provider_identity", fn() raise {
    ignore(
      consume(data, capabilities={
        ..capabilities,
        restore_library: Some(fn(_) raise {
          { ..@fixtures.provider(), format: "wrong", }
        }),
      }),
    )
  })
  assert_eq(events, [
    @metadata.Started,
    @metadata.Refused("metadata.invalid_provider_identity"),
  ])
  events.clear()
  ignore(@metadata.interpret(@fixtures.input(), "sample", [], capabilities~))
  assert_true(events.is_empty())
}

///|
test "upstream closed targetNames record and language ID expectations" {
  for
    language in [
      "moonbit", "elm", "typescript", "fsharp", "csharp", "my-lang2", "x-2",
    ] {
    assert_true(@metadata.valid_language_id(language))
  }
  for
    language in [
      "", "MoonBit", "moonbit_library", "2lang", "x--y", "x-", "-x", "a.b", "a/../b",
    ] {
    assert_false(@metadata.valid_language_id(language))
  }
  let names = @metadata.TargetNames::from_ion(
    @ion_text.read_ion("{frontend:{moonbit:\"morphir://opaque\"},backend:{}}"),
  )
  assert_eq(names.frontend["moonbit"], "morphir://opaque")
  assert_eq(names.backend.length(), 0)
  for source in ["{frontend:{}}", "{frontend:{},backend:{},extra:{}}"] {
    reject("metadata.invalid_target_names", fn() raise {
      ignore(@metadata.TargetNames::from_ion(@ion_text.read_ion(source)))
    })
  }
  reject("metadata.invalid_language_id", fn() raise {
    ignore(
      @metadata.TargetNames::from_ion(
        @ion_text.read_ion("{frontend:{MoonBit:\"ready\"},backend:{}}"),
      ),
    )
  })
  reject("metadata.invalid_string", fn() raise {
    ignore(
      @metadata.TargetNames::from_ion(
        @ion_text.read_ion("{frontend:{},backend:{moonbit:42}}"),
      ),
    )
  })
  reject("metadata.duplicate_field", fn() raise {
    ignore(
      @metadata.TargetNames::from_ion(
        @ion_text.read_ion(
          "{frontend:{},backend:{moonbit:\"a\",moonbit:\"b\"}}",
        ),
      ),
    )
  })
}

///|
test "document graph assertions stay separate from subjects and equal duplicates survive" {
  let row = @fixtures.row("ready")
  let data = @fixtures.adapter("[" + row + "," + row + "]")
  let before = @ion_text.write_ion(data)
  let result = consume(data)
  assert_eq(result.facts.length(), 1)
  let fact = result.facts[0]
  assert_eq(fact.owner, "value:example:main#ready")
  assert_eq(fact.names.backend["moonbit"], "wanted")
  assert_eq(fact.assertions.length(), 2)
  assert_false(fact.assertions[0].document == fact.assertions[0].subject)
  assert_eq(fact.assertions[0].ordinal, 0)
  assert_eq(fact.assertions[1].ordinal, 1)
  assert_eq(fact.provider_revision, @fixtures.REVISION)
  assert_eq(@ion_text.write_ion(data), before)
}

///|
test "provider admission is explicit fresh and derived from the restored native declaration" {
  let data = @fixtures.adapter("[" + @fixtures.row("ready") + "]")
  reject("metadata.provider_unavailable", fn() raise {
    ignore(consume(data, capabilities=@metadata.Capabilities::unavailable()))
  })
  let calls = Ref(0)
  let admitted = {
    ..@fixtures.capabilities(),
    restore_library: Some(fn(_) raise {
      calls.val += 1
      @fixtures.provider()
    }),
  }
  ignore(consume(data, capabilities=admitted))
  ignore(consume(data, capabilities=admitted))
  assert_eq(calls.val, 2)
  reject("metadata.required_interpreter_unavailable", fn() raise {
    ignore(
      consume(data, capabilities={
        ..admitted,
        target_names_interpreter: false,
      }),
    )
  })
  let missing = {
    ..@fixtures.capabilities(),
    restore_library: Some(fn(_) raise {
      { ..@fixtures.provider(), document_metadata: @ion_text.read_ion("{}"), }
    }),
  }
  reject("metadata.invalid_provider_declaration", fn() raise {
    ignore(consume(data, capabilities=missing))
  })
  let wrong = {
    ..@fixtures.capabilities(),
    restore_library: Some(fn(_) raise {
      { ..@fixtures.provider(), revision: "bad", }
    }),
  }
  reject("metadata.invalid_provider_identity", fn() raise {
    ignore(consume(data, capabilities=wrong))
  })
  let predicate = @metadata.TARGET_NAMES_PREDICATE.replace(
    old="#/",
    new="&rev=sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb#/",
  )
  let pinned = @fixtures.adapter(
    "[" + @fixtures.row("ready") + "]",
    context="{targetNames:{'@id':\"" + predicate + "\",'@type':\"@json\"}}",
  )
  reject("metadata.provider_revision_mismatch", fn() raise {
    ignore(consume(pinned))
  })
}

///|
test "known requests require current ValueDefinition identity and consistent authored records" {
  let row = @fixtures.row("ready")
  reject("metadata.unsupported_subject_role", fn() raise {
    ignore(
      consume(
        @fixtures.adapter(
          "[" + row.replace(old="/value/ready", new="/value/ready/body") + "]",
        ),
      ),
    )
  })
  reject("metadata.unresolved_subject", fn() raise {
    ignore(consume(@fixtures.adapter("[" + @fixtures.row("missing") + "]")))
  })
  reject("metadata.conflicting_target_names", fn() raise {
    ignore(
      consume(
        @fixtures.adapter(
          "[" + row + "," + @fixtures.row("ready", backend="different") + "]",
        ),
      ),
    )
  })
  reject("metadata.invalid_object", fn() raise {
    ignore(
      consume(
        @fixtures.adapter(
          "[" + row + "]",
          context="{targetNames:\"" + @metadata.TARGET_NAMES_PREDICATE + "\"}",
        ),
      ),
    )
  })
  let wrong_holder : Array[@metadata.MetadataEntry] = [
    {
      node_id: "value:unowned:main#ready",
      data: @fixtures.adapter("[" + row + "]"),
    },
  ]
  reject("metadata.invalid_holder", fn() raise {
    ignore(
      @metadata.interpret(
        @fixtures.input(),
        "sample",
        wrong_holder,
        capabilities=@fixtures.capabilities(),
      ),
    )
  })
}

///|
test "unknown fact data and context remain intact without provider admission" {
  let predicate = "morphir://ir/pkg/other/metadata?format=4.1.0#/module/naming/value/something"
  let data = @fixtures.adapter(
    "[" + @fixtures.row("ready") + "]",
    context="{targetNames:{'@id':\"" + predicate + "\",'@type':\"@json\"}}",
  )
  let before = @ion_text.write_ion(data)
  let result = consume(data, capabilities=@metadata.Capabilities::unavailable())
  assert_eq(result.facts.length(), 0)
  assert_eq(result.unvalidated_predicates, [predicate])
  assert_eq(@ion_text.write_ion(data), before)
}

///|
test "scoped context aliases override locally while protected bindings cannot change" {
  let row = @fixtures.row("ready")
  let source = "morphir_linked_metadata_v1::{document:\"morphir://ir/pkg/example/annotations?format=4.1.0#/distribution\",'@context':{targetNames:\"morphir://ir/pkg/other/metadata?format=4.1.0#/module/naming/value/name\"},'$meta':{'@context':{targetNames:{'@id':\"" +
    @metadata.TARGET_NAMES_PREDICATE +
    "\",'@type':\"@json\"}},'@graph':[" +
    row +
    "]}}"
  assert_eq(consume(@ion_text.read_ion(source)).facts.length(), 1)
  reject("metadata.protected_term_redefinition", fn() raise {
    ignore(
      consume(
        @ion_text.read_ion(
          source.replace(
            old="targetNames:\"morphir://ir/pkg/other/metadata?format=4.1.0#/module/naming/value/name\"",
            new="targetNames:{'@id':\"morphir://ir/pkg/other/metadata?format=4.1.0#/module/naming/value/name\",'@protected':true}",
          ),
        ),
      ),
    )
  })
  let compact = @fixtures.adapter(
    "[" + @fixtures.row("ready", property="n:target-names") + "]",
    context="{n:{'@id':\"morphir://ir/pkg/morphir/naming?format=4.1.0#/module/naming/value/\",'@prefix':true},'n:target-names':{'@id':\"" +
      @metadata.TARGET_NAMES_PREDICATE +
      "\",'@type':\"@json\"}}",
  )
  assert_eq(consume(compact).facts.length(), 1)
  reject("metadata.invalid_predicate_uri", fn() raise {
    ignore(
      consume(
        @fixtures.adapter(
          "[" + row + "]",
          context="{'@vocab':\"morphir://ir/pkg/morphir/naming?format=4.1.0#/module/naming/value/\"}",
        ),
      ),
    )
  })
}

///|
test "context references require exact bytes and reject duplicate imports and collisions before overrides" {
  let context = "{\"@context\":{\"targetNames\":{\"@id\":\"" +
    @metadata.TARGET_NAMES_PREDICATE +
    "\",\"@type\":\"@json\"}}}"
  let bytes = @utf8.encode(context)
  let digest = @crypto.bytes_to_hex_string(@crypto.sha256(bytes))
  let reference = "morphir://context/sha256/" + digest
  let loader = {
    ..@fixtures.capabilities(),
    load_context: Some(fn(resource, _) raise {
      { url: resource, bytes, sha256: digest, }
    }),
  }
  let data = @fixtures.adapter(
    "[" + @fixtures.row("ready") + "]",
    context="\"" + reference + "\"",
  )
  assert_eq(consume(data, capabilities=loader).facts.length(), 1)
  let corrupt = {
    ..loader,
    load_context: Some(fn(resource, _) raise {
      { url: resource, bytes: @utf8.encode(context + " "), sha256: digest, }
    }),
  }
  reject("metadata.context_digest_mismatch", fn() raise {
    ignore(consume(data, capabilities=corrupt))
  })
  let repeated = @fixtures.adapter(
    "[" + @fixtures.row("ready") + "]",
    context="[\"" + reference + "\",\"" + reference + "\"]",
  )
  reject("metadata.duplicate_context_import", fn() raise {
    ignore(consume(repeated, capabilities=loader))
  })
  reject("metadata.remote_context_forbidden", fn() raise {
    ignore(
      consume(
        @fixtures.adapter(
          "[]",
          context="\"https://example.com/context.jsonld\"",
        ),
        capabilities=loader,
      ),
    )
  })
  let other = "{\"@context\":{\"targetNames\":\"morphir://ir/pkg/other/metadata?format=4.1.0#/module/naming/value/name\"}}"
  let other_bytes = @utf8.encode(other)
  let other_digest = @crypto.bytes_to_hex_string(@crypto.sha256(other_bytes))
  let other_ref = "morphir://context/sha256/" + other_digest
  let two = {
    ..loader,
    load_context: Some(fn(resource, _) raise {
      if resource == reference {
        { url: resource, bytes, sha256: digest, }
      } else {
        { url: resource, bytes: other_bytes, sha256: other_digest, }
      }
    }),
  }
  let conflict = @fixtures.adapter(
    "[]",
    context="[\"" +
      reference +
      "\",\"" +
      other_ref +
      "\",{targetNames:{'@id':\"" +
      @metadata.TARGET_NAMES_PREDICATE +
      "\",'@type':\"@json\"}}]",
  )
  reject("metadata.context_term_collision", fn() raise {
    ignore(consume(conflict, capabilities=two))
  })
  let no_base = @fixtures.adapter("[]", context="\"relative.jsonld\"")
  reject("metadata.relative_import_without_base", fn() raise {
    ignore(consume(no_base, capabilities=loader))
  })
  let relative_document = "{\"@context\":\"relative.jsonld\"}"
  let relative_bytes = @utf8.encode(relative_document)
  let relative_digest = @crypto.bytes_to_hex_string(
    @crypto.sha256(relative_bytes),
  )
  let relative_loader = {
    ..loader,
    load_context: Some(fn(resource, _) raise {
      { url: resource, bytes: relative_bytes, sha256: relative_digest, }
    }),
  }
  reject("metadata.relative_import_without_base", fn() raise {
    ignore(
      consume(
        @fixtures.adapter(
          "[]",
          context="\"morphir://context/sha256/" + relative_digest + "\"",
        ),
        capabilities=relative_loader,
      ),
    )
  })
}

///|
test "assertion source selectors match expanded local assertions and preserve complete authored sources" {
  let data = @fixtures.adapter("[" + @fixtures.row("ready") + "]")
  let selector = "{carrier:\"documentGraph\",subject:\"morphir://ir/pkg/example?format=4.0.0#/module/main/value/ready\",predicate:\"" +
    @metadata.TARGET_NAMES_PREDICATE +
    "\",object:{'@value':{frontend:{moonbit:\"isReady\"},backend:{moonbit:\"wanted\"}},'@type':\"@json\"}}"
  let sources = "{selector:" +
    selector +
    ",sources:[{kind:\"compiler\",ref:\"model.mbt\",producer:\"moonbit\"},{kind:\"author\",ref:\"maintainer\"}]}"
  let original = @ion_text.write_ion(data)
  let with_sources = @ion_text.read_ion(
    original[:original.length() - 2].to_owned() +
    ",assertionSources:[" +
    sources +
    "]}}",
  )
  assert_eq(consume(with_sources).facts[0].assertions.length(), 1)
  let reordered = @ion_text.read_ion(
    original[:original.length() - 2].to_owned() +
    ",assertionSources:[" +
    sources.replace(
      old="frontend:{moonbit:\"isReady\"},backend:{moonbit:\"wanted\"}",
      new="backend:{moonbit:\"wanted\"},frontend:{moonbit:\"isReady\"}",
    ) +
    "]}}",
  )
  assert_eq(consume(reordered).facts[0].assertions.length(), 1)
  assert_true(@ion_text.write_ion(with_sources).contains("maintainer"))
  let duplicate = @ion_text.read_ion(
    original[:original.length() - 2].to_owned() +
    ",assertionSources:[" +
    sources +
    "," +
    sources +
    "]}}",
  )
  reject("metadata.duplicate_assertion_selector", fn() raise {
    ignore(consume(duplicate))
  })
  let wrong = @ion_text.read_ion(
    original[:original.length() - 2].to_owned() +
    ",assertionSources:[" +
    sources.replace(
      old="backend:{moonbit:\"wanted\"}",
      new="backend:{moonbit:\"different\"}",
    ) +
    "]}}",
  )
  reject("metadata.unmatched_assertion_selector", fn() raise {
    ignore(consume(wrong))
  })
}

///|
test "provider output type and public Library role are checked instead of trusting a companion schema" {
  let data = @fixtures.adapter("[" + @fixtures.row("ready") + "]")
  let original = @fixtures.provider()
  guard original.core.distribution
    is Library(package_name, dependencies, definition) else {
    fail("Library fixture")
  }
  let module_name = @ir.Path::parse("naming")
  let value_name = @ir.Name::parse("target-names")
  let module_def = definition.modules[module_name]
  let entry = module_def.value.values[value_name]
  guard entry.value.value is ExpressionBody(inputs, output, body) &&
    output is Record(attrs, members) else {
    fail("record fixture")
  }
  let wrong_members = members.copy()
  wrong_members[@ir.Name::parse("backend")] = @ir.Type::Unit(attrs)
  let wrong_value = {
    ..entry,
    value: {
      ..entry.value,
      value: @ir.ValueDefinition::ExpressionBody(
        inputs,
        @ir.Type::Record(attrs, wrong_members),
        body,
      ),
    },
  }
  let values = module_def.value.values.copy()
  values[value_name] = wrong_value
  let modules = definition.modules.copy()
  modules[module_name] = {
    ..module_def,
    value: { ..module_def.value, values, },
  }
  let wrong_core = @ir.IRFile::new(
    @ir.Distribution::Library(package_name, dependencies, { modules, }),
  )
  let wrong_type = {
    ..@fixtures.capabilities(),
    restore_library: Some(fn(_) { { ..original, core: wrong_core, } }),
  }
  reject("metadata.invalid_provider_type", fn() raise {
    ignore(consume(data, capabilities=wrong_type))
  })
  let private_modules = definition.modules.copy()
  private_modules[module_name] = { ..module_def, access: @ir.Access::Private, }
  let private_core = @ir.IRFile::new(
    @ir.Distribution::Library(package_name, dependencies, {
      modules: private_modules,
    }),
  )
  let private_provider = {
    ..@fixtures.capabilities(),
    restore_library: Some(fn(_) { { ..original, core: private_core, } }),
  }
  reject("metadata.invalid_provider_declaration", fn() raise {
    ignore(consume(data, capabilities=private_provider))
  })
}

///|
test "selected naming provider admits only nonempty ValueDefinition subject roles" {
  let data = @fixtures.adapter("[" + @fixtures.row("ready") + "]")
  fn provider_roles(roles : String) -> @metadata.Capabilities {
    {
      ..@fixtures.capabilities(),
      restore_library: Some(fn(_) raise {
        {
          ..@fixtures.provider(),
          document_metadata: @ion_text.read_ion(
            "{'@context':{'@vocab':\"morphir://ir/pkg/morphir/metadata?format=4.1.0#/module/schema/value/\"},'@graph':[{'@id':\"" +
            @metadata.TARGET_NAMES_PREDICATE +
            "\",'subject-role':" +
            roles +
            ",'object-form':\"data\",interpreter:\"target-name-language-ids\"}]}",
          ),
        }
      }),
    }
  }
  for
    roles in [
      "[\"ValueDefinition\",\"TypeExpression\"]", "[\"TypeExpression\",\"ValueDefinition\"]",
      "[\"TypeExpression\"]", "[]",
    ] {
    reject("metadata.invalid_provider_declaration", fn() raise {
      ignore(consume(data, capabilities=provider_roles(roles)))
    })
  }
  let valid = consume(
    data,
    capabilities=provider_roles("[\"ValueDefinition\",\"ValueDefinition\"]"),
  )
  assert_eq(valid.facts.length(), 1)
}

///|
test "target-name requests recognize native revision pins while admission checks their value" {
  let revision = @fixtures.provider().revision
  let predicate = @metadata.TARGET_NAMES_PREDICATE.replace(
    old="#/",
    new="&rev=sha256:" + revision + "#/",
  )
  assert_true(
    @metadata.is_target_names_predicate(@metadata.TARGET_NAMES_PREDICATE),
  )
  assert_true(@metadata.is_target_names_predicate(predicate))
  let wrong = @metadata.TARGET_NAMES_PREDICATE.replace(
    old="#/",
    new="&rev=sha256:" + "0".repeat(64) + "#/",
  )
  assert_true(@metadata.is_target_names_predicate(wrong))
  let data = @fixtures.adapter(
    "[" + @fixtures.row("ready") + "]",
    context="{targetNames:{'@id':\"" + predicate + "\",'@type':\"@json\"}}",
  )
  let result = consume(data)
  assert_eq(result.facts[0].provider_revision, revision)
  assert_eq(result.facts[0].names.backend["moonbit"], "wanted")
  for
    other in [
      predicate.replace(old="/pkg/morphir/naming?", new="/pkg/other/naming?"),
      predicate.replace(old="format=4.1.0", new="format=4.0.0"),
      predicate.replace(old="/value/target-names", new="/value/other"),
    ] {
    assert_false(@metadata.is_target_names_predicate(other))
  }
}
