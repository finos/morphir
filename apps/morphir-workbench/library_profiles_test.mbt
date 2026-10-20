///|
let library_source : String =
  #|fn gate(active : Bool) -> Bool { active }
  #|pub fn eligible(activeUser : Bool, vipMember : Bool) -> Bool {
  #|  let allowed = gate(activeUser)
  #|  allowed && !vipMember
  #|}
  #|pub fn welcome() -> Bool { eligible(true, false) }

///|
fn library_entry(result : Json, name : String) -> String raise {
  for node in @wire.array(@wire.field(result, "nodes")) {
    if @wire.string(@wire.field(node, "label")) == name {
      return @wire.string(@wire.field(node, "id"))
        .strip_prefix("value|")
        .unwrap_or(@wire.string(@wire.field(node, "id"))[:])
        .to_owned()
    }
  }
  abort("Missing library function: " + name)
}

///|
fn library_compile(source~ : String = library_source) -> Json {
  @pipeline.execute({
    "operation": "compile",
    "source": source,
    "languageId": "moonbit",
    "frontendProvider": "finos/morphir-moonbit-frontend",
    "frontendProfile": "moonbit-model-stable-v1",
    "target": "moonbit",
  })
}

///|
test "local catalog exposes one MoonBit language and the registered profile descriptions" {
  let catalog = @pipeline.execute({ "operation": "catalog" })
  let frontends = @wire.array(@wire.field(catalog, "frontends"))
  let moonbit = frontends.filter(f => {
    @wire.field(f, "languageId") == @wire.text("moonbit")
  })
  assert_eq(moonbit.length(), 1)
  assert_eq(
    @wire.field(moonbit[0], "defaultProfile"),
    @wire.text(@moonbit_frontend.STABLE_PROFILE),
  )
  let profiles = @wire.array(@wire.field(moonbit[0], "profiles"))
  assert_eq(profiles.map(p => @wire.string(@wire.field(p, "id"))), [
    @moonbit_frontend.STABLE_PROFILE,
    @moonbit_frontend.EXPERIMENTAL_PROFILE,
  ])
  assert_eq(
    @wire.field(profiles[1], "displayName"),
    @wire.text("Experimental typed MoonBit library"),
  )
  assert_eq(
    @wire.field(profiles[1], "evidence"),
    @wire.text("local-acceptance"),
  )
}

///|
test "library selection preserves every source label and origin without inferring an entry" {
  let result = library_compile()
  assert_eq(
    @wire.field(result, "success"),
    Json::boolean(true),
    msg=result.stringify(),
  )
  assert_eq(
    @wire.field(result, "sourceProfile"),
    @wire.text(@moonbit_frontend.STABLE_PROFILE),
  )
  assert_eq(@wire.optional(result, "sourceEntry"), None)
  let entries = @wire.array(@wire.field(result, "sourceEntries"))
  assert_eq(entries.length(), 2)
  assert_true(entries.contains(@wire.text(library_entry(result, "eligible"))))
  assert_true(entries.contains(@wire.text(library_entry(result, "welcome"))))
  let profiles = @wire.field(@wire.field(result, "typedEvaluations"), "entries")
  assert_eq(@wire.optional(profiles, library_entry(result, "gate")), None)
  let inputs = @wire.array(
    @wire.field(
      @wire.field(profiles, library_entry(result, "eligible")),
      "inputs",
    ),
  )
  assert_eq(inputs.map(p => @wire.string(@wire.field(p, "label"))), [
    "activeUser", "vipMember",
  ])
  let registry = @data.Registry::new()
  let unit = registry.decode("ion-text", {
    unit_id: "main",
    content: Text(@wire.string(@wire.field(result, "sourceUnitIon"))),
  })
  let original = @moonbit_frontend.compile_library({
    unit_id: "main",
    package_name: "user",
    module_name: "main",
    source: library_source,
  })
  assert_eq(@codec.to_json(unit.distribution), @codec.to_json(original.ir))
  assert_eq(unit.metadata.length(), original.metadata.length())
  for i, item in unit.metadata {
    assert_true(item.data.equals(original.metadata[i].data))
  }
  assert_true(unit.provenance[0].equals(original.provenance[0]))
}

///|
test "library calls and lets evaluate through JSON and Ion while private entry requests reject in both runtimes" {
  let result = library_compile()
  let source = @wire.string(@wire.field(result, "irSource"))
  let calls : Array[(String, Array[Json], Bool)] = [
    (
      "eligible",
      [{ "type": "bool", "value": true }, { "type": "bool", "value": false }],
      true,
    ),
    ("welcome", [], true),
  ]
  for (entry, arguments, expected) in calls {
    let reply = @pipeline.execute({
      "operation": "evaluate",
      "source": source,
      "entry": library_entry(result, entry),
      "executionMode": "typed",
      "arguments": arguments,
    })
    assert_eq(
      @wire.field(reply, "success"),
      Json::boolean(true),
      msg=reply.stringify(),
    )
    assert_eq(@wire.field(reply, "typed"), { "type": "bool", "value": expected })
  }
  let reply = @pipeline.execute({
    "operation": "evaluate",
    "source": source,
    "entry": library_entry(result, "eligible"),
    "executionMode": "typed",
    "argumentsIon": "[true, true]",
  })
  assert_eq(@wire.field(reply, "typed"), { "type": "bool", "value": false })
  for mode in ["typed", "scheme"] {
    let reply = @pipeline.execute({
      "operation": "evaluate",
      "source": source,
      "entry": library_entry(result, "gate"),
      "executionMode": mode,
      "arguments": [{ "type": "bool", "value": true }],
    })
    assert_eq(@wire.field(reply, "success"), Json::boolean(false))
  }
}

///|
test "profile and provider refusals cannot fall back to the seed or another source language" {
  for
    provider, profile in [
      ("unknown/compiler", @moonbit_frontend.STABLE_PROFILE),
      ("finos/morphir-moonbit-frontend", "unknown-profile"),
    ] {
    let result = @pipeline.execute({
      "operation": "compile",
      "source": library_source,
      "languageId": "moonbit",
      "frontendProvider": provider,
      "frontendProfile": profile,
    })
    assert_eq(@wire.field(result, "success"), Json::boolean(false))
  }
  let stable = compile_moonbit(library_source)
  assert_eq(@wire.field(stable, "success"), Json::boolean(true))
  assert_eq(
    @wire.field(stable, "sourceProfile"),
    @wire.text(@moonbit_frontend.STABLE_PROFILE),
  )
  let scheme = @pipeline.execute({
    "operation": "compile",
    "source": "(+ 1 2)",
    "languageId": "scheme",
    "frontendProfile": @moonbit_frontend.STABLE_PROFILE,
  })
  assert_eq(@wire.field(scheme, "success"), Json::boolean(false))
  let recursion = library_compile(
    source="pub fn recur(x : Bool) -> Bool { recur(x) }",
  )
  assert_eq(@wire.field(recursion, "success"), Json::boolean(false))
  assert_eq(
    @wire.field(@wire.field(recursion, "frontendDiagnostic"), "code"),
    @wire.text("moonbit_frontend.recursive_call"),
  )
}

///|
test "all-private libraries remain inspectable with an empty public manifest" {
  let result = library_compile(
    source="fn gate(active : Bool) -> Bool { active }",
  )
  assert_eq(
    @wire.field(result, "success"),
    Json::boolean(true),
    msg=result.stringify(),
  )
  assert_eq(@wire.field(result, "sourceEntries"), Json::array([]))
  assert_eq(
    @wire.field(@wire.field(result, "typedEvaluations"), "entries"),
    Json::object(Map([])),
  )
  assert_true(!@wire.array(@wire.field(result, "nodes")).is_empty())
}

///|
test "String source compiles and executes typed public entries in the workbench" {
  let compiled = @pipeline.execute({
    "operation": "compile",
    "languageId": "moonbit",
    "frontendProfile": "moonbit-model-stable-v1",
    "target": "moonbit",
    "source": "fn prefix() -> String { \"Hello, \" }\npub fn welcome(name : String, enabled : Bool) -> String { if enabled { prefix() + name } else { \"\" } }",
  })
  assert_eq(
    @wire.field(compiled, "success"),
    Json::boolean(true),
    msg=compiled.stringify(),
  )
  let entry = library_entry(compiled, "welcome")
  for
    (enabled, units) in [
      (true, [72, 101, 108, 108, 111, 44, 32, 55357, 56832]),
      (false, []),
    ] {
    let evaluated = @pipeline.execute({
      "operation": "evaluate",
      "executionMode": "typed",
      "source": @wire.string(@wire.field(compiled, "irSource")),
      "entry": entry,
      "arguments": [
        { "type": "text", "units": [55357, 56832] },
        { "type": "bool", "value": enabled },
      ],
    })
    assert_eq(
      @wire.field(evaluated, "success"),
      Json::boolean(true),
      msg=evaluated.stringify(),
    )
    assert_eq(@wire.field(evaluated, "typed"), {
      "type": "text",
      "units": units,
    })
  }
}
