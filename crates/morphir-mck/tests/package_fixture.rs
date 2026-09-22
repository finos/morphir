// Copyright 2026 FINOS
// SPDX-License-Identifier: Apache-2.0
#[path = "support/package_fixture/mod.rs"]
mod fixture;
use std::{collections::BTreeMap, path::PathBuf};

fn source() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("../..")
        .canonicalize()
        .unwrap()
}

#[test]
fn reproduces_exactly_the_nineteen_frozen_files() {
    let files = fixture::generate(&fixture::read_inputs(&source()).unwrap()).unwrap();
    assert_eq!(files.len(), 19);
    fixture::check_files(&source().join(fixture::SIGNED_PATH), &files).unwrap();
}

#[test]
fn verifies_four_frozen_targets_with_upstream_tuf_at_fixed_time() {
    let files = fixture::read_files(&source().join(fixture::SIGNED_PATH)).unwrap();
    assert_eq!(fixture::verify_tuf(&files, fixture::CLOCK).unwrap(), 4);
}

#[test]
fn authoring_rejects_missing_and_changed_inputs() {
    assert!(fixture::generate(&BTreeMap::new()).is_err());
    let mut inputs = fixture::read_inputs(&source()).unwrap();
    inputs.values_mut().next().unwrap().push(0);
    assert!(fixture::generate(&inputs).is_err());
}

fn temporary() -> tempfile::TempDir {
    tempfile::tempdir_in(std::env::temp_dir().canonicalize().unwrap()).unwrap()
}
fn small_files() -> fixture::Files {
    BTreeMap::from([
        ("keys/publisher.json".into(), b"public\n".to_vec()),
        ("payload.bin".into(), vec![0, 255, 13, 10]),
    ])
}
#[test]
fn output_is_absent_or_empty_and_never_overwrites() {
    let parent = temporary();
    let input = temporary();
    for output in [
        parent.path().to_path_buf(),
        parent.path().join("new/output"),
    ] {
        fixture::write_files(&output, &small_files(), input.path()).unwrap();
        fixture::check_files(&output, &small_files()).unwrap();
        assert!(
            fixture::write_files(
                &output,
                &BTreeMap::from([("replacement".into(), vec![1])]),
                input.path()
            )
            .unwrap_err()
            .to_string()
            .contains("empty")
        );
        assert_eq!(
            std::fs::read(output.join("payload.bin")).unwrap(),
            vec![0, 255, 13, 10]
        );
    }
    assert!(
        fixture::write_files(&input.path().join("."), &small_files(), input.path())
            .unwrap_err()
            .to_string()
            .contains("source")
    );
}
#[test]
fn rejects_noncanonical_paths_before_creating_output() {
    let parent = temporary();
    for path in [
        "../escape",
        "/absolute",
        "a/../escape",
        "a//b",
        "a\\b",
        "./file",
        "",
        "a\0b",
    ] {
        let output = parent.path().join("absent");
        let files = BTreeMap::from([(path.into(), vec![1])]);
        assert!(
            fixture::write_files(&output, &files, parent.path())
                .unwrap_err()
                .to_string()
                .contains("path")
        );
        assert!(!output.exists());
    }
}
#[test]
fn exact_check_rejects_missing_changed_and_extra_entries() {
    for extra in ["extra.json", "keys/README.md", "empty/"] {
        let output = temporary();
        fixture::write_files(output.path(), &small_files(), &source()).unwrap();
        std::fs::write(output.path().join("README.md"), "provenance").unwrap();
        fixture::check_files(output.path(), &small_files()).unwrap();
        if extra.ends_with('/') {
            std::fs::create_dir(output.path().join(extra)).unwrap();
        } else {
            std::fs::write(output.path().join(extra), "unexpected").unwrap();
        }
        assert!(
            fixture::check_files(output.path(), &small_files())
                .unwrap_err()
                .to_string()
                .contains("Unexpected")
        );
    }
    let output = temporary();
    fixture::write_files(output.path(), &small_files(), &source()).unwrap();
    std::fs::write(output.path().join("payload.bin"), [0]).unwrap();
    assert!(
        fixture::check_files(output.path(), &small_files())
            .unwrap_err()
            .to_string()
            .contains("bytes differ")
    );
    std::fs::remove_file(output.path().join("payload.bin")).unwrap();
    assert!(
        fixture::check_files(output.path(), &small_files())
            .unwrap_err()
            .to_string()
            .contains("Missing fixture")
    );
}
#[cfg(unix)]
#[test]
fn rejects_symlink_inputs_outputs_ancestors_and_readmes() {
    use std::os::unix::fs::symlink;
    let parent = temporary();
    let target = temporary();
    let alias = parent.path().join("alias");
    symlink(target.path(), &alias).unwrap();
    assert!(
        fixture::write_files(&alias, &small_files(), &source())
            .unwrap_err()
            .to_string()
            .contains("Symlink")
    );
    assert!(fixture::write_files(&alias.join("nested"), &small_files(), &source()).is_err());
    assert!(fixture::write_files(target.path(), &small_files(), &alias).is_err());
    fixture::write_files(target.path(), &small_files(), &source()).unwrap();
    symlink(
        target.path().join("payload.bin"),
        target.path().join("README.md"),
    )
    .unwrap();
    assert!(fixture::check_files(target.path(), &small_files()).is_err());
    assert!(fixture::read_files(&alias).is_err());
    let source_alias = parent.path().join("source");
    symlink(source(), &source_alias).unwrap();
    assert!(
        fixture::read_inputs(&source_alias)
            .unwrap_err()
            .to_string()
            .contains("Symlink")
    );
}
#[test]
fn fixture_cli_requires_explicit_source_and_one_mode() {
    for args in [
        vec![],
        vec!["--source", "parent"],
        vec!["--output", "out"],
        vec!["--source", "parent", "--output", "out", "--check", "check"],
        vec!["--source", "a", "--source", "b", "--output", "out"],
        vec!["--source", "a", "--output", "--check"],
        vec!["--source", "a", "--other", "b"],
    ] {
        assert!(fixture::parse_arguments(args.into_iter().map(String::from)).is_err());
    }
    let parsed =
        fixture::parse_arguments(["--source", "parent", "--output", "out"].map(String::from))
            .unwrap();
    assert_eq!(parsed.source, PathBuf::from("parent"));
    assert_eq!(
        parsed.destination,
        fixture::Destination::Output(PathBuf::from("out"))
    );
}

mod tuf_negatives {
    use super::*;
    use fixture::{
        ordered::{Json, object},
        signing,
    };
    use serde_json::{Value, json};
    const ROLES: [&str; 4] = ["root", "timestamp", "snapshot", "targets"];
    const AT: &str = "2026-01-01T00:00:00Z";
    fn path(role: &str) -> String {
        format!("registry/metadata/1.{role}.json")
    }
    fn label(role: &str) -> String {
        format!("offline-tuf-test:{role}")
    }
    fn target_path() -> String {
        format!(
            "registry/targets/example/{}.release.json",
            signing::hash(b"a signed fixture target\n")
        )
    }
    fn put(files: &mut fixture::Files, role: &str, signed: Value) {
        files.insert(
            path(role),
            serde_json::to_vec(&signing::tuf(Json::from(signed), &label(role))).unwrap(),
        );
    }
    fn signed(files: &fixture::Files, role: &str) -> Value {
        serde_json::from_slice::<Value>(&files[&path(role)]).unwrap()["signed"].clone()
    }
    fn info(bytes: &[u8]) -> Value {
        json!({"version":1,"length":bytes.len(),"hashes":{"sha256":signing::hash(bytes)}})
    }
    // This small repository is authored independently of generate::generate.
    // Only public deterministic signing primitives are shared with its author.
    fn repository(edit: impl Fn(&str, &mut Value)) -> fixture::Files {
        let target = b"a signed fixture target\n".to_vec();
        let mut files = BTreeMap::from([(target_path(), target.clone())]);
        for role in ["root", "targets", "snapshot", "timestamp"] {
            let mut body = json!({"_type":role,"spec_version":"1.0.36","version":1,"expires":"2027-01-01T00:00:00Z"});
            match role {
                "root" => {
                    body["consistent_snapshot"] = true.into();
                    body["keys"] = serde_json::to_value(Json::Object(
                        ROLES
                            .iter()
                            .map(|r| (signing::key_id(&label(r)), signing::public_tuf(&label(r))))
                            .collect(),
                    ))
                    .unwrap();
                    body["roles"] = serde_json::to_value(Json::Object(ROLES.iter().map(|r|(r.to_string(), object!("keyids" => vec![Json::from(signing::key_id(&label(r)))], "threshold" => 1usize))).collect())).unwrap();
                }
                "targets" => {
                    body["targets"] = json!({"example/release.json":{"length":target.len(),"hashes":{"sha256":signing::hash(&target)}}})
                }
                "snapshot" => body["meta"] = json!({"targets.json":info(&files[&path("targets")])}),
                "timestamp" => {
                    body["meta"] = json!({"snapshot.json":info(&files[&path("snapshot")])})
                }
                _ => unreachable!(),
            }
            edit(role, &mut body);
            put(&mut files, role, body);
        }
        files
    }
    fn relink(files: &mut fixture::Files) {
        for (parent, child) in [("snapshot", "targets"), ("timestamp", "snapshot")] {
            let mut body = signed(files, parent);
            body["meta"][format!("{child}.json")] = info(&files[&path(child)]);
            put(files, parent, body);
        }
    }
    #[test]
    fn independent_repository_is_accepted() {
        assert_eq!(fixture::verify_tuf(&repository(|_, _| {}), AT).unwrap(), 1);
    }
    #[test]
    fn rejects_missing_and_tampered_signatures_in_every_role_after_parent_relink() {
        for role in ROLES {
            for missing in [true, false] {
                let mut files = repository(|_, _| {});
                let mut envelope: Value = serde_json::from_slice(&files[&path(role)]).unwrap();
                envelope["signatures"] = if missing {
                    json!([])
                } else {
                    json!([{"keyid":signing::key_id(&label(role)),"sig":"00".repeat(64)}])
                };
                files.insert(path(role), serde_json::to_vec(&envelope).unwrap());
                if role == "targets" {
                    relink(&mut files);
                }
                if role == "snapshot" {
                    let mut body = signed(&files, "timestamp");
                    body["meta"]["snapshot.json"] = info(&files[&path("snapshot")]);
                    put(&mut files, "timestamp", body);
                }
                let error = fixture::verify_tuf(&files, AT).unwrap_err().to_string();
                assert!(
                    error.to_lowercase().contains("signature"),
                    "{role}: {error}"
                );
            }
        }
    }
    #[test]
    fn rejects_expiration_at_exact_boundary_for_every_role() {
        for role in ROLES {
            let files = repository(|r, body| {
                if r == role {
                    body["expires"] = AT.into();
                }
            });
            fixture::verify_tuf(&files, "2025-12-31T23:59:59.999Z").unwrap();
            let error = fixture::verify_tuf(&files, AT).unwrap_err().to_string();
            assert!(error.to_lowercase().contains("expir"), "{role}: {error}");
        }
    }
    #[test]
    fn rejects_signed_child_version_mismatch_with_valid_hash_links() {
        for role in ["snapshot", "targets"] {
            let files = repository(|r, body| {
                if r == role {
                    body["version"] = 2.into();
                }
            });
            let error = fixture::verify_tuf(&files, AT).unwrap_err().to_string();
            assert!(error.to_lowercase().contains("version"), "{role}: {error}");
        }
    }
    #[test]
    fn rejects_metadata_and_target_hash_length_and_missing_bytes() {
        for item in [path("snapshot"), path("targets"), target_path()] {
            for change in ["hash", "long", "short", "missing"] {
                let mut files = repository(|_, _| {});
                match change {
                    "hash" => {
                        let bytes = files.get_mut(&item).unwrap();
                        let last = bytes.len() - 1;
                        bytes[last] ^= 1;
                    }
                    "long" => files.get_mut(&item).unwrap().push(b' '),
                    "short" => {
                        files.get_mut(&item).unwrap().pop();
                    }
                    _ => {
                        files.remove(&item);
                    }
                }
                assert!(fixture::verify_tuf(&files, AT).is_err(), "{item}: {change}");
            }
        }
    }
    #[test]
    fn rejects_signed_lengths_larger_than_actual_bytes_even_with_matching_hashes() {
        for role in ["timestamp", "snapshot", "targets"] {
            let files = repository(|current, body| {
                if current == role {
                    let info = match role {
                        "timestamp" => &mut body["meta"]["snapshot.json"],
                        "snapshot" => &mut body["meta"]["targets.json"],
                        _ => &mut body["targets"]["example/release.json"],
                    };
                    info["length"] = (info["length"].as_u64().unwrap() + 1).into();
                }
            });
            let error = fixture::verify_tuf(&files, AT).unwrap_err().to_string();
            assert!(error.to_lowercase().contains("length"), "{role}: {error}");
        }
    }

    #[test]
    fn verifies_every_supported_advertised_hash() {
        use sha2::{Digest, Sha512};
        for role in ["timestamp", "snapshot", "targets"] {
            for correct in [true, false] {
                let mut files = repository(|_, _| {});
                let child = match role {
                    "timestamp" => path("snapshot"),
                    "snapshot" => path("targets"),
                    _ => target_path(),
                };
                let actual = Sha512::digest(&files[&child])
                    .iter()
                    .map(|byte| format!("{byte:02x}"))
                    .collect::<String>();
                let mut body = signed(&files, role);
                let info = match role {
                    "timestamp" => &mut body["meta"]["snapshot.json"],
                    "snapshot" => &mut body["meta"]["targets.json"],
                    _ => &mut body["targets"]["example/release.json"],
                };
                info["hashes"]["sha512"] = if correct {
                    actual.into()
                } else {
                    "00".repeat(64).into()
                };
                put(&mut files, role, body);
                if role == "targets" {
                    relink(&mut files);
                }
                if role == "snapshot" {
                    let mut body = signed(&files, "timestamp");
                    body["meta"]["snapshot.json"] = self::info(&files[&path("snapshot")]);
                    put(&mut files, "timestamp", body);
                }
                let result = fixture::verify_tuf(&files, AT);
                if correct {
                    assert_eq!(result.unwrap(), 1);
                } else {
                    assert!(
                        result
                            .unwrap_err()
                            .to_string()
                            .to_lowercase()
                            .contains("hash")
                    );
                }
            }
        }
    }

    #[test]
    fn rejects_morphir_profile_violations() {
        let cases = [
            "spec",
            "consistent",
            "shared",
            "hash",
            "length",
            "additional",
            "path",
            "threshold",
            "zero-version",
        ];
        for case in cases {
            let files = repository(|role, body| match (case, role) {
                ("spec", "targets") => body["spec_version"] = "1.0.35".into(),
                ("consistent", "root") => body["consistent_snapshot"] = false.into(),
                ("shared", "root") => {
                    let definition = body["roles"]["root"].clone();
                    for r in ROLES {
                        body["roles"][r] = definition.clone();
                    }
                }
                ("hash", "timestamp") => {
                    body["meta"]["snapshot.json"]
                        .as_object_mut()
                        .unwrap()
                        .remove("hashes");
                }
                ("length", "snapshot") => {
                    body["meta"]["targets.json"]
                        .as_object_mut()
                        .unwrap()
                        .remove("length");
                }
                ("additional", "snapshot") => body["meta"]["other.json"] = info(b"x"),
                ("path", "targets") => {
                    body["targets"] =
                        json!({"../escape":{"length":1,"hashes":{"sha256":"00".repeat(32)}}})
                }
                ("threshold", "root") => body["roles"]["root"]["threshold"] = 0.into(),
                ("zero-version", "targets") => body["version"] = 0.into(),
                _ => {}
            });
            let error = fixture::verify_tuf(&files, AT).unwrap_err().to_string();
            assert!(error.contains("profile"), "{case}: {error}");
        }
    }
}

mod signing_checks {
    use super::*;
    use base64::{Engine, engine::general_purpose::STANDARD};
    use fixture::{
        ordered::{Json, canonical},
        signing,
    };
    use serde_json::{Value, json};
    #[test]
    fn dsse_frames_byte_lengths_and_keeps_fixed_public_key_derivation() {
        assert_eq!(signing::pae("t", b"{}"), b"DSSEv1 1 t 2 {}");
        assert_eq!(
            signing::pae("é", "é".as_bytes()),
            "DSSEv1 2 é 2 é".as_bytes()
        );
        let description: Value = serde_json::from_slice(
            &std::fs::read(
                source()
                    .join(fixture::SIGNED_PATH)
                    .join("fixture-description.json"),
            )
            .unwrap(),
        )
        .unwrap();
        for entry in description["publicKeys"].as_array().unwrap() {
            assert_eq!(
                signing::public(entry["label"].as_str().unwrap()),
                entry["publicKey"]
            );
        }
    }
    fn envelope(labels: &[&str]) -> Value {
        serde_json::to_value(signing::dsse(b"{}", labels)).unwrap()
    }
    #[test]
    fn independent_dsse_verifier_counts_distinct_authorized_keys() {
        let a = signing::public("publisher-a");
        let b = signing::public("publisher-b");
        let one = envelope(&["publisher-a"]);
        let two = envelope(&["publisher-a", "publisher-b"]);
        assert!(fixture::verify_dsse(&one, std::slice::from_ref(&a), 1));
        assert!(fixture::verify_dsse(&two, &[a.clone(), b], 2));
        assert!(!fixture::verify_dsse(&one, &[a.clone(), a.clone()], 2));
        let mut doubled = one.clone();
        doubled["signatures"]
            .as_array_mut()
            .unwrap()
            .push(one["signatures"][0].clone());
        assert!(!fixture::verify_dsse(&doubled, std::slice::from_ref(&a), 2));
        assert!(!fixture::verify_dsse(&one, &[a], 0));
    }
    #[test]
    fn independent_dsse_verifier_rejects_tampering_and_noncanonical_encoding() {
        let keys = [signing::public("publisher-a")];
        for field in [
            "payload",
            "payloadType",
            "payload-padding",
            "signature-padding",
            "signature-bytes",
        ] {
            let mut value = envelope(&["publisher-a"]);
            match field {
                "payload" => value["payload"] = STANDARD.encode(b"[]").into(),
                "payloadType" => value["payloadType"] = "application/json".into(),
                "payload-padding" => value["payload"] = "e30".into(),
                "signature-padding" => {
                    value["signatures"][0]["sig"] = value["signatures"][0]["sig"]
                        .as_str()
                        .unwrap()
                        .trim_end_matches('=')
                        .into()
                }
                _ => value["signatures"][0]["sig"] = STANDARD.encode([0; 64]).into(),
            }
            assert!(!fixture::verify_dsse(&value, &keys, 1), "{field}");
        }
        let mut value = envelope(&["publisher-a"]);
        value["signatures"][0]["keyid"] = "wrong-hint".into();
        value["signatures"].as_array_mut().unwrap().insert(
            0,
            json!({"keyid":"misleading","sig":STANDARD.encode([0;64])}),
        );
        assert!(fixture::verify_dsse(&value, &keys, 1));
    }
    #[test]
    fn tuf_signing_canonicalizes_nested_objects_and_non_ascii_strings() {
        let signed = Json::from(json!({"z":"é","a":{"n":2,"b":true}}));
        assert_eq!(
            canonical(&signed),
            "{\"a\":{\"b\":true,\"n\":2},\"z\":\"é\"}".as_bytes()
        );
        let envelope =
            serde_json::to_value(signing::tuf(signed.clone(), "repository-root")).unwrap();
        assert_eq!(
            envelope,
            serde_json::to_value(signing::tuf(signed, "repository-root")).unwrap()
        );
        let signature =
            fixture::decode_hex(envelope["signatures"][0]["sig"].as_str().unwrap()).unwrap();
        let public = fixture::decode_hex(&signing::public("repository-root")).unwrap();
        ring::signature::UnparsedPublicKey::new(&ring::signature::ED25519, public)
            .verify(
                "{\"a\":{\"b\":true,\"n\":2},\"z\":\"é\"}".as_bytes(),
                &signature,
            )
            .unwrap();
    }
}

#[test]
fn frozen_artifacts_satisfy_schemas_and_independent_release_relationships() {
    fixture::verify_relationships(
        &source(),
        &fixture::read_files(&source().join(fixture::SIGNED_PATH)).unwrap(),
    )
    .unwrap();
}

#[cfg(unix)]
#[test]
fn output_uses_the_same_normalized_path_that_was_validated() {
    let parent = temporary();
    let target = temporary();
    std::fs::create_dir(target.path().join("nested")).unwrap();
    std::os::unix::fs::symlink(target.path().join("nested"), parent.path().join("alias")).unwrap();
    let output = parent.path().join("alias/../output");
    fixture::write_files(&output, &small_files(), &source()).unwrap();
    assert!(parent.path().join("output/payload.bin").exists());
    assert!(!target.path().join("output").exists());
}

#[test]
fn vendor_is_exact_pinned_upstream_plus_the_reviewed_version_patch() {
    let root = source().join("third_party/rust-tuf");
    let manifest = std::fs::read(root.join("UPSTREAM-SHA256SUMS")).unwrap();
    assert_eq!(
        fixture::signing::hash(&manifest),
        "47b87ccc849744b741c2dc87ebe9f869b58cede9fff0432b07c486a92d2bd259"
    );
    let original_files = String::from_utf8(manifest).unwrap();
    let mut expected: std::collections::BTreeSet<String> = [
        "UPSTREAM-SHA256SUMS",
        "MORPHIR-VENDOR.md",
        "morphir-spec-version.patch",
    ]
    .into_iter()
    .map(String::from)
    .collect();
    for line in original_files.lines() {
        let (hash, path) = line.split_once("  ").unwrap();
        expected.insert(path.to_string());
        let mut bytes = std::fs::read(root.join(path)).unwrap();
        if path == "src/pouf/pouf1/shims.rs" {
            let patched = String::from_utf8(bytes).unwrap();
            assert_eq!(
                patched
                    .matches("matches!(other, \"1.0\" | \"1.0.0\" | \"1.0.36\")")
                    .count(),
                1
            );
            assert_eq!(
                patched
                    .matches("let valid_spec_versions = [\"1.0.0\", \"1.0\", \"1.0.36\"];")
                    .count(),
                1
            );
            bytes = patched
                .replace(
                    "matches!(other, \"1.0\" | \"1.0.0\" | \"1.0.36\")",
                    "matches!(other, \"1.0\" | \"1.0.0\")",
                )
                .replace(
                    "let valid_spec_versions = [\"1.0.0\", \"1.0\", \"1.0.36\"];",
                    "let valid_spec_versions = [\"1.0.0\", \"1.0\"];",
                )
                .into_bytes();
        }
        assert_eq!(
            fixture::signing::hash(&bytes),
            hash,
            "upstream source changed: {path}"
        );
    }
    assert_eq!(
        fixture::read_files(&root)
            .unwrap()
            .into_keys()
            .collect::<std::collections::BTreeSet<_>>(),
        expected
    );
}

#[test]
fn upstream_tuf_is_absent_from_every_production_dependency_path() {
    // Cargo may fetch uncached platform manifests to inspect the complete graph.
    // This Cargo dependency-graph check is separate from offline fixture verification.
    for name in ["morphir-mck", "morphir"] {
        let output = std::process::Command::new(env!("CARGO"))
            .args([
                "tree", "--locked", "-p", name, "--edges", "normal", "--target", "all", "--prefix",
                "none", "--format", "{p}",
            ])
            .current_dir(source())
            .output()
            .unwrap();
        assert!(
            output.status.success(),
            "cargo tree: {}",
            String::from_utf8_lossy(&output.stderr)
        );
        let tree = String::from_utf8(output.stdout).unwrap();
        assert!(tree.starts_with(name), "empty dependency graph");
        assert!(
            !tree.lines().any(|line| line.starts_with("tuf v")),
            "{name} links TUF through a production dependency"
        );
    }
}
