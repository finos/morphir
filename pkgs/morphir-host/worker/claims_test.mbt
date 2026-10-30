///|
test "extension identities are validated values" {
  assert_eq(
    @worker.ExtensionId::parse("morphir-moonbit").to_string(),
    "morphir-moonbit",
  )
  for text in ["", "morphir moonbit", "morphir\nmoonbit", "x".repeat(129)] {
    guard (Ok(@worker.ExtensionId::parse(text)) catch { e => Err(e) })
      is Err(InvalidExtensionId(_)) else {
      fail("accepted extension ID \{text}")
    }
  }
  assert_eq(
    @worker.ExtensionVersion::parse("0.4.2-rc.1").to_string(),
    "0.4.2-rc.1",
  )
  for text in ["", "0.4 .2", "1".repeat(65)] {
    guard (Ok(@worker.ExtensionVersion::parse(text)) catch { e => Err(e) })
      is Err(InvalidExtensionVersion(_)) else {
      fail("accepted version \{text}")
    }
  }
}

///|
fn language(id : String, extensions : Array[String]) -> @worker.LanguageClaim {
  @worker.LanguageClaim::new(
    @ids.LanguageId::parse(id),
    extensions.map(@ids.FileExtension::parse),
  ) catch {
    error => abort(error.to_string())
  }
}

///|
test "claims take languages and file extensions from the extension" {
  // The host holds no list of languages: a language it has never seen is a
  // claim like any other.
  let claims = @worker.Claims::new(
    @worker.ExtensionId::parse("morphir-gleam"),
    @worker.ExtensionVersion::parse("0.1.0"),
    languages=[language("gleam", [".gleam"])],
    operations=[Compile, CompileModel],
  )
  assert_eq(claims.extension_id.to_string(), "morphir-gleam")
  assert_eq(claims.languages[0].language_id.to_string(), "gleam")
  assert_eq(claims.languages[0].file_extensions[0].to_string(), ".gleam")
  assert_true(claims.offers(Compile))
  assert_false(claims.offers(Generate))
}

///|
test "a language claim needs at least one file extension" {
  guard (Ok(@worker.LanguageClaim::new(@ids.LanguageId::parse("elm"), [])) catch {
      e => Err(e)
    })
    is Err(@worker.EmptyLanguageClaim("elm")) else {
    fail("accepted a language without file extensions")
  }
}

///|
test "claims record everything activation compares" {
  let tuple = @worker.ModelTuple::new(
    CompileModel,
    MorphirModel,
    IonBinary,
    V0_1_0Draft1,
    V4_0_0,
  )
  let claims = @worker.Claims::new(
    @worker.ExtensionId::parse("morphir-moonbit"),
    @worker.ExtensionVersion::parse("0.1.0"),
    protocol_lines=[Mep0_2Draft1, Mep0_1],
    operations=[Generate, CompileModel],
    languages=[language("moonbit", [".mbt"])],
    frontend_ir_versions=[@worker.IrVersionName::parse("4.0.0")],
    targets=[@ids.BackendId::parse("moonbit")],
    backend_ir_versions=[@worker.IrVersionName::parse("4")],
    model_tuples=[tuple],
  )
  assert_eq(claims.protocol_lines, [Mep0_1, Mep0_2Draft1])
  assert_eq(claims.targets[0].to_string(), "moonbit")
  assert_eq(claims.backend_ir_versions[0].to_string(), "4")
  assert_eq(claims.frontend_ir_versions[0].to_string(), "4.0.0")
  assert_eq(claims.model_tuples, [tuple])
  guard (Ok(@worker.IrVersionName::parse("4 0")) catch { e => Err(e) })
    is Err(InvalidIrVersionName(_)) else {
    fail("accepted an IR version name with a space")
  }
}

///|
test "claims are sets: order and duplicates do not change them" {
  let id = @worker.ExtensionId::parse("morphir-elm")
  let version = @worker.ExtensionVersion::parse("2.1.0")
  let one = @worker.Claims::new(
    id,
    version,
    operations=[Generate, Compile, Generate],
    languages=[language("elm", [".elm"]), language("elm", [".elm-x", ".elm"])],
    targets=[
      @ids.BackendId::parse("typescript"),
      @ids.BackendId::parse("scala"),
    ],
  )
  let two = @worker.Claims::new(
    id,
    version,
    operations=[Compile, Generate],
    languages=[language("elm", [".elm-x", ".elm"])],
    targets=[
      @ids.BackendId::parse("scala"),
      @ids.BackendId::parse("typescript"),
      @ids.BackendId::parse("scala"),
    ],
  )
  assert_eq(one, two)
  // Languages that name the same language merge their file extensions.
  assert_eq(one.languages.length(), 1)
  assert_eq(one.languages[0].file_extensions.map(e => e.to_string()), [
    ".elm", ".elm-x",
  ])
}

///|
test "claims keep their own copies of the parts" {
  let operations : Array[@worker.Operation] = [Compile]
  let claims = @worker.Claims::new(
    @worker.ExtensionId::parse("morphir-python"),
    @worker.ExtensionVersion::parse("0.4.2"),
    operations~,
  )
  operations.push(Generate)
  assert_eq(claims.operations, [Compile])
}

///|
test "operations are the closed set of MEP operations" {
  for
    operation in [
      @worker.Operation::Compile,
      Generate,
      CompileModel,
      GenerateModel,
    ] {
    assert_eq(@worker.Operation::parse(operation.to_string()), operation)
  }
  assert_eq(@worker.Operation::Compile.to_string(), "morphir.frontend.compile")
  assert_eq(@worker.Operation::Generate.protocol_line(), Mep0_1)
  assert_eq(@worker.Operation::GenerateModel.protocol_line(), Mep0_2Draft1)
  assert_eq(@worker.Operation::CompileModel.model(), Some(CompileModel))
  assert_eq(@worker.Operation::Compile.model(), None)
  assert_eq(@worker.ModelOperation::GenerateModel.operation(), GenerateModel)
  guard (Ok(@worker.Operation::parse("morphir.frontend.lint")) catch {
      e => Err(e)
    })
    is Err(UnknownOperation(_)) else {
    fail("accepted an unknown operation")
  }
}

///|
test "protocol lines are the two MEP versions the host offers" {
  assert_eq(@worker.ProtocolLine::parse("0.1"), Mep0_1)
  assert_eq(@worker.ProtocolLine::parse("0.2.0-draft.1"), Mep0_2Draft1)
  assert_eq(@worker.ProtocolLine::Mep0_2Draft1.to_string(), "0.2.0-draft.1")
  guard (Ok(@worker.ProtocolLine::parse("0.2.0")) catch { e => Err(e) })
    is Err(UnknownProtocolLine(_)) else {
    fail("accepted a protocol version the host does not offer")
  }
}

///|
test "a model tuple has five closed parts" {
  let tuple = @worker.ModelTuple::new(
    CompileModel,
    MorphirIr,
    MorphirJson,
    V0_1_0Draft1,
    V4_0_0,
  )
  assert_eq(tuple.operation.to_string(), "morphir.frontend.compileModel")
  assert_eq(tuple.profile.to_string(), "morphir-ir")
  assert_eq(tuple.codec.to_string(), "morphir-json")
  assert_eq(tuple.envelope_version.to_string(), "0.1.0-draft.1")
  assert_eq(tuple.ir_version.to_string(), "4.0.0")
  assert_eq(
    @worker.ModelTuple::parse(
      "morphir.backend.generateModel", "morphir-model", "ion-binary", "0.1.0-draft.1",
      "4.0.0",
    ),
    @worker.ModelTuple::new(
      GenerateModel,
      MorphirModel,
      IonBinary,
      V0_1_0Draft1,
      V4_0_0,
    ),
  )
  guard (Ok(
      @worker.ModelTuple::parse(
        "morphir.frontend.compileModel", "morphir-ir", "ion-text", "0.1.0-draft.1",
        "4.0.0",
      ),
    ) catch {
      e => Err(e)
    })
    is Err(UnknownModelTuplePart(_)) else {
    fail("accepted an unknown codec")
  }
}
