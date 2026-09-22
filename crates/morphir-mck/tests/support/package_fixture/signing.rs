// Copyright 2026 FINOS
// SPDX-License-Identifier: Apache-2.0
//! Public test seeds only. No developer keys, stores, or production credentials.
use super::ordered::{Json, canonical, object};
use base64::{Engine, engine::general_purpose::STANDARD};
use ed25519_dalek::{Signer, SigningKey};
use sha2::{Digest, Sha256};
pub const PAYLOAD_TYPE: &str = "application/vnd.morphir.library-release.v0.1.0-draft.3+json";
pub fn hex(bytes: &[u8]) -> String {
    bytes.iter().map(|b| format!("{b:02x}")).collect()
}
pub fn hash(bytes: &[u8]) -> String {
    hex(&Sha256::digest(bytes))
}
pub fn digest(bytes: &[u8]) -> String {
    format!("sha256:{}", hash(bytes))
}
pub fn key(label: &str) -> SigningKey {
    SigningKey::from_bytes(&Sha256::digest(format!("morphir-mck-fixture:{label}")).into())
}
pub fn public(label: &str) -> String {
    hex(key(label).verifying_key().as_bytes())
}
pub fn public_tuf(label: &str) -> Json {
    object!("keytype" => "ed25519", "scheme" => "ed25519", "keyval" => object!("public" => public(label)))
}
pub fn key_id(label: &str) -> String {
    hash(&canonical(&public_tuf(label)))
}
pub fn tuf(signed: Json, label: &str) -> Json {
    let signature = hex(&key(label).sign(&canonical(&signed)).to_bytes());
    object!("signed" => signed, "signatures" => vec![object!("keyid" => key_id(label), "sig" => signature)])
}
pub fn dsse(payload: &[u8], labels: &[&str]) -> Json {
    let pae = pae(PAYLOAD_TYPE, payload);
    object!("payloadType" => PAYLOAD_TYPE, "payload" => STANDARD.encode(payload), "signatures" => labels.iter().map(|label| {
        object!("keyid" => public(label), "sig" => STANDARD.encode(key(label).sign(&pae).to_bytes()))
    }).collect::<Vec<_>>())
}
pub fn metadata_link(bytes: &[u8]) -> Json {
    object!("version" => 1usize, "length" => bytes.len(), "hashes" => object!("sha256" => hash(bytes)))
}
pub fn pae(payload_type: &str, payload: &[u8]) -> Vec<u8> {
    let mut result = format!(
        "DSSEv1 {} {} {} ",
        payload_type.len(),
        payload_type,
        payload.len()
    )
    .into_bytes();
    result.extend_from_slice(payload);
    result
}
