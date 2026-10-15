///|
fn rewrite(
  bytes : Bytes,
  change : (@ion.IonValue) -> @ion.IonValue raise,
) -> Bytes raise {
  @binary.write_binary_value(change(@binary.read_binary_value(bytes[:])))
}

///|
fn replace(
  value : @ion.IonValue,
  key : String,
  replacement : @ion.IonValue,
) -> @ion.IonValue raise {
  guard value.kind() is @ion.Struct(entries) else { fail("fixture struct") }
  @ion.IonValue::from_fields(
    entries.map(field => {
      if field.name().text() == Some(key) {
        @ion.Field::new(key, replacement)
      } else {
        field
      }
    }),
  ).with_annotations(value.annotations())
}

///|
fn refuses(run : () -> Unit raise) -> Unit raise {
  let refused = try {
    run()
    false
  } catch {
    _ => true
  }
  assert_true(refused)
}

///|
test "actual Rust binary frames feed native naming metadata and contexts" {
  let e = expected()
  admit_capabilities(shared_capabilities(), e.invocation, e.project_scope)
  let snapshot = Snapshot::decode(shared_snapshot(), e)
  let restored = snapshot.restored()
  assert_eq(
    restored.revision,
    "870af5f51087dfe6a13fdf10c3b856d879b53d650982612a7aede276060c0720",
  )
  let context = snapshot.context("./contexts/schema.jsonld", restored.document)
  assert_eq(
    context.sha256,
    "01a54bdd5624d57b003d6196e97c0f94c5a37a0c77e4303834775cd72e8bf1d7",
  )
  assert_eq(snapshot.context("./schema.jsonld", context.url).url, context.url)
  assert_eq(
    snapshot.context(
      "morphir://context/sha256/" + context.sha256,
      restored.document,
    ).bytes,
    context.bytes,
  )
  let result = @linked_metadata.interpret(
    @fixtures.input(),
    "sample",
    [
      {
        node_id: "value:example:main#ready",
        data: @fixtures.adapter("[" + @fixtures.row("ready") + "]"),
      },
    ],
    capabilities={
      restore_library: Some(fn(_) raise { snapshot.restored() }),
      load_context: Some(fn(resource, base) raise {
        snapshot.context(resource, base)
      }),
      target_names_interpreter: true,
    },
  )
  assert_eq(result.facts[0].names.backend["moonbit"], "wanted")
  assert_eq(result.facts[0].provider_revision, restored.revision)
}

///|
test "correlation and every frozen identity are mandatory" {
  let bytes = shared_snapshot()
  for
    e in [
      { ..expected(), invocation: "another-operation", },
      {
        ..expected(),
        project_scope: "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
      },
      { ..expected(), release: "other.example/morphir/naming@1.0.0", },
      {
        ..expected(),
        policy_sha256: "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
      },
      {
        ..expected(),
        lock_sha256: "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
      },
    ] {
    refuses(fn() raise { ignore(Snapshot::decode(bytes, e)) })
  }
  for key in ["service", "profile", "profileVersion", "codec"] {
    let changed = rewrite(bytes, fn(v) raise {
      replace(v, key, @ion.IonValue::string("other"))
    })
    refuses(fn() raise { ignore(Snapshot::decode(changed, expected())) })
  }
  refuses(fn() raise {
    admit_capabilities(
      shared_capabilities(),
      "wrong-operation",
      expected().project_scope,
    )
  })
}

///|
test "original native and context digests and metadata are checked" {
  let bytes = shared_snapshot()
  for key in ["native", "manifest", "contexts"] {
    // Manifest is opaque original data; changing its type must still fail.
    let changed = rewrite(bytes, fn(v) raise {
      let libraries = list(
        required(members(v.with_annotations([])), "libraries"),
        128,
      )
      replace(
        v,
        "libraries",
        @ion.IonValue::list([
          replace(libraries[0], key, @ion.IonValue::string("tampered")),
        ]),
      )
    })
    refuses(fn() raise { ignore(Snapshot::decode(changed, expected())) })
  }
  for key in ["core", "metadata"] {
    let changed = rewrite(bytes, fn(v) raise {
      replace(v, key, @ion.IonValue::blob(@utf8.encode("{}")))
    })
    refuses(fn() raise { ignore(Snapshot::decode(changed, expected())) })
  }
  let corrupt_context = rewrite(bytes, fn(v) raise {
    let libraries = list(
      required(members(v.with_annotations([])), "libraries"),
      128,
    )
    let contexts = list(required(members(libraries[0]), "contexts"), 256)
    replace(
      v,
      "libraries",
      @ion.IonValue::list([
        replace(
          libraries[0],
          "contexts",
          @ion.IonValue::list([
            replace(
              contexts[0],
              "bytes",
              @ion.IonValue::blob(@utf8.encode("changed")),
            ),
          ]),
        ),
      ]),
    )
  })
  refuses(fn() raise { ignore(Snapshot::decode(corrupt_context, expected())) })
}

///|
test "context inventory has no filesystem or network fallback" {
  let snapshot = Snapshot::decode(shared_snapshot(), expected())
  let document = snapshot.restored().document
  for
    path in [
      "../escape", "/absolute", "https://example.com/schema", "./missing", "contexts\\schema.jsonld",
      "./contexts//schema.jsonld",
    ] {
    refuses(fn() raise { ignore(snapshot.context(path, document)) })
  }
  refuses(fn() raise {
    ignore(snapshot.context("./contexts/schema.jsonld", "unknown://base"))
  })
  refuses(fn() raise {
    ignore(snapshot.context("morphir://context/sha256/not-a-digest", document))
  })
}

///|
test "binary framing bounds recursion and rejects trailing or unknown values" {
  let bytes = shared_snapshot()
  refuses(fn() raise {
    ignore(Snapshot::decode(@utf8.encode("{}"), expected()))
  })
  refuses(fn() raise {
    ignore(Snapshot::decode(bytes[:bytes.length() - 1].to_owned(), expected()))
  })
  let extra = @binary.write_binary_value(@ion.IonValue::string("second"))
  let joined = Bytes::from_array(bytes.to_array() + extra.to_array())
  refuses(fn() raise { ignore(Snapshot::decode(joined, expected())) })
  let mut nested = @ion.IonValue::string("leaf")
  for _ in 0..<20 {
    nested = @ion.IonValue::list([nested])
  }
  let deep = @binary.write_binary_value(nested)
  refuses(fn() raise { preflight(deep) })
  refuses(fn() raise {
    ignore(
      Snapshot::decode(
        rewrite(bytes, fn(v) raise {
          guard v.kind() is @ion.Struct(entries) else { fail("fixture") }
          @ion.IonValue::from_fields(entries + [entries[0]]).with_annotations(
            v.annotations(),
          )
        }),
        expected(),
      ),
    )
  })
}

///|
test "returned metadata cannot mutate retained response views" {
  let snapshot = Snapshot::decode(shared_snapshot(), expected())
  let view = snapshot.restored()
  if view.document_metadata.kind() is @ion.Struct(entries) {
    entries.clear()
  }
  assert_true(
    snapshot.restored().document_metadata.kind() is @ion.Struct(entries) &&
    entries.length() > 0,
  )
}

///|
test "requests retain blobs and reject a changed policy snapshot" {
  let policy = @utf8.encode("policy bytes")
  let lock = @utf8.encode("lock bytes")
  let e = {
    ..expected(),
    policy_sha256: @identity.sha256(policy),
    lock_sha256: @identity.sha256(lock),
  }
  let bytes = snapshot_request(
    e, policy, lock, "/registry", "/state", "/scratch/output",
  )
  let value = @binary.read_binary_value(bytes[:])
  let fields = members(value.with_annotations([]))
  assert_eq(blob(required(fields, "policy")), policy)
  assert_eq(blob(required(fields, "lock")), lock)
  refuses(fn() raise {
    ignore(
      snapshot_request(
        e,
        @utf8.encode("changed"),
        lock,
        "/registry",
        "/state",
        "/output",
      ),
    )
  })
}

///|
test "context responses have independent byte ownership" {
  let snapshot = Snapshot::decode(shared_snapshot(), expected())
  let document = snapshot.restored().document
  let first = snapshot.context("./contexts/schema.jsonld", document)
  let hashed = snapshot.context(
    "morphir://context/sha256/" + first.sha256,
    document,
  )
  assert_eq(first.bytes, hashed.bytes)
  assert_false(physical_equal(first.bytes, hashed.bytes))
  assert_false(
    physical_equal(
      first.bytes,
      snapshot.libraries[snapshot.root].contexts[0].bytes,
    ),
  )
  assert_false(
    physical_equal(
      hashed.bytes,
      snapshot.libraries[snapshot.root].contexts[0].bytes,
    ),
  )
}

///|
test "capability encoders enforce the advertised request bound" {
  refuses(fn() raise {
    ignore(
      capabilities_request(
        "x".repeat(MAX_REQUEST_BYTES),
        expected().project_scope,
      ),
    )
  })
  refuses(fn() raise {
    ignore(
      capabilities_request(expected().invocation, "x".repeat(MAX_REQUEST_BYTES)),
    )
  })
}
