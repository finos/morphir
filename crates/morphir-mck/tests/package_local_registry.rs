use morphir_mck::package::local_registry::{
    RepositorySource, admit_local_registry, inspect_local_registry,
};
use std::path::Path;

#[test]
fn candidate_corpus_is_inspected_but_never_partially_admitted() {
    let root = Path::new(env!("CARGO_MANIFEST_DIR")).join("../..");
    let source = RepositorySource::new(root).unwrap();
    let summary = inspect_local_registry(&source);
    assert!(summary.errors.is_empty(), "{:?}", summary.errors);
    assert_eq!(summary.case_count, 54);
    assert_eq!(summary.bound_asset_count, 6);
    assert_eq!(summary.pending_asset_count, 121);
    assert!(
        admit_local_registry(&source)
            .unwrap_err()
            .join(" ")
            .contains("pending asset")
    );
}

#[path = "support/local_registry/mod.rs"]
mod support;
use serde_json::json;
use support::*;

#[test]
fn definitions_and_full_admission_are_separate() {
    let source = files();
    let summary = inspect_local_registry(&source);
    assert!(summary.errors.is_empty(), "{:?}", summary.errors);
    assert_eq!(
        (
            summary.case_count,
            summary.bound_asset_count,
            summary.pending_asset_count
        ),
        (1, 0, 1)
    );
    assert!(admit_local_registry(&source).is_err());
    assert!(admit_local_registry(&scenario_files()).is_ok());
}
fn rejects(source: &Files) {
    let summary = inspect_local_registry(source);
    assert!(!summary.errors.is_empty());
    assert!(admit_local_registry(source).is_err());
}
#[test]
fn malformed_definition_bindings_and_assertions_are_rejected() {
    for fault in [
        "length",
        "digest",
        "duplicate case",
        "duplicate asset",
        "duplicate path",
        "unknown reference",
        "wrong reference type",
        "invalid calendar",
        "missing parent",
        "hardlink target",
        "contradictory assertions",
        "pointer mismatch",
    ] {
        let mut source = files();
        match fault {
            "length" | "digest" => {
                let path = bind(&mut source, "future", "bytes", vec![0]);
                source.insert(
                    path,
                    if fault == "length" {
                        vec![0, 0]
                    } else {
                        vec![1]
                    },
                );
            }
            "duplicate case" => mutate(&mut source, CASE, |d| {
                let v = d["cases"][0].clone();
                d["cases"].as_array_mut().unwrap().push(v)
            }),
            "duplicate asset" => mutate(&mut source, INDEX, |d| {
                let v = d["assets"][0].clone();
                d["assets"].as_array_mut().unwrap().push(v)
            }),
            "duplicate path" => mutate(&mut source, INDEX, |d| {
                let v = d["fixtures"][0].clone();
                d["fixtures"].as_array_mut().unwrap().push(v)
            }),
            "unknown reference" => mutate(&mut source, CASE, |d| {
                d["cases"][0]["input"] = json!({"kind":"asset","asset":"missing"})
            }),
            "wrong reference type" => {
                bind(
                    &mut source,
                    "future",
                    "tree",
                    encode(&json!({"entries":[]})),
                );
                mutate(&mut source, CASE, |d| {
                    d["cases"][0]["input"] = json!({"kind":"asset","asset":"future"})
                });
            }
            "invalid calendar" => mutate(&mut source, CASE, |d| {
                d["cases"][0]["at"] = json!("2027-02-30T00:00:00Z")
            }),
            "missing parent" => {
                bind(
                    &mut source,
                    "future",
                    "tree",
                    encode(
                        &json!({"entries":[{"kind":"file","path":"absent/file","bytes":{"kind":"hex","value":"00"}}]}),
                    ),
                );
            }
            "hardlink target" => {
                bind(
                    &mut source,
                    "future",
                    "tree",
                    encode(
                        &json!({"entries":[{"kind":"hardlink","path":"file","target":"absent"}]}),
                    ),
                );
            }
            _ => {
                bind(&mut source, "future", "result", encode(&failure()));
                mutate(
                    &mut source,
                    CASE,
                    |d| d["cases"][0]["expected"] = json!({"kind":"asset","asset":"future","assertions":if fault=="pointer mismatch" {json!([{"pointer":"/ok","equals":true}])} else {json!([{"pointer":"/diagnostic","equals":failure()["diagnostic"]},{"pointer":"/diagnostic/code","equals":"release-revoked"}])}}),
                );
            }
        }
        assert!(
            !inspect_local_registry(&source).errors.is_empty(),
            "{fault}"
        );
    }
}
#[test]
fn diagnostic_relationships_are_checked() {
    let diagnostics = [
        json!({"category":"domain-rejection","code":"release-revoked","phase":"authorization","witnesses":[{"kind":"authority","rule":"namespace-denied"}]}),
        json!({"category":"domain-rejection","code":"resource-limit","phase":"bundle","witnesses":[{"kind":"resource","resource":"lock-bytes","scope":"profile","maximum":"16777216","observed":"16777218"}]}),
        json!({"category":"domain-rejection","code":"resource-limit","phase":"bundle","witnesses":[{"kind":"resource","resource":"lock-bytes","scope":"profile","maximum":"1","observed":"2"}]}),
        json!({"category":"invalid-input","code":"resolution-invalid","phase":"graph","witnesses":[{"kind":"resolver","diagnostic":{"code":"incomplete-input","missing":[]}}]}),
        json!({"category":"domain-rejection","code":"metadata-expired","phase":"repository","witnesses":[{"kind":"time","role":"root","at":"2027-01-01T00:00:00Z","boundary":"2028-01-01T00:00:00Z"}]}),
        json!({"category":"domain-rejection","code":"metadata-rollback","phase":"repository","witnesses":[{"kind":"rollback","role":"targets","trusted":"1","received":"1"}]}),
        json!({"category":"domain-rejection","code":"historical-continuity-missing","phase":"repository","witnesses":[{"kind":"continuity","fromVersion":"1","throughVersion":"4","missingVersions":["3","2"]}]}),
        json!({"category":"domain-rejection","code":"publication-conflict","phase":"publication","witnesses":[{"kind":"revision","expected":{"kind":"absent"},"actual":{"kind":"absent"}}]}),
    ];
    for diagnostic in diagnostics {
        let mut source = files();
        mutate(&mut source, CASE, |d| {
            d["cases"][0]["expected"]["result"] = json!({"ok":false,"diagnostic":diagnostic})
        });
        rejects(&source);
    }
}
#[test]
fn scenario_schedule_and_observations_are_checked() {
    for fault in [
        "unknown actor",
        "duplicate operation",
        "missing observation policy",
        "join before start",
        "unreleased barrier",
        "after fault",
        "terminated join",
        "missing tree inventory",
        "wrong result kind",
        "inconsistent graph",
    ] {
        let mut source = scenario_files();
        let checkpoint = json!({"operation":"refresh","boundary":"after","step":"security-state-commit","subject":{"kind":"repository","registry":"finance"}});
        mutate(&mut source, CASE, |d| {
            let s = &mut d["cases"][0];
            match fault {
                "unknown actor" => s["operations"][0]["actor"] = json!("missing"),
                "duplicate operation" => {
                    let v = s["operations"][0].clone();
                    s["operations"].as_array_mut().unwrap().push(v)
                }
                "missing observation policy" => s["observe"]["policies"] = json!([]),
                "join before start" => s["actions"].as_array_mut().unwrap().reverse(),
                "unreleased barrier" | "after fault" | "terminated join" => {
                    s["actions"][0]["barriers"] = json!([checkpoint]);
                    let actions = s["actions"].as_array_mut().unwrap();
                    actions.insert(1, json!({"kind":"await","checkpoint":checkpoint}));
                    if fault == "after fault" {
                        actions.insert(2,json!({"kind":"inject-fault","checkpoint":checkpoint,"action":"state-write","reason":"no-space"}));
                        actions.insert(3, json!({"kind":"release","checkpoint":checkpoint}));
                    }
                    if fault == "terminated join" {
                        actions.insert(2, json!({"kind":"terminate","checkpoint":checkpoint}));
                        s["operations"][0]["expected"] =
                            json!({"kind":"terminated","checkpoint":checkpoint});
                    }
                }
                "wrong result kind" => {
                    s["operations"][0]["expected"]["result"] = json!({"ok":true,"kind":"publication","outcome":"committed","timestampDigest":format!("sha256:{}","0".repeat(64))})
                }
                "inconsistent graph" => {
                    s["operations"][0]["name"] = json!("resolve-library");
                    s["operations"][0]["input"] = json!({"root":{"packagePath":"example.com/root","version":"1.0.0"},"registries":["finance"]});
                    s["operations"][0]["expected"]["result"] = json!({"ok":true,"kind":"graph-ready","graph":{"root":s["operations"][0]["input"]["root"],"nodes":[]},"verified":[]});
                }
                _ => {}
            }
        });
        if fault == "missing tree inventory" {
            observation(&mut source, |o| {
                o["filesystems"].as_array_mut().unwrap().pop();
            });
        }
        assert!(
            !inspect_local_registry(&source).errors.is_empty(),
            "{fault}"
        );
    }
}

#[test]
fn consumed_raw_files_and_transitive_schemas_define_identity() {
    let source = scenario_files();
    let kit = admit_local_registry(&source).unwrap();
    use morphir_mck::kit::hash::content_hash;
    assert_eq!(
        kit.content_hash(),
        &content_hash(source.iter().map(|(p, b)| (p.as_str(), b.as_slice())))
    );
    for name in [INDEX, CASE, SCHEMA, "spec/package/mck/README.md"] {
        let mut next = source.clone();
        next.get_mut(name).unwrap().push(b'\n');
        assert_ne!(
            admit_local_registry(&next).unwrap().content_hash(),
            kit.content_hash()
        );
    }
    let mut next = source.clone();
    let id = "https://morphir.finos.org/spec/package/0.1.0-draft.1/library-manifest.schema.json";
    mutate(&mut next, SCHEMA, |s| {
        s["$defs"]["Index"]["allOf"] = json!([{"$ref":format!("{id}#/$defs/IndexExtension")}])
    });
    let name = "spec/package/schemas/library-manifest.schema.json";
    next.insert(
        name.into(),
        encode(&json!({"$id":id,"$defs":{"IndexExtension":{"type":"object"}}})),
    );
    let first = admit_local_registry(&next).unwrap();
    assert_eq!(
        first.content_hash(),
        &content_hash(next.iter().map(|(p, b)| (p.as_str(), b.as_slice())))
    );
    next.get_mut(name).unwrap().push(b'\n');
    assert_ne!(
        first.content_hash(),
        admit_local_registry(&next).unwrap().content_hash()
    );
    next.remove(name);
    rejects(&next);
}
#[test]
fn schema_catalog_is_offline_and_validates_complete_results() {
    for property in ["$id", "$ref"] {
        let mut source = files();
        mutate(&mut source, SCHEMA, |s| {
            s[property] = json!("https://unregistered.invalid/schema")
        });
        assert!(
            inspect_local_registry(&source)
                .errors
                .join(" ")
                .contains("unknown local schema ID")
        );
    }
    let mut source = files();
    mutate(&mut source, CASE, |d| {
        d["cases"][0]["expected"]["result"]["diagnostic"]
            .as_object_mut()
            .unwrap()
            .remove("witnesses");
    });
    assert!(
        inspect_local_registry(&source)
            .errors
            .join(" ")
            .contains("Result")
    );
}
#[test]
fn raw_asset_bytes_are_owned_and_excluded_assets_are_inaccessible() {
    let mut source = files();
    let raw = vec![0xef, 0xbb, 0xbf, 0xff, 0x0a];
    let name = bind(&mut source, "future", "bytes", raw.clone());
    mutate(&mut source, CASE, |d| {
        d["cases"][0]["input"] = json!({"kind":"asset","asset":"future"})
    });
    let admitted = admit_local_registry(&source).unwrap();
    let case = &admitted.cases()[0];
    source.get_mut(&name).unwrap().fill(0);
    assert_eq!(case.asset_bytes("future").unwrap(), raw);
    assert!(case.asset_bytes("outside").is_err());
    let mut definition = case.definition().clone();
    definition["id"] = json!("changed");
    let mut expectations = case.expectations().clone();
    expectations.get_mut(case.id()).unwrap()["ok"] = json!(true);
    assert_eq!(case.id(), "local-registry.wire.raw");
    assert_eq!(case.expectations()[case.id()], failure());
    rejects(&source);
}
#[test]
fn observation_snapshot_has_its_own_namespace() {
    let mut source = scenario_files();
    mutate(&mut source, CASE, |d| {
        d["cases"][0]["operations"][0]["id"] = json!("observations");
        for action in d["cases"][0]["actions"].as_array_mut().unwrap() {
            action["operation"] = json!("observations");
        }
    });
    let kit = admit_local_registry(&source).unwrap();
    let case = &kit.cases()[0];
    assert_eq!(case.expectations()["observations"], failure());
    assert_eq!(
        case.observations().unwrap()["security"][0]["actor"],
        "client"
    );
}
#[test]
fn publication_rollback_equal_floor_is_valid_but_other_equal_floors_are_not() {
    let mut source = scenario_files();
    bind(
        &mut source,
        "rollback",
        "result",
        encode(
            &json!({"ok":false,"diagnostic":{"category":"domain-rejection","code":"metadata-rollback","phase":"publication","witnesses":[{"kind":"rollback","registry":"finance","role":"targets","trusted":"2","received":"2"}]}}),
        ),
    );
    mutate(&mut source, CASE, |d| {
        let op = &mut d["cases"][0]["operations"][0];
        op["name"] = json!("publish-library");
        op["input"] = json!({"registry":"finance","bundle":{"asset":"future"},"record":{"kind":"hex","value":"00"},"envelope":{"kind":"hex","value":"00"},"predecessor":{"kind":"hex","value":"00"},"proposal":{"asset":"future"}});
        op["expected"] = json!({"kind":"asset","asset":"rollback","assertions":[{"pointer":"/ok","equals":false}]});
    });
    assert!(admit_local_registry(&source).is_ok());
    mutate(&mut source, CASE, |d| {
        d["cases"][0]["operations"][0]["name"] = json!("restore-library")
    });
    rejects(&source);
}
#[test]
fn diagnostic_quoted_invalid_calendar_is_data_and_later_authorization_time_is_retained() {
    let mut source = files();
    mutate(&mut source, CASE, |d| {
        d["cases"][0]["expected"]["result"]["diagnostic"] = json!({"category":"unsupported-capability","code":"unsupported-profile","phase":"support","witnesses":[{"kind":"unsupported","subject":{"kind":"lock"},"pointer":"/kind","value":"2027-02-30T00:00:00Z"}]})
    });
    assert!(inspect_local_registry(&source).errors.is_empty());
    let mut source = scenario_files();
    observation(&mut source, |o| {
        o["security"][0]["repositories"][0]["lastFreshAuthorization"] =
            json!({"kind":"at","time":"2027-01-02T00:00:00Z"})
    });
    assert!(admit_local_registry(&source).is_ok());
}
#[test]
fn logical_aliases_are_distinct_from_physical_registry_roots() {
    let mut source = scenario_files();
    let name = "spec/package/mck/fixtures/local-registry/assets/configuration.json";
    let mut config: serde_json::Value = serde_json::from_slice(&source[name]).unwrap();
    config["bindings"][0]["registryRoot"] = json!("finance-root");
    bind(
        &mut source,
        "configuration",
        "configuration",
        encode(&config),
    );
    observation(&mut source, |o| {
        o["registries"][0]["registry"] = json!("finance-root");
        o["filesystems"][2]["root"]["owner"] = json!("finance-root");
    });
    mutate(&mut source, CASE, |d| {
        let s = &mut d["cases"][0];
        s["setup"]["registries"][0]["id"] = json!("finance-root");
        let cp = json!({"operation":"refresh","boundary":"before","step":"security-state-commit","subject":{"kind":"repository","registry":"finance"}});
        s["actions"][0]["barriers"] = json!([cp]);
        let a = s["actions"].as_array_mut().unwrap();
        a.insert(1, json!({"kind":"await","checkpoint":cp}));
        a.insert(2, json!({"kind":"release","checkpoint":cp}));
    });
    assert!(admit_local_registry(&source).is_ok());
    mutate(&mut source, CASE, |d| {
        d["cases"][0]["operations"][0]["input"]["registry"] = json!("finance-root")
    });
    assert!(
        inspect_local_registry(&source)
            .errors
            .join(" ")
            .contains("alias")
    );
}

#[test]
fn writer_lock_checkpoints_require_repository_subjects() {
    let root = Path::new(env!("CARGO_MANIFEST_DIR")).join("../..");
    let schema: serde_json::Value =
        serde_json::from_slice(&std::fs::read(root.join(SCHEMA)).unwrap()).unwrap();
    let checkpoint_schema = json!({
        "$defs": {
            "Id": schema["$defs"]["Id"],
            "Step": schema["$defs"]["Step"],
            "Subject": schema["$defs"]["Subject"],
            "Checkpoint": schema["$defs"]["Checkpoint"]
        },
        "$ref": "#/$defs/Checkpoint"
    });
    let validator = jsonschema::validator_for(&checkpoint_schema).unwrap();
    for boundary in ["before", "after"] {
        for subject in [
            json!({"kind":"repository","registry":"finance"}),
            json!({"kind":"lock"}),
            json!({"kind":"policy"}),
            json!({"kind":"request"}),
            json!({"kind":"object","registry":"finance","path":"metadata/timestamp.json"}),
        ] {
            let checkpoint = json!({"operation":"refresh","boundary":boundary,"step":"writer-lock","subject":subject});
            assert!(validator.is_valid(&checkpoint), "{checkpoint}");
            let mut source = scenario_files();
            mutate(&mut source, CASE, |doc| {
                let scenario = &mut doc["cases"][0];
                let operation = &mut scenario["operations"][0];
                operation["name"] = json!("publish-library");
                operation["input"] = json!({"registry":"finance","bundle":{"asset":"future"},"record":{"kind":"hex","value":"00"},"envelope":{"kind":"hex","value":"00"},"predecessor":{"kind":"hex","value":"00"},"proposal":{"asset":"future"}});
                scenario["actions"] = json!([
                    {"kind":"start","operation":"refresh","barriers":[checkpoint]},
                    {"kind":"await","checkpoint":checkpoint},
                    {"kind":"release","checkpoint":checkpoint},
                    {"kind":"join","operation":"refresh"}
                ]);
            });
            let summary = inspect_local_registry(&source);
            if subject["kind"] == "repository" {
                assert!(summary.errors.is_empty(), "{:?}", summary.errors);
                assert!(admit_local_registry(&source).is_ok());
            } else {
                assert!(
                    summary
                        .errors
                        .join(" ")
                        .contains("writer-lock checkpoint requires repository subject"),
                    "{checkpoint}: {:?}",
                    summary.errors
                );
                assert!(admit_local_registry(&source).is_err());
            }
        }
    }
}

#[test]
fn fatal_diagnostics_require_exactly_one_witness() {
    for code in ["resource-limit", "io-failure", "unsafe-path"] {
        let mut source = scenario_files();
        let witness = match code {
            "resource-limit" => {
                json!({"kind":"resource","subject":{"kind":"policy"},"resource":"policy-bytes","scope":"profile","maximum":"1048576","observed":"1048577"})
            }
            "io-failure" => {
                json!({"kind":"io","subject":{"kind":"lock"},"action":"open","reason":"permission"})
            }
            _ => json!({"kind":"path","subject":{"kind":"lock"},"rule":"escape"}),
        };
        mutate(&mut source, CASE, |d| {
            d["cases"][0]["operations"][0]["expected"]["result"] = json!({"ok":false,"diagnostic":{"category":if code=="io-failure" {"operational-failure"}else{"domain-rejection"},"code":code,"phase":"repository","witnesses":[witness,witness]}})
        });
        assert!(
            inspect_local_registry(&source)
                .errors
                .join(" ")
                .contains("one witness")
        );
    }
}
#[test]
fn cache_projection_excludes_private_paths_and_incomplete_bundles() {
    for path in [
        "private-index.json".to_owned(),
        "metadata".to_owned(),
        format!("bundles/{}", "0".repeat(64)),
    ] {
        let mut source = scenario_files();
        observation(&mut source, |o| {
            o["filesystems"][0]["entries"] = if path.starts_with("bundles/") {
                json!([{"kind":"directory","path":"bundles"},{"kind":"directory","path":path}])
            } else {
                json!([{"kind":"file","path":path,"length":"0","sha256":digest(b"")}])
            }
        });
        assert!(
            inspect_local_registry(&source)
                .errors
                .join(" ")
                .contains("cache")
        );
    }
}
#[test]
fn confined_paths_missing_files_and_duplicate_decoded_members_are_rejected() {
    for path in [
        "/absolute",
        "fixtures/local-registry/cases/../test.json",
        "fixtures/local-registry/cases//test.json",
        "fixtures/local-registry/cases/a\\b.json",
        "fixtures/local-registry/assets/test.json",
    ] {
        let mut source = files();
        mutate(&mut source, INDEX, |i| i["fixtures"] = json!([path]));
        rejects(&source);
    }
    for bytes in [
        b"{\"fixtures\":[],\"fixtures\":[]}".to_vec(),
        b"{\"fixtures\":[],\"\\u0066ixtures\":[]}".to_vec(),
        vec![0xff],
        b"\xef\xbb\xbf{}".to_vec(),
    ] {
        let mut source = files();
        source.insert(INDEX.into(), bytes);
        rejects(&source);
    }
    let mut source = files();
    source.remove(CASE);
    rejects(&source);
}
#[cfg(unix)]
#[test]
fn repository_source_rejects_missing_bytes_and_symlink_escape() {
    let root = tempfile::tempdir().unwrap();
    let outside = tempfile::tempdir().unwrap();
    let source = scenario_files();
    for (name, bytes) in &source {
        let path = root.path().join(name);
        std::fs::create_dir_all(path.parent().unwrap()).unwrap();
        std::fs::write(path, bytes).unwrap();
    }
    let source = RepositorySource::new(root.path()).unwrap();
    assert!(admit_local_registry(&source).is_ok());
    let name = root
        .path()
        .join("spec/package/mck/fixtures/local-registry/assets/future.json");
    std::fs::remove_file(&name).unwrap();
    assert!(admit_local_registry(&source).is_err());
    let target = outside.path().join("tree.json");
    std::fs::write(&target, encode(&json!({"entries":[]}))).unwrap();
    std::os::unix::fs::symlink(target, name).unwrap();
    assert!(
        inspect_local_registry(&source)
            .errors
            .join(" ")
            .contains("confined")
    );
}

#[test]
fn official_schemas_reject_pending_claims_and_unknown_fields() {
    use morphir_mck::package::local_registry::CorpusSource;
    struct Overlay {
        repository: RepositorySource,
        files: Files,
    }
    impl CorpusSource for Overlay {
        fn read(&self, name: &str) -> Result<Vec<u8>, String> {
            self.files
                .get(name)
                .cloned()
                .map(Ok)
                .unwrap_or_else(|| self.repository.read(name))
        }
    }
    for fault in [
        "pending hash",
        "pending path",
        "unknown field",
        "wrong version",
    ] {
        let repository =
            RepositorySource::new(Path::new(env!("CARGO_MANIFEST_DIR")).join("../..")).unwrap();
        let mut index: serde_json::Value =
            serde_json::from_slice(&repository.read(INDEX).unwrap()).unwrap();
        match fault {
            "pending hash" | "pending path" => {
                let pending = index["assets"]
                    .as_array_mut()
                    .unwrap()
                    .iter_mut()
                    .find(|a| a["kind"] == "pending")
                    .unwrap();
                if fault == "pending hash" {
                    pending["sha256"] = json!(digest(b""));
                } else {
                    pending["path"] = json!("fixtures/local-registry/assets/fake.json");
                }
            }
            "unknown field" => index["invented"] = json!(true),
            _ => index["formatVersion"] = json!("0.1.0-draft.2"),
        }
        let overlay = Overlay {
            repository,
            files: Files::from([(INDEX.into(), encode(&index))]),
        };
        let summary = inspect_local_registry(&overlay);
        assert!(!summary.errors.is_empty(), "{fault}");
        assert_eq!(summary.case_count, 0);
        assert!(admit_local_registry(&overlay).is_err());
    }
}

#[test]
fn remaining_witness_relationships_reject_impossible_claims() {
    for (code, witness) in [
        (
            "unauthorized-publisher",
            json!({"kind":"repository-authority","rule":"repository-unconfigured"}),
        ),
        (
            "publisher-threshold-unmet",
            json!({"kind":"authentication","verified":"2","required":"2"}),
        ),
        (
            "digest-mismatch",
            json!({"kind":"digest","expected":"a","actual":"a"}),
        ),
        (
            "length-mismatch",
            json!({"kind":"length","expected":"1","actual":"1"}),
        ),
        (
            "record-replacement-unsupported",
            json!({"kind":"replacement","existing":"a","proposed":"a"}),
        ),
        (
            "publication-conflict",
            json!({"kind":"immutable","existing":"a","proposed":"a"}),
        ),
        (
            "historical-continuity-missing",
            json!({"kind":"continuity","fromVersion":"2","throughVersion":"5","missingVersions":["1"]}),
        ),
        (
            "trusted-time-unavailable",
            json!({"kind":"time","role":"clock","at":"2027-01-02T00:00:00Z","boundary":"2027-01-01T00:00:00Z"}),
        ),
        (
            "conflicting-views",
            json!({"kind":"views","snapshots":["z","a"]}),
        ),
        (
            "catalog-conflict",
            json!({"kind":"catalog","candidates":[{"repository":"z","snapshot":"a","record":"a"},{"repository":"a","snapshot":"a","record":"a"}]}),
        ),
        (
            "publication-conflict",
            json!({"kind":"release-conflict","existingManifest":"a","proposedManifest":"a","existingContent":"b","proposedContent":"b"}),
        ),
    ] {
        let mut source = files();
        mutate(
            &mut source,
            CASE,
            |d| d["cases"][0]["expected"]["result"] = json!({"ok":false,"diagnostic":{"category":if code=="record-replacement-unsupported" {"unsupported-capability"}else{"domain-rejection"},"code":code,"phase":"publication","witnesses":[witness]}}),
        );
        rejects(&source);
    }
}
#[test]
fn caller_resource_limits_and_resolver_witness_order_are_preserved() {
    let mut source = scenario_files();
    mutate(&mut source, CASE, |d| {
        let op = &mut d["cases"][0]["operations"][0];
        op["limits"] = json!([{"resource":"lock-bytes","maximum":"5"}]);
        op["expected"]["result"] = json!({"ok":false,"diagnostic":{"category":"domain-rejection","code":"resource-limit","phase":"bundle","witnesses":[{"kind":"resource","resource":"lock-bytes","scope":"caller","maximum":"5","observed":"6"}]}});
    });
    assert!(admit_local_registry(&source).is_ok());
    mutate(&mut source, CASE, |d| {
        d["cases"][0]["operations"][0]["limits"][0]["maximum"] = json!("4")
    });
    rejects(&source);
    let mut source = files();
    mutate(
        &mut source,
        CASE,
        |d| d["cases"][0]["expected"]["result"] = json!({"ok":false,"diagnostic":{"category":"invalid-input","code":"resolution-invalid","phase":"graph","witnesses":[{"kind":"resolver","diagnostic":{"code":"invalid-input","violations":[{"pointer":"/a","rule":"invalid-value"},{"pointer":"/b","rule":"invalid-value"}]}}]}}),
    );
    assert!(inspect_local_registry(&source).errors.is_empty());
    mutate(&mut source, CASE, |d| {
        d["cases"][0]["expected"]["result"]["diagnostic"]["witnesses"][0]["diagnostic"]["violations"].as_array_mut().unwrap().reverse()
    });
    rejects(&source);
}
#[test]
fn graph_success_must_match_requested_root_verified_releases_and_observations() {
    let mut source = scenario_files();
    let release = json!({"packagePath":"example.com/root","version":"1.0.0"});
    let hash = digest(b"");
    let graph = json!({"root":release,"nodes":[{"release":release,"irPackageName":"root","manifestDigest":hash,"contentDigest":hash,"bindings":[]}]});
    mutate(&mut source, CASE, |d| {
        let op = &mut d["cases"][0]["operations"][0];
        op["name"] = json!("resolve-library");
        op["input"] = json!({"root":release,"registries":["finance"]});
        op["expected"]["result"] =
            json!({"ok":true,"kind":"graph-ready","graph":graph,"verified":[release]});
    });
    mutate(&mut source, CASE, |d| {
        d["cases"][0]["expectedObservations"]["assertions"] = json!([])
    });
    observation(&mut source, |o| {
        o["readyGraphs"] = json!([{"operation":"refresh","releases":[release]}])
    });
    assert!(
        admit_local_registry(&source).is_ok(),
        "{:?}",
        inspect_local_registry(&source).errors
    );
    for fault in ["root", "verified", "observations"] {
        let mut next = source.clone();
        match fault {
            "root" => mutate(&mut next, CASE, |d| {
                d["cases"][0]["operations"][0]["input"]["root"]["version"] = json!("2.0.0")
            }),
            "verified" => mutate(&mut next, CASE, |d| {
                d["cases"][0]["operations"][0]["expected"]["result"]["verified"] = json!([])
            }),
            _ => observation(&mut next, |o| o["readyGraphs"] = json!([])),
        }
        rejects(&next);
    }
}
