//! Embeds the IR kit and its external text fixture so the packaged CLI can
//! check and run it offline. The embedded-kit test checks this inventory.

use std::fmt::Write as _;
use std::path::{Path, PathBuf};
use std::process::Command;

#[path = "src/kit/closure.rs"]
mod closure;

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

    // `distributions.feature` names this repository fixture outside the kit.
    // The embedded-kit test fails if a new text target is omitted here.
    for target in ["website/static/ir/examples/v4/complete-example.json"] {
        if !keys.iter().any(|existing| existing == target) {
            keys.push(target.to_owned());
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
    // The driver's own sources: a build from edited ones must not claim its commit.
    let driver_dirty = revision.is_some()
        && git(
            &repo,
            &[
                "status",
                "--porcelain",
                "--",
                "crates",
                "Cargo.toml",
                "Cargo.lock",
                "ecosystem/morphir-rust",
            ],
        )
        .is_none_or(|changes| !changes.is_empty());
    for watched in [
        "crates",
        "Cargo.toml",
        "Cargo.lock",
        "ecosystem/morphir-rust/crates",
    ] {
        println!("cargo:rerun-if-changed={}", repo.join(watched).display());
    }
    if let Some(log) = git(&repo, &["rev-parse", "--git-path", "logs/HEAD"]) {
        println!("cargo:rerun-if-changed={}", repo.join(log).display());
    }

    writeln!(
        generated,
        "pub const REVISION: Option<&str> = {revision:?};"
    )
    .unwrap();
    writeln!(generated, "pub const DIRTY: bool = {dirty};").unwrap();
    writeln!(generated, "pub const DRIVER_DIRTY: bool = {driver_dirty};").unwrap();
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
