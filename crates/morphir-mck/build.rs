//! Embeds the IR kit: every file under `spec/ir/mck`, every fixture a `text`
//! fence names, and the fixed inputs every snapshot carries, so the packaged CLI checks and runs the kit offline
//! with no checkout. The closure is computed with the crate's own parser,
//! included by path; a kit that does not parse fails the build.

use std::fmt::Write as _;
use std::path::{Path, PathBuf};
use std::process::Command;

#[allow(dead_code)]
#[path = "src/kit/syntax/mod.rs"]
mod syntax;

#[path = "src/kit/closure.rs"]
mod closure;

use syntax::case::parse_kit_file;
use syntax::info_string::Language;

const KIT_PATH: &str = "spec/ir/mck";

fn walk(directory: &Path, prefix: &str, out: &mut Vec<String>) {
    println!("cargo:rerun-if-changed={}", directory.display());
    let mut entries: Vec<_> = std::fs::read_dir(directory)
        .unwrap_or_else(|e| panic!("cannot read {}: {e}", directory.display()))
        .map(|entry| entry.expect("directory entry"))
        .collect();
    entries.sort_by_key(|entry| entry.file_name());
    for entry in entries {
        let key = format!("{prefix}/{}", entry.file_name().to_string_lossy());
        let kind = entry.file_type().expect("file type");
        if kind.is_dir() {
            walk(&entry.path(), &key, out);
        } else if kind.is_file() {
            out.push(key);
        }
    }
}

fn git(repo: &Path, args: &[&str]) -> Option<String> {
    let output = Command::new("git")
        .arg("-C")
        .arg(repo)
        .args(args)
        .output()
        .ok()?;
    output
        .status
        .success()
        .then(|| String::from_utf8_lossy(&output.stdout).trim().to_owned())
}

fn main() {
    let manifest_dir =
        PathBuf::from(std::env::var_os("CARGO_MANIFEST_DIR").expect("CARGO_MANIFEST_DIR"));
    // Not canonicalized: on Windows that yields a verbatim `\\?\` path, which git refuses.
    let repo = manifest_dir
        .ancestors()
        .nth(2)
        .expect("crates/morphir-mck sits two levels below the repository root")
        .to_path_buf();

    let mut keys = Vec::new();
    walk(&repo.join(KIT_PATH), KIT_PATH, &mut keys);

    let case_files: Vec<String> = keys
        .iter()
        .filter(|key| {
            let name = &key[KIT_PATH.len() + 1..];
            !name.contains('/') && name.ends_with(".md") && name != "README.md"
        })
        .cloned()
        .collect();
    for key in &case_files {
        let source = std::fs::read_to_string(repo.join(key))
            .unwrap_or_else(|e| panic!("cannot read {key}: {e}"));
        let parsed = parse_kit_file(key, &source);
        if let Some(error) = parsed.errors.first() {
            panic!(
                "the kit does not parse, so it cannot be embedded: {}:{}: {}",
                error.file, error.line, error.message
            );
        }
        for fence in parsed
            .cases
            .iter()
            .flat_map(|case| &case.fences)
            .filter(|f| f.info.language == Language::Text)
        {
            let target = fence.text_target();
            let confined = !target.starts_with('/')
                && !target.contains('\\')
                && !target.contains(':')
                && target
                    .split('/')
                    .all(|segment| !segment.is_empty() && segment != "." && segment != "..");
            assert!(
                confined,
                "{key}:{}: text fence names {target}, which is not a repository-relative path",
                fence.line
            );
            if !keys.iter().any(|existing| existing == target) {
                keys.push(target.to_owned());
            }
        }
    }

    for fixed in closure::FIXED_INPUTS {
        if !keys.iter().any(|existing| existing == fixed) {
            keys.push((*fixed).to_owned());
        }
    }

    let mut generated = String::new();
    for key in &keys {
        let path = repo.join(key);
        assert!(
            path.is_file(),
            "{key} is named by the kit but is not a file"
        );
        println!("cargo:rerun-if-changed={}", path.display());
    }

    let revision = git(&repo, &["rev-parse", "HEAD"]).filter(|rev| rev.len() == 40);
    let mut status = vec!["status", "--porcelain", "--"];
    status.extend(keys.iter().map(String::as_str));
    // A build that cannot prove its inputs are committed must not claim a clean revision.
    let dirty = revision.is_some() && git(&repo, &status).is_none_or(|changes| !changes.is_empty());
    if let Some(log) = git(&repo, &["rev-parse", "--git-path", "logs/HEAD"]) {
        println!("cargo:rerun-if-changed={}", repo.join(log).display());
    }

    writeln!(
        generated,
        "pub const REVISION: Option<&str> = {revision:?};"
    )
    .unwrap();
    writeln!(generated, "pub const DIRTY: bool = {dirty};").unwrap();
    writeln!(generated, "pub static FILES: &[(&str, &[u8])] = &[").unwrap();
    for key in &keys {
        writeln!(
            generated,
            "    ({key:?}, include_bytes!({:?})),",
            repo.join(key).display().to_string()
        )
        .unwrap();
    }
    writeln!(generated, "];").unwrap();

    let out = PathBuf::from(std::env::var_os("OUT_DIR").expect("OUT_DIR")).join("embedded_kit.rs");
    std::fs::write(&out, generated)
        .unwrap_or_else(|e| panic!("cannot write {}: {e}", out.display()));
}
