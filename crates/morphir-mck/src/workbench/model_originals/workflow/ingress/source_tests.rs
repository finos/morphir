//! Actual bounded corpus file acquisition retains the source for borrowed views.
use super::*;
use crate::workbench::corpus::CorpusSource;

const RAW: &str = include_str!("controls/corpus.json");

#[test]
fn actual_file_source_keeps_exact_bytes_after_the_selected_file_changes() {
    let root = tempfile::tempdir().unwrap();
    let path = root.path().join("cases.json");
    std::fs::write(&path, RAW).unwrap();
    let source = CorpusSource::load(root.path()).unwrap();
    assert_eq!(source.bytes(), RAW.as_bytes());
    assert_eq!(
        crate::kit::hash::sha256_hex(source.bytes()),
        "0ff73a3105fc564b449b0bf3bc6baffe54645ea7e84eb73813d0a015af570f50"
    );
    std::fs::write(&path, "false").unwrap();
    std::fs::remove_file(&path).unwrap();
    let mut decoder = Decoder::new(
        super::super::DecodeLimits::new(1_048_576, 67_108_864, 1_000_000, 67_108_864, 1_000_000)
            .unwrap(),
    );
    let bound = BoundCorpus::decode(source.text(), &mut decoder).unwrap();
    assert_eq!(bound.raw().as_ptr(), source.bytes().as_ptr());
    assert_eq!(bound.cases()[0].id(), "case-A");
    assert!(bound.cases()[0].paired().is_ok());
    for token in [
        bound.cases()[0].input_token(),
        bound.cases()[0].expected_token(),
    ] {
        let start = token
            .as_ptr()
            .addr()
            .checked_sub(source.bytes().as_ptr().addr())
            .unwrap();
        assert_eq!(source.text().get(start..start + token.len()), Some(token));
    }
}

#[test]
fn actual_corpus_source_rejects_nonfiles_oversized_files_and_invalid_utf8() {
    let root = tempfile::tempdir().unwrap();
    let path = root.path().join("cases.json");
    std::fs::create_dir(&path).unwrap();
    assert!(CorpusSource::load(root.path()).is_err());
    std::fs::remove_dir(&path).unwrap();
    let file = std::fs::File::create(&path).unwrap();
    file.set_len(16 * 1024 * 1024 + 1).unwrap();
    assert!(CorpusSource::load(root.path()).is_err());
    std::fs::write(&path, [0xff, 0xfe]).unwrap();
    assert!(CorpusSource::load(root.path()).is_err());
}
