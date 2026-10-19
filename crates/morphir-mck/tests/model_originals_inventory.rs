//! Independent inventory controls. These establish checker behavior, not host qualification.
use morphir_mck::workbench::model_originals::{Inventory, InventoryError};
use serde_json::{Value, json};
use sha2::{Digest, Sha256};

const PACKET: &str =
    include_str!("../../../spec/workbench/model-originals/0.1.0-draft.1/acceptance/wire49.json");

fn fixture() -> (Value, Vec<Value>) {
    let packet: Value = serde_json::from_str(PACKET).unwrap();
    (
        packet["cases"][0]["expected"]["summary"].clone(),
        packet["cases"][1]["expected"]["completeEntries"]
            .as_array()
            .unwrap()
            .clone(),
    )
}

// This test-side encoder follows the public preimage, independently of the checker.
// Re-signing mutations lets individual controls exercise more than digest mismatch.
fn resign(summary: &mut Value, entries: &[Value]) {
    let mut digest = Sha256::new();
    digest.update(b"morphir/workbench/model-originals/0.1.0-draft.1\0");
    digest.update(u32::try_from(entries.len()).unwrap().to_be_bytes());
    let mut files = 0;
    let mut bytes = 0;
    for entry in entries {
        let file = entry["kind"] == "file";
        digest.update([u8::from(file)]);
        let path = entry["path"].as_str().unwrap().as_bytes();
        digest.update(u32::try_from(path.len()).unwrap().to_be_bytes());
        digest.update(path);
        if file {
            files += 1;
            let length = entry["byteLength"].as_u64().unwrap();
            bytes += length;
            digest.update(length.to_be_bytes());
            let hex = entry["sha256"].as_str().unwrap();
            for offset in (0..64).step_by(2) {
                digest.update([u8::from_str_radix(&hex[offset..offset + 2], 16).unwrap()]);
            }
        }
    }
    summary["inventory"] = json!({"entryCount":entries.len(),"fileCount":files,
        "directoryCount":entries.len()-files,"sourceByteLength":bytes,
        "sha256":digest.finalize().iter().map(|byte|format!("{byte:02x}")).collect::<String>()});
}

fn check(summary: &Value, entries: &[Value]) -> Result<Inventory, InventoryError> {
    let frames = entries.iter().map(Value::to_string).collect::<Vec<_>>();
    let frames = frames.iter().map(String::as_str).collect::<Vec<_>>();
    Inventory::parse(&summary.to_string(), &frames)
}
fn accepts(summary: &Value, entries: &[Value]) -> bool {
    check(summary, entries).is_ok()
}

#[test]
fn original_frozen_inventory_and_digest_are_accepted_without_erasing_empty_directories() {
    let (summary, entries) = fixture();
    let frames = entries.iter().map(Value::to_string).collect::<Vec<_>>();
    let frames = frames.iter().map(String::as_str).collect::<Vec<_>>();
    let inventory = Inventory::parse(&summary.to_string(), &frames).unwrap();
    assert_eq!(inventory.entries().len(), 4);
    assert_eq!(inventory.source_byte_length(), 120);
    assert_eq!(
        inventory.digest().to_hex(),
        "8ae541eb3e9c3da4ee65f45ec6d5a39d5431c1e0032d0756030dc7a8fa8466b2"
    );
}

#[test]
fn omission_extra_entries_counts_and_digest_are_independent_controls() {
    let (summary, entries) = fixture();
    let mut omitted = entries.clone();
    omitted.remove(2);
    assert!(!accepts(&summary, &omitted));
    let mut extra = entries.clone();
    extra.push(json!({"kind":"directory","entryId":"outside","path":"outside"}));
    let mut claimed = summary.clone();
    resign(&mut claimed, &extra);
    assert!(matches!(
        check(&claimed, &extra),
        Err(InventoryError::Coverage)
    ));
    for key in [
        "entryCount",
        "fileCount",
        "directoryCount",
        "sourceByteLength",
    ] {
        let mut wrong = summary.clone();
        wrong["inventory"][key] = json!(0);
        assert!(!accepts(&wrong, &entries), "accepted wrong {key}");
    }
    let mut wrong = summary;
    wrong["inventory"]["sha256"] = json!("0".repeat(64));
    assert!(matches!(
        check(&wrong, &entries),
        Err(InventoryError::Digest)
    ));
}

#[test]
fn unique_ids_order_and_file_prefixes_are_checked_even_with_a_valid_digest() {
    let (summary, entries) = fixture();
    let mut duplicate = entries.clone();
    duplicate[1]["entryId"] = duplicate[0]["entryId"].clone();
    assert!(matches!(
        check(&summary, &duplicate),
        Err(InventoryError::DuplicateIdentity)
    ));
    let mut wrong_order = entries.clone();
    wrong_order.swap(1, 2);
    let mut claimed = summary.clone();
    resign(&mut claimed, &wrong_order);
    assert!(matches!(
        check(&claimed, &wrong_order),
        Err(InventoryError::Ordering)
    ));
    let mut under_file = entries;
    under_file.insert(
        1,
        json!({"kind":"directory","entryId":"child","path":"morphir-ir.json/child"}),
    );
    resign(&mut claimed, &under_file);
    assert!(matches!(
        check(&claimed, &under_file),
        Err(InventoryError::PathSet)
    ));
}

#[test]
fn required_directory_roots_and_descendant_ancestors_cannot_be_implicit() {
    let (mut summary, mut entries) = fixture();
    entries.remove(1);
    resign(&mut summary, &entries);
    assert!(matches!(
        check(&summary, &entries),
        Err(InventoryError::Coverage)
    ));
    let (mut summary, mut entries) = fixture();
    entries[3]["path"] = json!("notes/missing/opaque.bin");
    resign(&mut summary, &entries);
    assert!(matches!(
        check(&summary, &entries),
        Err(InventoryError::Coverage)
    ));
    // Ancestors outside a selected root are implicit and do not enter the inventory.
    let (mut summary, mut entries) = fixture();
    summary["primary"]["path"] = json!("packages/morphir-ir.json");
    entries[0]["path"] = json!("packages/morphir-ir.json");
    entries.sort_by(|a, b| a["path"].as_str().cmp(&b["path"].as_str()));
    resign(&mut summary, &entries);
    assert!(accepts(&summary, &entries));
}

#[test]
fn normalized_directory_prefix_aliases_and_portable_device_names_are_rejected() {
    for path in [
        "Notes/opaque.bin",
        "notes/CON.txt",
        "notes/COM¹.txt",
        "notes/trailing.",
        "notes/../escape",
    ] {
        let (mut summary, mut entries) = fixture();
        entries[3]["path"] = json!(path);
        entries.sort_by(|a, b| a["path"].as_str().cmp(&b["path"].as_str()));
        resign(&mut summary, &entries);
        assert!(!accepts(&summary, &entries), "accepted {path}");
    }
    let (mut summary, entries) = fixture();
    summary["companions"]
        .as_array_mut()
        .unwrap()
        .push(json!({"kind":"directory","path":"NOTES/other"}));
    assert!(matches!(
        check(&summary, &entries),
        Err(InventoryError::PathSet)
    ));
}

#[test]
fn utf8_order_is_distinct_from_utf16_order() {
    let (mut summary, mut entries) = fixture();
    entries[2]["path"] = json!("notes/\u{e000}");
    entries[3]["path"] = json!("notes/\u{10000}");
    resign(&mut summary, &entries);
    assert!(accepts(&summary, &entries));
    entries.swap(2, 3);
    resign(&mut summary, &entries);
    assert!(!accepts(&summary, &entries));
}

#[test]
fn root_depth_and_descendant_depth_are_separate_inclusive_limits() {
    let (mut summary, _) = fixture();
    let root = vec!["a"; 128].join("/");
    summary["primary"] = json!({"kind":"directory","path":root});
    summary["companions"] = json!([]);
    let mut entries = vec![json!({"kind":"directory","entryId":"root","path":root})];
    let mut path = root;
    for depth in 1..=128 {
        path.push_str("/a");
        entries.push(json!({"kind":"directory","entryId":format!("level-{depth}"),"path":path}));
    }
    resign(&mut summary, &entries);
    assert!(accepts(&summary, &entries));
    path.push_str("/a");
    entries.push(json!({"kind":"directory","entryId":"too-deep","path":path}));
    resign(&mut summary, &entries);
    assert!(!accepts(&summary, &entries));
}

#[test]
fn exact_numeric_and_literal_boundaries_precede_schema_float_limits() {
    let (summary, entries) = fixture();
    let raw_entries = entries.iter().map(Value::to_string).collect::<Vec<_>>();
    let frames = raw_entries.iter().map(String::as_str).collect::<Vec<_>>();
    for number in [
        "100064.00000000000000001",
        "1e100000",
        "-1",
        "{\"$serde_json::private::Number\":\"4\"}",
    ] {
        let raw = summary.to_string().replacen(
            "\"entryCount\":4",
            &format!("\"entryCount\":{number}"),
            1,
        );
        assert!(
            Inventory::parse(&raw, &frames).is_err(),
            "accepted {number}"
        );
    }
    let duplicate = raw_entries[0].replacen(
        "\"kind\":\"file\"",
        "\"kind\":\"file\",\"kind\":\"file\"",
        1,
    );
    let mut altered = frames.clone();
    altered[0] = &duplicate;
    assert!(Inventory::parse(&summary.to_string(), &altered).is_err());
    let huge = raw_entries[0].replacen("\"byteLength\":116", "\"byteLength\":1e100000", 1);
    altered[0] = &huge;
    assert!(Inventory::parse(&summary.to_string(), &altered).is_err());
    for needle in ["\"byteLength\":370", "\"byteLength\":111", "\"schema\":1"] {
        let key = needle.split(':').next().unwrap();
        let raw = summary
            .to_string()
            .replacen(needle, &format!("{key}:1e100000"), 1);
        assert!(Inventory::parse(&raw, &frames).is_err());
    }
}

#[test]
fn content_and_inventory_hashes_have_separate_roles_and_ids_are_not_hashed() {
    let (mut summary, mut entries) = fixture();
    entries[0]["entryId"] = json!("different-valid-id");
    assert!(accepts(&summary, &entries));
    summary["inventory"]["sha256"] = entries[0]["sha256"].clone();
    assert!(!accepts(&summary, &entries));
}

#[test]
fn source_byte_limit_is_aggregate_and_inclusive() {
    let (mut summary, mut entries) = fixture();
    entries[0]["byteLength"] = json!(67108864);
    entries[3]["byteLength"] = json!(0);
    resign(&mut summary, &entries);
    assert!(accepts(&summary, &entries));
    entries[3]["byteLength"] = json!(1);
    // Leave a legal claimed summary so the computed aggregate is the refusal.
    assert!(matches!(
        check(&summary, &entries),
        Err(InventoryError::SourceBudget)
    ));
}

#[test]
fn normalization_generated_separators_do_not_hide_a_prefix_alias() {
    let (mut summary, mut entries) = fixture();
    // The middle normalized path has no raw component boundary at a/b.
    // It must not make the checker forget the spelling seen on its predecessor.
    for (index, path) in ["notes/a/b/x", "notes/a／b／y", "notes/a／b/z"]
        .iter()
        .enumerate()
    {
        entries.push(json!({"kind":"directory","entryId":format!("alias-{index}"),"path":path}));
    }
    entries.sort_by(|a, b| a["path"].as_str().cmp(&b["path"].as_str()));
    resign(&mut summary, &entries);
    assert!(matches!(
        check(&summary, &entries),
        Err(InventoryError::PathSet)
    ));
}

#[test]
fn malformed_variants_do_not_expose_schema_numeric_panics() {
    let (summary, entries) = fixture();
    let huge: Value = serde_json::from_str("1e100000").unwrap();
    let mut directory = entries.clone();
    directory[0]["kind"] = json!("directory");
    directory[0]["byteLength"] = huge.clone();
    assert!(!accepts(&summary, &directory));
    let mut origin = summary.clone();
    origin["origin"]["kind"] = json!("legacy-json");
    origin["origin"]["record"]["byteLength"] = huge.clone();
    assert!(!accepts(&origin, &entries));
    let mut projection = summary;
    projection["projection"]["status"] = json!("not-requested");
    projection["projection"]["byteLength"] = huge;
    assert!(!accepts(&projection, &entries));
}
