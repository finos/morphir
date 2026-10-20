//! Child of pipeline::installed_client_tests. Private compiler invariants only.
//! Mutated decoded fixtures cannot issue an authenticated source or public run.
use super::*;
use crate::workbench::model_originals::workflow::{
    Decode, DecodeError,
    compile::CompileError,
    decode::OperandResource,
    installed_client::{self, Fixture},
    pairing::PairedWorkflow,
    source_compile::CompilationError,
    work::ClosureError,
};
use serde_json::{Value, json};

const PRIMARY_PATH: &str = ".morphir/out/packages/orders/compile.dest/morphir-ir.json";
const SENTINEL_PATH: &str = ".morphir/out/packages/orders/compile.dest/unrelated.log";

fn node<'a>(fixture: &'a mut Value, path: &str) -> &'a mut Value {
    fixture["nodes"]
        .as_array_mut()
        .unwrap()
        .iter_mut()
        .find(|node| node["path"] == path)
        .unwrap()
}
fn exercise(mutate: impl FnOnce(&mut Value, &mut Value), expected: ClosureError) {
    let corpus = source(CORPUS);
    let configured = policy(POLICY);
    prepared_installed_client(&corpus, &configured, ReviewedSources::installed_client_selected(), |inventory, owners| {
        assert_eq!(inventory.len(), 24);
        let original = inventory.invocation();
        let original = original.compiled_source().source().paired();
        let mut fixture = serde_json::from_slice::<Value>(SIDE).unwrap()["fixture"].take();
        let mut input: Value = serde_json::from_str(include_str!("../installed_client_controls/input.json")).unwrap();
        mutate(&mut fixture, &mut input);
        let fixture = owners.decode.literal_with_raw(&fixture.to_string()).unwrap().0;
        let fixture = Fixture::decode(&fixture, &mut owners.decode).unwrap();
        let input = owners.decode.literal_with_raw(&input.to_string()).unwrap().0;
        let scenario = crate::workbench::model_originals::workflow::input::Scenario::decode(&input, &mut owners.decode).unwrap();
        let paired = PairedWorkflow::new(&scenario, original.expected()).unwrap();
        let result = installed_client::compile_fixture_witness_roles(&fixture, &paired, &mut owners.closure, &mut owners.expansion, &mut owners.decode).map(|_| ());
        assert!(matches!(result, Err(CompilationError::Closure(CompileError::Owner(actual))) if actual == expected));
        Ok(())
    }).unwrap();
}

#[test]
fn witness_mapping_refuses_missing_and_ambiguous_undeclared_literal_nodes() {
    exercise(
        |fixture, _| {
            fixture["nodes"]
                .as_array_mut()
                .unwrap()
                .retain(|node| node["path"] != SENTINEL_PATH)
        },
        ClosureError::Missing,
    );
    exercise(
        |fixture, _| {
            fixture["nodes"].as_array_mut().unwrap().push(json!({"kind":"literal","path":".morphir/out/packages/orders/compile.dest/another-unrelated.log","bytes":{"kind":"utf8","text":"another"}}))
        },
        ClosureError::Ambiguous,
    );
}

#[test]
fn witness_mapping_refuses_wrong_kind_foreign_root_and_duplicate_physical_path() {
    exercise(
        |fixture, _| {
            *node(fixture, PRIMARY_PATH) =
                json!({"kind":"literal","path":PRIMARY_PATH,"bytes":{"kind":"utf8","text":""}})
        },
        ClosureError::Missing,
    );
    exercise(
        |fixture, _| node(fixture, PRIMARY_PATH)["path"] = json!("foreign/output/morphir-ir.json"),
        ClosureError::Semantic,
    );
    exercise(
        |fixture, _| {
            let duplicate = node(fixture, PRIMARY_PATH).clone();
            fixture["nodes"].as_array_mut().unwrap().push(duplicate);
        },
        ClosureError::Duplicate,
    );
}

#[test]
fn witness_mapping_refuses_role_alias_collision_and_normalized_included_sentinel() {
    exercise(
        |fixture, _| fixture["opaqueByteSource"] = fixture["primaryByteSource"].clone(),
        ClosureError::Semantic,
    );
    // Distinct raw paths, normalized alias of a declared companion. This is
    // not the duplicate-raw-path check and must use the existing path semantics.
    exercise(
        |fixture, _| {
            node(fixture, SENTINEL_PATH)["path"] =
                json!(".morphir/out/packages/orders/compile.dest/notes/OPAQUE.bin")
        },
        ClosureError::Semantic,
    );
}

#[test]
fn witness_mapping_binds_selected_peer_independent_session_and_opening_action() {
    exercise(
        |_, input| input["runs"][0]["fixture"]["runtime"]["peer"] = json!("foreign-peer"),
        ClosureError::Missing,
    );
    exercise(
        |_, input| {
            let frame = &mut input["runs"][0]["fixture"]["literalPeers"][0]["frames"][2]["text"];
            let mut ready: Value = serde_json::from_str(frame.as_str().unwrap()).unwrap();
            ready["result"]["binding"]["sessionId"] = json!("foreign-session");
            *frame = json!(ready.to_string());
        },
        ClosureError::Semantic,
    );
    exercise(
        |_, input| {
            input["runs"][0]["actions"][0]["source"]["providerId"] = json!("foreign-provider")
        },
        ClosureError::Semantic,
    );
}

#[test]
fn witness_mapping_decode_preflight_refusal_is_sticky_on_same_cumulative_owner() {
    let corpus = source(CORPUS);
    let configured = policy(POLICY);
    prepared_installed_client(
        &corpus,
        &configured,
        ReviewedSources::installed_client_selected(),
        |inventory, owners| {
            assert_eq!(inventory.len(), 24);
            let invocation = inventory.invocation();
            let plan = invocation.compiled_source().installed().unwrap();
            let paired = invocation.compiled_source().source().paired();
            let limit = serde_json::from_str::<Value>(POLICY).unwrap()["decode"]["byteVisits"]
                .as_u64()
                .unwrap() as usize;
            let remaining = limit
                .checked_sub(owners.decode.usage().byte_visits)
                .unwrap();
            owners
                .decode
                .bytes(remaining.checked_sub(1).unwrap())
                .unwrap();
            let before_factories =
                crate::workbench::model_originals::fixture_bytes::literal_factories();
            let result = installed_client::compile_fixture_witness_roles(
                plan.fixture(),
                paired,
                &mut owners.closure,
                &mut owners.expansion,
                &mut owners.decode,
            )
            .map(|_| ());
            assert!(matches!(
                result,
                Err(CompilationError::Source(SourceError::Decode(
                    DecodeError::Work(OperandResource::ByteVisits)
                )))
            ));
            assert_eq!(
                crate::workbench::model_originals::fixture_bytes::literal_factories(),
                before_factories,
                "refuse before materializing a literal recipe"
            );
            let decode = owners.decode.usage();
            let closure = owners.closure.usage();
            let expansion = owners.expansion.usage();
            let retry = installed_client::compile_fixture_witness_roles(
                plan.fixture(),
                paired,
                &mut owners.closure,
                &mut owners.expansion,
                &mut owners.decode,
            )
            .map(|_| ());
            assert!(matches!(
                retry,
                Err(CompilationError::Source(SourceError::Decode(
                    DecodeError::Work(OperandResource::ByteVisits)
                )))
            ));
            assert_eq!(owners.decode.usage(), decode);
            assert_eq!(owners.closure.usage(), closure);
            assert_eq!(owners.expansion.usage(), expansion);
            Ok(())
        },
    )
    .unwrap();
}
