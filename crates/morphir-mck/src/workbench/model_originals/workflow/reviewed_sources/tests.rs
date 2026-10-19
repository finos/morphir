use super::*;

#[test]
fn chained_test_replacements_retain_both_packet_and_receipt_bytes() {
    let packet = b"changed packet bytes";
    let receipt = b"changed receipt bytes";
    let supplied = ReviewedSources::selected()
        .with_replacement("preceding60.json", packet)
        .with_replacement("acceptance/provenance.json", receipt);
    assert_eq!(supplied.acceptance_receipt(), receipt);
    let file = supplied
        .files()
        .find(|file| file.path() == "preceding60.json")
        .unwrap();
    assert!(
        file.bytes() == packet,
        "both supplied replacements must remain selected"
    );
    let selected = ReviewedSources::selected();
    assert_ne!(selected.acceptance_receipt(), receipt);
    assert_ne!(
        selected
            .files()
            .find(|file| file.path() == "preceding60.json")
            .unwrap()
            .bytes(),
        packet
    );
}

#[test]
fn selected_views_cover_all_manifest_paths_without_duplicate_file_names() {
    let selected = ReviewedSources::selected();
    let mut paths = std::collections::BTreeSet::new();
    for file in selected.files() {
        assert!(paths.insert(file.path()));
        assert!(!file.bytes().is_empty());
    }
    assert_eq!(paths.len(), 70);
    assert!(paths.contains("wire49.json"));
    assert!(paths.contains("connected-expected-v17-migration-v1/cases/connected-inventory-single-file-json-v3/input.json"));
}
