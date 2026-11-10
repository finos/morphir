//! `contract-files.json` lists every file an implementation pins. These tests
//! keep it complete: every listed path exists, every toolchain page and
//! schema is listed, and every repository file a pinned page links to is
//! pinned or listed as a reference with its reason.

use serde_json::Value;
use std::collections::BTreeSet;
use std::path::{Component, Path, PathBuf};

fn repository() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../..")
}

fn manifest() -> Value {
    let path = repository().join("docs/spec/toolchain/fixtures/0.1.0-draft.1/contract-files.json");
    serde_json::from_slice(&std::fs::read(&path).unwrap()).unwrap()
}

fn strings(value: &Value) -> Vec<String> {
    value
        .as_array()
        .unwrap()
        .iter()
        .map(|item| item.as_str().unwrap().to_owned())
        .collect()
}

/// Resolve `..` and `.` without touching the file system.
fn normalize(path: &Path) -> String {
    let mut parts: Vec<String> = Vec::new();
    for component in path.components() {
        match component {
            Component::ParentDir => {
                assert!(
                    parts.pop().is_some(),
                    "{} leaves the repository",
                    path.display()
                );
            }
            Component::Normal(part) => parts.push(part.to_string_lossy().into_owned()),
            _ => {}
        }
    }
    parts.join("/")
}

/// The repository paths that a Markdown page links to.
fn local_links(page: &str) -> Vec<String> {
    let text = std::fs::read_to_string(repository().join(page)).unwrap();
    let directory = Path::new(page).parent().unwrap();
    let mut links = Vec::new();
    let mut rest = text.as_str();
    while let Some(start) = rest.find("](") {
        rest = &rest[start + 2..];
        let end = rest.find(')').unwrap();
        let target = rest[..end].split('#').next().unwrap().trim();
        rest = &rest[end..];
        if target.is_empty() || target.contains("://") || target.starts_with("mailto:") {
            continue;
        }
        let resolved = if let Some(schema) = target.strip_prefix("/schemas/") {
            format!("website/static/schemas/{schema}")
        } else {
            assert!(
                !target.starts_with('/'),
                "{page} links to the site route {target}; link the file instead"
            );
            normalize(&directory.join(target))
        };
        links.push(resolved);
    }
    links
}

#[test]
fn every_listed_path_exists() {
    let manifest = manifest();
    assert_eq!(manifest["contractVersion"], "0.1.0-draft.1");
    for tree in strings(&manifest["trees"]) {
        assert!(repository().join(&tree).is_dir(), "{tree}");
    }
    for file in strings(&manifest["files"]) {
        assert!(repository().join(&file).is_file(), "{file}");
    }
    for reference in manifest["references"].as_array().unwrap() {
        let path = reference["path"].as_str().unwrap();
        assert!(repository().join(path).is_file(), "{path}");
        assert!(!reference["reason"].as_str().unwrap().trim().is_empty());
    }
}

#[test]
fn every_toolchain_page_and_schema_is_pinned() {
    let files = strings(&manifest()["files"])
        .into_iter()
        .collect::<BTreeSet<_>>();
    let pages = std::fs::read_dir(repository().join("docs/spec/toolchain"))
        .unwrap()
        .map(|entry| entry.unwrap().file_name().to_string_lossy().into_owned())
        .filter(|name| name.ends_with(".md"))
        .map(|name| format!("docs/spec/toolchain/{name}"));
    let schemas = std::fs::read_dir(repository().join("website/static/schemas"))
        .unwrap()
        .map(|entry| entry.unwrap().file_name().to_string_lossy().into_owned())
        .filter(|name| name.ends_with("-0.1.0-draft.1.schema.json"))
        .filter(|name| {
            ["toolset-recipe-", "toolchain-", "morphirup-"]
                .iter()
                .any(|prefix| name.starts_with(prefix))
        })
        .map(|name| format!("website/static/schemas/{name}"));
    let mut seen = 0;
    for path in pages.chain(schemas) {
        assert!(
            files.contains(&path),
            "{path} is not in contract-files.json"
        );
        seen += 1;
    }
    assert_eq!(seen, 13, "seven pages and six schemas");
}

#[test]
fn every_linked_repository_file_is_pinned_or_referenced() {
    let manifest = manifest();
    let trees = strings(&manifest["trees"]);
    let files = strings(&manifest["files"])
        .into_iter()
        .collect::<BTreeSet<_>>();
    let references = manifest["references"]
        .as_array()
        .unwrap()
        .iter()
        .map(|reference| reference["path"].as_str().unwrap().to_owned())
        .collect::<BTreeSet<_>>();
    let mut failures = Vec::new();
    for page in files.iter().filter(|file| file.ends_with(".md")) {
        for link in local_links(page) {
            let pinned = files.contains(&link)
                || trees
                    .iter()
                    .any(|tree| link == *tree || link.starts_with(&format!("{tree}/")));
            if !pinned && !references.contains(&link) {
                failures.push(format!("{page} links to {link}"));
            }
        }
    }
    assert!(failures.is_empty(), "{}", failures.join("\n"));
}
