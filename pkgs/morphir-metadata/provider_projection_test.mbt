///|
/// Interoperability data from the shared checked projection profile.
/// Source: finos/morphir-rust 3b55adfa831c6dcfb749e4e74c301e924124490c
/// crates/morphir-package/tests/local_registry/naming-snapshot-fixture The Rust
/// fixture authenticates the signed release; this test supplies a simulated host
/// capability and qualifies data consumption, not signature verification here.
const SHARED_NATIVE_REVISION : String = "870af5f51087dfe6a13fdf10c3b856d879b53d650982612a7aede276060c0720"

///|
fn shared_native_payload() -> String {
  (
    #|{
    #|  "formatVersion": "4.1.0",
    #|  "distribution": {
    #|    "Library": {
    #|      "packageName": "morphir/naming",
    #|      "dependencies": {},
    #|      "def": {
    #|        "modules": {
    #|          "naming": {
    #|            "Public": {
    #|              "types": {},
    #|              "values": {
    #|                "target-names": {
    #|                  "Public": {
    #|                    "ExpressionBody": {
    #|                      "inputTypes": {},
    #|                      "outputType": {
    #|                        "Record": {
    #|                          "fields": {
    #|                            "frontend": {
    #|                              "Reference": {
    #|                                "fqname": "morphir/SDK:dict#dict",
    #|                                "args": [
    #|                                  "morphir/SDK:string#string",
    #|                                  "morphir/SDK:string#string"
    #|                                ]
    #|                              }
    #|                            },
    #|                            "backend": {
    #|                              "Reference": {
    #|                                "fqname": "morphir/SDK:dict#dict",
    #|                                "args": [
    #|                                  "morphir/SDK:string#string",
    #|                                  "morphir/SDK:string#string"
    #|                                ]
    #|                              }
    #|                            }
    #|                          }
    #|                        }
    #|                      },
    #|                      "body": {
    #|                        "Record": {
    #|                          "fields": {
    #|                            "frontend": {
    #|                              "Reference": {
    #|                                "fqname": "morphir/SDK:dict#empty"
    #|                              }
    #|                            },
    #|                            "backend": {
    #|                              "Reference": {
    #|                                "fqname": "morphir/SDK:dict#empty"
    #|                              }
    #|                            }
    #|                          }
    #|                        }
    #|                      }
    #|                    }
    #|                  }
    #|                }
    #|              }
    #|            }
    #|          }
    #|        }
    #|      }
    #|    }
    #|  },
    #|  "$meta": {
    #|    "@context": "./contexts/schema.jsonld",
    #|    "@graph": [
    #|      {
    #|        "@id": "morphir://ir/pkg/morphir/naming?format=4.1.0#/module/naming/value/target-names",
    #|        "subject-role": "ValueDefinition",
    #|        "object-form": "data",
    #|        "interpreter": "target-name-language-ids"
    #|      }
    #|    ]
    #|  }
    #|}
  )
}

///|
fn shared_core_projection() -> String {
  (
    #|{"formatVersion":4,"distribution":{"Library":{"packageName":"morphir/naming","dependencies":{},"def":{"modules":{"naming":{"Public":{"types":{},"values":{"target-names":{"Public":{"ExpressionBody":{"inputTypes":{},"outputType":{"Record":{"fields":{"frontend":{"Reference":["morphir/SDK:dict#dict","morphir/SDK:string#string","morphir/SDK:string#string"]},"backend":{"Reference":["morphir/SDK:dict#dict","morphir/SDK:string#string","morphir/SDK:string#string"]}}}},"body":{"Record":{"fields":{"frontend":{"Reference":"morphir/SDK:dict#empty"},"backend":{"Reference":"morphir/SDK:dict#empty"}}}}}}}}}}}}}}}
  )
}

///|
fn shared_native_metadata() -> String {
  (
    #|{
    #|    "@context": "./contexts/schema.jsonld",
    #|    "@graph": [
    #|      {
    #|        "@id": "morphir://ir/pkg/morphir/naming?format=4.1.0#/module/naming/value/target-names",
    #|        "subject-role": "ValueDefinition",
    #|        "object-form": "data",
    #|        "interpreter": "target-name-language-ids"
    #|      }
    #|    ]
    #|  }
  )
}

///|
fn shared_native_context() -> String {
  (
    #|{
    #|  "@context": {"@vocab": "morphir://ir/pkg/morphir/metadata?format=4.1.0#/module/schema/value/"}
    #|}
    #|
  )
}

///|
fn shared_projected_provider() -> @metadata.RestoredLibrary raise {
  {
    core: @ir_json.read(shared_core_projection()),
    format: "4.1.0",
    revision: SHARED_NATIVE_REVISION,
    document: "morphir://ir/pkg/morphir/naming?format=4.1.0&rev=sha256:" +
    SHARED_NATIVE_REVISION +
    "#/distribution",
    document_metadata: @ion_json.read_json(shared_native_metadata()[:]),
  }
}

///|
test "shared signed fixture projection supplies native naming declarations" {
  let restores = Ref(0)
  let contexts = Ref(0)
  let capabilities : @metadata.Capabilities = {
    restore_library: Some(fn(predicate) raise {
      assert_eq(predicate, @metadata.TARGET_NAMES_PREDICATE)
      restores.val += 1
      shared_projected_provider()
    }),
    load_context: Some(fn(resource, base) raise {
      assert_eq(resource, "./contexts/schema.jsonld")
      assert_true(base.contains(SHARED_NATIVE_REVISION))
      contexts.val += 1
      {
        url: "fixture://naming/contexts/schema.jsonld",
        bytes: @utf8.encode(shared_native_context()),
        sha256: "01a54bdd5624d57b003d6196e97c0f94c5a37a0c77e4303834775cd72e8bf1d7",
      }
    }),
    target_names_interpreter: true,
  }
  let data = @fixtures.adapter("[" + @fixtures.row("ready") + "]")
  let result = @metadata.interpret(
    @fixtures.input(),
    "sample",
    [{ node_id: "value:example:main#ready", data, }],
    capabilities~,
  )
  assert_eq(restores.val, 1)
  assert_eq(contexts.val, 1)
  assert_eq(result.facts.length(), 1)
  assert_eq(result.facts[0].names.backend["moonbit"], "wanted")
  assert_eq(result.facts[0].provider_revision, SHARED_NATIVE_REVISION)
}

///|
test "shared native revision hashes original payload rather than its core projection" {
  let native = @crypto.bytes_to_hex_string(
    @crypto.sha256(@utf8.encode(shared_native_payload())),
  )
  let projected = @crypto.bytes_to_hex_string(
    @crypto.sha256(@utf8.encode(shared_core_projection())),
  )
  assert_eq(native, SHARED_NATIVE_REVISION)
  assert_not_eq(projected, SHARED_NATIVE_REVISION)
  assert_eq(shared_projected_provider().format, "4.1.0")
}
