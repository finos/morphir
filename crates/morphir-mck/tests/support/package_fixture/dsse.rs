// Copyright 2026 FINOS
// SPDX-License-Identifier: Apache-2.0
//! Independent ring verification; never imports the generator's signing or PAE.
use base64::{Engine, engine::general_purpose::STANDARD};
use serde_json::Value;
use std::collections::BTreeSet;
const PAYLOAD_TYPE: &str = "application/vnd.morphir.library-release.v0.1.0-draft.3+json";
pub fn decode_hex(value: &str) -> Option<Vec<u8>> {
    if !value.len().is_multiple_of(2)
        || !value
            .bytes()
            .all(|b| b.is_ascii_digit() || (b'a'..=b'f').contains(&b))
    {
        return None;
    }
    value
        .as_bytes()
        .as_chunks::<2>()
        .0
        .iter()
        .map(|pair| u8::from_str_radix(std::str::from_utf8(pair).ok()?, 16).ok())
        .collect()
}
fn base64(value: &Value) -> Option<Vec<u8>> {
    let text = value.as_str()?;
    let bytes = STANDARD.decode(text).ok()?;
    (STANDARD.encode(&bytes) == text).then_some(bytes)
}
pub fn verify_dsse(envelope: &Value, authorized: &[String], threshold: usize) -> bool {
    if threshold < 1 || envelope["payloadType"] != PAYLOAD_TYPE {
        return false;
    }
    let Some(payload) = base64(&envelope["payload"]) else {
        return false;
    };
    let Some(signatures) = envelope["signatures"].as_array() else {
        return false;
    };
    let signatures: Vec<_> = signatures
        .iter()
        .filter_map(|s| base64(&s["sig"]))
        .filter(|s| s.len() == 64)
        .collect();
    let mut pae = format!(
        "DSSEv1 {} {} {} ",
        PAYLOAD_TYPE.len(),
        PAYLOAD_TYPE,
        payload.len()
    )
    .into_bytes();
    pae.extend(payload);
    let distinct: BTreeSet<_> = authorized
        .iter()
        .filter_map(|k| decode_hex(k))
        .filter(|k| k.len() == 32)
        .collect();
    distinct
        .iter()
        .filter(|key| {
            signatures.iter().any(|sig| {
                ring::signature::UnparsedPublicKey::new(&ring::signature::ED25519, key)
                    .verify(&pae, sig)
                    .is_ok()
            })
        })
        .count()
        >= threshold
}
