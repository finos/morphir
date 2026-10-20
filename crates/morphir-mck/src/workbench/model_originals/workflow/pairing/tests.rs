use super::super::{DecodeLimits, Decoder, domain, input};
use super::*;
use serde_json::{Value, json};

fn decoder() -> Decoder {
    Decoder::new(
        DecodeLimits::new(1_048_576, 67_108_864, 1_000_000, 67_108_864, 1_000_000).unwrap(),
    )
}
fn originals() -> (&'static str, &'static str) {
    let input = include_str!("input.json");
    let expected = include_str!("expected.json");
    // Frozen source-authored candidate, never captured implementation output.
    assert_eq!(
        crate::kit::hash::sha256_hex(input.as_bytes()),
        "e0e390e943260746becb2c747a9978c56a4b118fc58e7b8dca750283740110dd"
    );
    assert_eq!(
        crate::kit::hash::sha256_hex(expected.as_bytes()),
        "13d570e3518c29cc3b7cdfb49df24980a6fe2b6441952eb4308458161d597d90"
    );
    (input, expected)
}
fn fixture() -> (Value, Value) {
    let (input, expected) = originals();
    (
        serde_json::from_str(input).unwrap(),
        serde_json::from_str(expected).unwrap(),
    )
}
fn pair(input: &Value, expected: &Value) -> Result<(), PairError> {
    let mut d = decoder();
    let input: input::Scenario = d.decode(&input.to_string()).unwrap();
    let expected: domain::ExpectedWorkflow = d.decode(&expected.to_string()).unwrap();
    PairedWorkflow::new(&input, &expected).map(|_| ())
}
#[test]
fn source_authored_pair_selects_the_actual_client_run_without_authorizing_it() {
    let (raw, expected) = originals();
    let mut d = decoder();
    let input: input::Scenario = d.decode(raw).unwrap();
    let expected: domain::ExpectedWorkflow = d.decode(expected).unwrap();
    let paired = PairedWorkflow::new(&input, &expected).unwrap();
    assert_eq!(paired.run_index(), 0);
    assert!(
        matches!(paired.run(), PairedRun::Client { actions, fixture } if !actions.is_empty() && !fixture.literal_peers.0.is_empty())
    );
}
#[test]
fn every_origin_role_and_run_index_mismatch_refuses_before_compilation() {
    let (raw, expected) = fixture();
    for (member, value, error) in [
        ("packet", json!("additive"), PairError::Packet),
        ("id", json!("different-original"), PairError::Case),
        (
            "sha256",
            json!("0000000000000000000000000000000000000000000000000000000000000000"),
            PairError::Digest,
        ),
    ] {
        let mut changed = expected.clone();
        changed["origin"][member] = value;
        assert_eq!(pair(&raw, &changed), Err(error));
    }
    let mut changed = expected.clone();
    changed["runIndex"] = json!(1);
    assert_eq!(pair(&raw, &changed), Err(PairError::RunIndex));
    let mut changed = raw.clone();
    changed["runs"][0] = json!({
        "role":"model-originals-server",
        "actions":[{"kind":"checkpoint","name":"A"}],
        "fixture":{"grants":[],"guests":[],"providers":[],"records":[],"startup":{"cwd":"A","outputOverride":{"kind":"none"}}}
    });
    assert_eq!(pair(&changed, &expected), Err(PairError::Role));
}

#[test]
fn explicit_second_run_selection_and_server_role_pairing_do_not_default_to_zero() {
    let (mut raw, expected) = fixture();
    let server_run = json!({
        "role":"model-originals-server",
        "actions":[{"kind":"checkpoint","name":"A"}],
        "fixture":{"grants":[],"guests":[],"providers":[],"records":[],"startup":{"cwd":"A","outputOverride":{"kind":"none"}}}
    });
    let client_run = raw["runs"][0].clone();
    raw["runs"] = json!([server_run, client_run]);
    let mut client_expected = expected.clone();
    client_expected["runIndex"] = json!(1);
    assert!(pair(&raw, &client_expected).is_ok());
    assert_eq!(pair(&raw, &expected), Err(PairError::Role));
    // Synthetic metadata only. It establishes the other pairing branch,
    // not trusted provenance, valid aliases or an executable server fixture.
    let mut server_expected = expected;
    server_expected["role"] = json!("model-originals-server");
    server_expected["checks"] = json!([{"kind":"checkpoint-counts","checkpoint":"A","connection":"A","counts":[{"role":"slots","expected":{"kind":"exact","value":0}}],"id":"A"}]);
    assert!(pair(&raw, &server_expected).is_ok());
}
