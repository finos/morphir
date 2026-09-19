//! Differential test against the TypeScript kit parser this crate replaces.
//!
//! `spec/mck/baseline/kit-cases.json` freezes that parser's reading of the
//! real corpus, per case file. Every file whose bytes still match the frozen
//! digest must parse to exactly the same cases here. A file edited since the
//! baseline is skipped, because the old parser's answer for it is unknown.

use std::path::Path;

use morphir_mck::kit::hash::sha256_hex;
use morphir_mck::kit::syntax::case::{Compare, KitCase, Status, parse_kit_file};
use serde_json::{Value, json};

fn as_json(case: &KitCase) -> Value {
    let fences: Vec<Value> = case
        .fences
        .iter()
        .map(|fence| {
            let keys: serde_json::Map<String, Value> =
                ["warning", "diagnostic", "expect", "path", "set", "mode"]
                    .into_iter()
                    .filter_map(|key| Some((key.to_owned(), json!(fence.info.key(key)?))))
                    .collect();
            json!({
                "language": fence.info.language.as_str(),
                "role": fence.info.role.as_str(),
                "keys": keys,
                "body": fence.body,
                "line": fence.line,
                "index": fence.index,
            })
        })
        .collect();
    json!({
        "id": case.id.as_str(),
        "topic": case.topic,
        "number": case.number,
        "title": case.title,
        "node": case.node,
        "version": case.version,
        "status": match case.status { Status::Active => "active", Status::Pending => "pending" },
        "compare": match case.compare { Compare::Stripped => "stripped", Compare::Attributes => "attributes" },
        "prose": case.prose,
        "line": case.line,
        "fences": fences,
    })
}

#[test]
fn unchanged_case_files_parse_exactly_as_the_typescript_parser_read_them() {
    let repo = Path::new(env!("CARGO_MANIFEST_DIR")).join("../..");
    let raw = std::fs::read_to_string(repo.join("spec/mck/baseline/kit-cases.json")).unwrap();
    let baseline: Value = serde_json::from_str(raw.trim_start_matches('\u{FEFF}')).unwrap();

    let mut compared = 0;
    for file in baseline["files"].as_array().unwrap() {
        let path = file["path"].as_str().unwrap();
        let bytes = std::fs::read(repo.join(path)).unwrap();
        if sha256_hex(&bytes) != file["sha256"].as_str().unwrap() {
            eprintln!("skipping {path}: edited since the baseline");
            continue;
        }
        let parsed = parse_kit_file(path, std::str::from_utf8(&bytes).unwrap());
        assert_eq!(parsed.errors, vec![], "{path}");
        let expected = file["cases"].as_array().unwrap();
        assert_eq!(parsed.cases.len(), expected.len(), "{path}: case count");
        for (actual, expected) in parsed.cases.iter().zip(expected) {
            assert_eq!(&as_json(actual), expected, "{path}: {}", actual.id);
            compared += 1;
        }
    }
    eprintln!("compared {compared} cases with the TypeScript parser");
}
