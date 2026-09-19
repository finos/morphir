//! `mck-file-map-sha256/1`: a reproducible digest of a file map, independent
//! of git and of the platform. See `spec/mck/kit-manifest.md`.
//!
//! ```text
//! line(path) = UTF-8(path) || 0x00 || lowercase-hex(SHA-256(bytes)) || 0x0A
//! digest     = "sha256-" || lowercase-hex(SHA-256(lines, paths in UTF-16 order))
//! ```

use std::fmt;

use sha2::{Digest, Sha256};

use super::syntax::text::utf16_cmp;

pub const ALGORITHM: &str = "mck-file-map-sha256/1";

/// A `sha256-<64 hex>` digest of a file map.
#[derive(Debug, Clone, PartialEq, Eq, Hash)]
pub struct ContentDigest(String);

impl ContentDigest {
    /// Accepts exactly `sha256-` followed by 64 lowercase hex digits.
    pub fn parse(text: &str) -> Result<Self, String> {
        match text.strip_prefix("sha256-") {
            Some(hex) if is_sha256_hex(hex) => Ok(Self(text.to_owned())),
            _ => Err(format!(
                "\"{text}\" is not a sha256-<64 lowercase hex> digest"
            )),
        }
    }

    pub fn as_str(&self) -> &str {
        &self.0
    }
}

impl fmt::Display for ContentDigest {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(&self.0)
    }
}

/// 64 lowercase hex digits: a SHA-256 as the digest lines spell it.
pub fn is_sha256_hex(text: &str) -> bool {
    text.len() == 64
        && text
            .bytes()
            .all(|b| b.is_ascii_digit() || (b'a'..=b'f').contains(&b))
}

pub fn sha256_hex(bytes: &[u8]) -> String {
    hex(&Sha256::digest(bytes))
}

fn hex(bytes: &[u8]) -> String {
    bytes.iter().map(|byte| format!("{byte:02x}")).collect()
}

/// The digest of `files`, given as `(repository-relative path, bytes)`. The
/// order of `files` does not matter; a path listed twice is hashed twice, so
/// callers pass a map's entries.
pub fn content_hash<'a>(files: impl IntoIterator<Item = (&'a str, &'a [u8])>) -> ContentDigest {
    let hashed: Vec<(&str, String)> = files
        .into_iter()
        .map(|(path, bytes)| (path, sha256_hex(bytes)))
        .collect();
    digest_of_hashes(hashed.iter().map(|(path, hash)| (*path, hash.as_str())))
}

/// The same digest from each file's SHA-256 hex, as a manifest inventory
/// records it, so a manifest can be checked without its files.
pub fn digest_of_hashes<'a>(files: impl IntoIterator<Item = (&'a str, &'a str)>) -> ContentDigest {
    let mut files: Vec<_> = files.into_iter().collect();
    files.sort_by(|a, b| utf16_cmp(a.0, b.0));
    let mut outer = Sha256::new();
    for (path, hash) in files {
        outer.update(path.as_bytes());
        outer.update([0]);
        outer.update(hash.as_bytes());
        outer.update(b"\n");
    }
    ContentDigest(format!("sha256-{}", hex(&outer.finalize())))
}

#[cfg(test)]
mod tests {
    use serde::Deserialize;

    use super::*;

    #[derive(Deserialize)]
    struct Vectors {
        algorithm: String,
        vectors: Vec<Vector>,
    }

    #[derive(Deserialize)]
    #[serde(rename_all = "camelCase")]
    struct Vector {
        name: String,
        files: Vec<VectorFile>,
        sorted_paths: Vec<String>,
        content_hash: String,
    }

    #[derive(Deserialize)]
    struct VectorFile {
        path: String,
        text: String,
    }

    /// The literal vectors frozen from the TypeScript driver, including the
    /// pair whose UTF-16 order is the reverse of its code-point order.
    #[test]
    fn matches_the_frozen_baseline_vectors() {
        let raw = include_str!("../../../../spec/mck/baseline/hash-vectors.json");
        let vectors: Vectors = serde_json::from_str(raw.trim_start_matches('\u{FEFF}')).unwrap();
        assert_eq!(vectors.algorithm, ALGORITHM);
        assert!(vectors.vectors.iter().any(|v| v.name == "utf16-order"));
        for vector in vectors.vectors {
            let digest = content_hash(
                vector
                    .files
                    .iter()
                    .map(|f| (f.path.as_str(), f.text.as_bytes())),
            );
            assert_eq!(
                digest.as_str(),
                vector.content_hash,
                "vector {}",
                vector.name
            );

            let mut paths: Vec<&str> = vector.files.iter().map(|f| f.path.as_str()).collect();
            paths.sort_by(|a, b| utf16_cmp(a, b));
            assert_eq!(paths, vector.sorted_paths, "vector {}", vector.name);
        }
    }

    #[test]
    fn digest_of_hashes_agrees_with_content_hash() {
        let files = [("b", b"2".as_slice()), ("a", b"1".as_slice())];
        let hashes: Vec<(&str, String)> = files.iter().map(|(p, b)| (*p, sha256_hex(b))).collect();
        assert_eq!(
            digest_of_hashes(hashes.iter().map(|(p, h)| (*p, h.as_str()))),
            content_hash(files)
        );
    }

    #[test]
    fn parse_accepts_only_the_canonical_spelling() {
        let good = content_hash([("a", b"1".as_slice())]);
        assert_eq!(ContentDigest::parse(good.as_str()), Ok(good.clone()));
        for bad in [
            "sha256-",
            "sha256-XYZ",
            "sha512-00",
            &good.as_str().to_uppercase(),
            &format!("{good}0"),
        ] {
            assert!(ContentDigest::parse(bad).is_err(), "{bad}");
        }
    }

    #[test]
    fn is_sensitive_to_bytes_and_paths() {
        let base = content_hash([("a", b"1".as_slice())]);
        assert_ne!(base, content_hash([("a", b"2".as_slice())]));
        assert_ne!(base, content_hash([("b", b"1".as_slice())]));
    }
}
