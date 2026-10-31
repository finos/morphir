///|
/// The Python extension modules: MORPHIR_PYTHON_EXTENSIONS names a directory
/// with `0.4.1/` and `0.4.2/`, each holding the release's
/// `morphir-python-binding-<version>.wasm`.
fn python_module(version : String) -> Bytes? raise {
  guard @env.get_env_var("MORPHIR_PYTHON_EXTENSIONS") is Some(root) else {
    return None
  }
  Some(
    @fs.read_file_to_bytes(
      "\{root}/\{version}/morphir-python-binding-\{version}.wasm",
    ),
  )
}

///|
test "ABI classification: the Python extension 0.4.1 and 0.4.2 are extism-kernel-v1" {
  for version in ["0.4.1", "0.4.2"] {
    guard python_module(version) is Some(bytes) else { return }
    let module_ = @wasm.WasmModule::read(bytes)
    assert_eq(module_.classify(), ExtismKernelV1)
    assert_eq(module_.classify(declared=ExtismKernelV1), ExtismKernelV1)
    // The module declares no memory maximum; the rewrite gives it 256 MiB.
    guard module_.memories() is [memory] else { fail("not one memory") }
    assert_eq(memory.maximum, None)
    let capped = module_.with_memory_ceiling(@wasm.MemoryCeiling::restricted())
    guard capped.memories() is [capped_memory] else { fail("not one memory") }
    assert_eq(capped_memory.maximum, Some(4096L))
  }
}

///|
/// The claims that a guest describes in a probe.
fn described(guest : &@guest.Guest) -> @worker.Claims {
  let (conversation, step) = @worker.Conversation::probe()
  let (_, step) = drive(guest, conversation, step)
  guard step is Finished(Described(description), ..) else {
    abort("the guest did not describe itself: \{@debug.to_string(step)}")
  }
  description.claims
}

///|
test "Extism kernel adapter: Python compile is one handle call per request on one instance" {
  for version in ["0.4.1", "0.4.2"] {
    guard python_module(version) is Some(bytes) else { return }
    let (probe, _) = load_extism(bytes)
    let claims = described(probe)
    assert_eq(claims.extension_id.to_string(), "morphir-python")
    assert_eq(claims.version.to_string(), version)
    // An operation session: initialize, initialized, compile, shutdown, exit.
    let (guest, _) = load_extism(bytes)
    let (conversation, step) = @worker.Conversation::activate(
      Legacy,
      expected=claims,
    )
    let (conversation, step) = drive(guest, conversation, step)
    guard step is Activated(_, ..) else {
      fail("activation failed: \{@debug.to_string(step)}")
    }
    let request = @worker.CompileRequest::new({
      "languageId": "python",
      "sources": {
        "documents": [
          {
            "uri": "file:///work/acme/models.py",
            "languageId": "python",
            "version": 1,
            "text": "from dataclasses import dataclass\n\n@dataclass(frozen=True)\nclass Approved:\n    amount: float\n",
          },
        ],
      },
      "package": { "name": "acme" },
      "dependencies": [],
      "options": { "irVersion": "4", "typesOnly": false },
    })
    let (conversation, step) = conversation.compile(request)
    let (conversation, step) = drive(guest, conversation, step)
    guard step is Answered(answer, ..) else {
      fail("the compile was not answered: \{@debug.to_string(step)}")
    }
    guard answer.class is Completed(result) else {
      fail("the compile did not complete: \{@debug.to_string(answer)}")
    }
    let ir = result.stringify()
    assert_true(ir.contains("\"approved\"") && ir.contains("\"amount\""))
    let (closing, step) = conversation.close()
    let (_, step) = drive(guest, closing, step)
    assert_true(step is Finished(Closed, ..))
  }
}
