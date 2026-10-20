//! Source-authored component controls. No runtime or authority assertions.
use super::super::work::ClosureLimits;
use super::super::{DecodeLimits, Decoder, domain, input};
use super::*;

fn source() -> (input::Scenario, domain::ExpectedWorkflow) {
    let mut decoder = Decoder::new(
        DecodeLimits::new(
            16_777_216,
            1_073_741_824,
            4_000_000,
            1_073_741_824,
            4_000_000,
        )
        .unwrap(),
    );
    let input = decoder
        .decode(include_str!("controls/server-input.json"))
        .unwrap();
    let expected = decoder
        .decode(include_str!("controls/server-expected.json"))
        .unwrap();
    (input, expected)
}
fn owner() -> ClosureOwner {
    ClosureOwner::new(ClosureLimits::new(100_000, 100_000, 2_000_000, 2_000_000).unwrap())
}

#[test]
fn actual_typed_prearms_history_and_observation_claims_preserve_source_references() {
    let (input, expected) = source();
    let mut owner = owner();
    let pair = super::super::pairing::PairedWorkflow::new(&input, &expected).unwrap();
    let result = compile(&pair, &mut owner).unwrap();
    let registrations: Vec<_> = result
        .definitions()
        .iter()
        .filter(|value| value.role == Role::ObservedRegistration)
        .collect();
    assert_eq!(registrations.len(), 1);
    assert_eq!(registrations[0].origin, DefinitionOrigin::ObservationClaim);
    let claims: Vec<_> = result
        .associations()
        .iter()
        .filter(|value| {
            matches!(
                value.binding,
                Some(RuntimeBindingObligation::OfferRegistration { .. })
            )
        })
        .collect();
    assert_eq!(claims.len(), 2);
    assert_eq!(claims[0].definition, claims[1].definition);
    let domain::ExpectedWorkflow::ModelOriginalsServer { checks, .. } = &expected else {
        panic!("fixed server source")
    };
    let domain::ExpectedServerCheck::Offer {
        state: domain::ExpectedOffer::Held { registration, .. },
        ..
    } = &checks.0[1]
    else {
        panic!("fixed held source")
    };
    assert!(std::ptr::eq(registrations[0].alias, registration));
    assert!(std::ptr::eq(claims[0].alias, registration));
    assert!(matches!(
        claims[0].scope,
        ScopeKey::ConnectionProvider { .. }
    ));
    // Capture and writer prearms precede their declarations in these literal
    // actions. Historical inventory/send follow Release/Disconnect. Closure
    // validates names without inferring that those later operations succeed.
    let input::Run::ModelOriginalsServer { actions, .. } = &input.runs.0[0] else {
        panic!("fixed server input")
    };
    let input::HostAction::Inventory { capture, .. } = &actions.0[8] else {
        panic!("fixed released inventory source")
    };
    assert!(result.associations().iter().any(|association| std::ptr::eq(
        association.alias,
        capture
    ) && matches!(
        association.position,
        SourcePosition::Action(8)
    )));
    assert!(owner.usage().lookup_bytes > 0);
}

#[test]
fn ordinary_forward_consumption_is_not_a_capture_prearm() {
    let (mut input, expected) = source();
    let input::Run::ModelOriginalsServer { actions, .. } = &mut input.runs.0[0] else {
        panic!("fixed server source")
    };
    actions.0.insert(
        1,
        input::HostAction::Continue {
            attempt: FixtureAlias::new("attempt-A").unwrap(),
        },
    );
    let pair = super::super::pairing::PairedWorkflow::new(&input, &expected).unwrap();
    assert!(matches!(
        compile(&pair, &mut owner()),
        Err(CompileError::Owner(ClosureError::ForwardReference))
    ));
}

#[test]
fn expected_byte_declaration_cannot_supply_a_missing_input_grant() {
    let (mut input, mut expected) = source();
    let input::Run::ModelOriginalsServer { fixture, .. } = &mut input.runs.0[0] else {
        panic!("fixed server source")
    };
    fixture.grants.0.clear();
    let mut decoder = Decoder::new(
        DecodeLimits::new(
            16_777_216,
            1_073_741_824,
            4_000_000,
            1_073_741_824,
            4_000_000,
        )
        .unwrap(),
    );
    let byte = decoder.decode(r#"{"alias":"workspace","byteLength":0,"bytes":{"kind":"utf8","text":""},"sha256":"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"}"#).unwrap();
    let domain::ExpectedWorkflow::ModelOriginalsServer { byte_sources, .. } = &mut expected else {
        panic!("fixed server expected")
    };
    byte_sources.0.push(byte);
    let pair = super::super::pairing::PairedWorkflow::new(&input, &expected).unwrap();
    assert!(matches!(
        compile(&pair, &mut owner()),
        Err(CompileError::Owner(ClosureError::Missing))
    ));
}

#[test]
fn duplicate_action_alias_is_an_authoring_error_before_runtime_effects() {
    let (mut input, expected) = source();
    let input::Run::ModelOriginalsServer { actions, .. } = &mut input.runs.0[0] else {
        panic!("fixed server source")
    };
    actions.0.push(input::HostAction::Connect {
        authentication: input::HostActionConnectAuthentication::Valid,
        connection: FixtureAlias::new("connection-A").unwrap(),
    });
    let pair = super::super::pairing::PairedWorkflow::new(&input, &expected).unwrap();
    assert!(matches!(
        compile(&pair, &mut owner()),
        Err(CompileError::Owner(ClosureError::Duplicate))
    ));
}

#[test]
fn declared_foreign_connection_does_not_statically_prove_capture_ownership() {
    let (mut input, expected) = source();
    let input::Run::ModelOriginalsServer { actions, .. } = &mut input.runs.0[0] else {
        panic!("fixed server source")
    };
    let input::HostAction::Inventory { connection, .. } = &mut actions.0[8] else {
        panic!("fixed inventory source")
    };
    *connection = FixtureAlias::new("connection-B").unwrap();
    actions.0.insert(
        0,
        input::HostAction::Connect {
            authentication: input::HostActionConnectAuthentication::Valid,
            connection: FixtureAlias::new("connection-B").unwrap(),
        },
    );
    let pair = super::super::pairing::PairedWorkflow::new(&input, &expected).unwrap();
    assert!(compile(&pair, &mut owner()).is_ok());
    // The actual runtime must still refuse this foreign-connection operation.
}

#[test]
fn runs_keep_identical_declarations_separate_but_share_one_budget() {
    let (mut input, expected) = source();
    let (mut other, _) = source();
    input.runs.0.push(other.runs.0.remove(0));
    let pair = super::super::pairing::PairedWorkflow::new(&input, &expected).unwrap();
    // Nine input definition attempts per literal run; six in expected data.
    let mut exact =
        ClosureOwner::new(ClosureLimits::new(24, 100_000, 2_000_000, 2_000_000).unwrap());
    assert!(compile(&pair, &mut exact).is_ok());
    assert_eq!(exact.usage().definitions, 24);
    let mut one_less =
        ClosureOwner::new(ClosureLimits::new(23, 100_000, 2_000_000, 2_000_000).unwrap());
    assert!(matches!(
        compile(&pair, &mut one_less),
        Err(CompileError::Owner(ClosureError::Resource(
            Resource::Definitions
        )))
    ));
}

#[test]
fn a_definition_in_another_run_cannot_supply_a_missing_capture_attempt() {
    let (mut input, expected) = source();
    let (mut other, _) = source();
    let input::Run::ModelOriginalsServer { actions, .. } = &mut input.runs.0[0] else {
        panic!("fixed server source")
    };
    actions.0.remove(3);
    input.runs.0.push(other.runs.0.remove(0));
    let pair = super::super::pairing::PairedWorkflow::new(&input, &expected).unwrap();
    assert!(matches!(
        compile(&pair, &mut owner()),
        Err(CompileError::Owner(ClosureError::Missing))
    ));
}

#[test]
fn literal_server_lookup_work_exact_and_one_less_is_pre_effect_and_sticky() {
    let (input, expected) = source();
    let pair = super::super::pairing::PairedWorkflow::new(&input, &expected).unwrap();
    // Independently derived before execution: 15 definition attempts,
    // 27 references, 68 declaration + 322 input + 272 expected byte visits.
    let mut exact = ClosureOwner::new(ClosureLimits::new(15, 27, 662, 2_000_000).unwrap());
    let plan = compile(&pair, &mut exact).unwrap();
    assert_eq!(plan.definitions().len(), 14);
    assert_eq!(plan.associations().len(), 27);
    assert_eq!(exact.usage().lookup_bytes, 662);
    let mut one_less = ClosureOwner::new(ClosureLimits::new(15, 27, 661, 2_000_000).unwrap());
    assert!(matches!(
        compile(&pair, &mut one_less),
        Err(CompileError::Owner(ClosureError::Resource(
            Resource::LookupBytes
        )))
    ));
    assert_eq!(one_less.usage().lookup_bytes, 660);
    let before = one_less.usage();
    assert!(matches!(
        compile(&pair, &mut one_less),
        Err(CompileError::Owner(ClosureError::Resource(
            Resource::LookupBytes
        )))
    ));
    assert_eq!(one_less.usage(), before);
}

#[test]
fn zero_structural_credit_refuses_before_any_alias_or_table_allocation() {
    let (input, expected) = source();
    let pair = super::super::pairing::PairedWorkflow::new(&input, &expected).unwrap();
    let mut owner = ClosureOwner::new(ClosureLimits::new(100_000, 100_000, 2_000_000, 0).unwrap());
    assert!(matches!(
        compile(&pair, &mut owner),
        Err(CompileError::Owner(ClosureError::Resource(
            Resource::StructuralVisits
        )))
    ));
    assert_eq!(owner.usage(), super::super::work::ClosureUsage::default());
}

#[test]
fn server_effect_issuer_is_an_explicit_source_blocker_not_a_missing_client_attempt() {
    let (input, mut expected) = source();
    let mut decoder = Decoder::new(
        DecodeLimits::new(
            16_777_216,
            1_073_741_824,
            4_000_000,
            1_073_741_824,
            4_000_000,
        )
        .unwrap(),
    );
    let trace = decoder.decode(r#"{"alias":"trace-A","events":[{"kind":"pending","effect":{"attempt":"attempt-A","kind":"capture","ordinal":0},"port":"promise","input":{"kind":"scenario-invocation"}}]}"#).unwrap();
    let domain::ExpectedWorkflow::ModelOriginalsServer { trace_sources, .. } = &mut expected else {
        panic!("fixed expected server")
    };
    trace_sources.0.push(trace);
    let pair = super::super::pairing::PairedWorkflow::new(&input, &expected).unwrap();
    let Err(CompileError::Scope(ScopeError::Semantic(
        super::super::meaning::SemanticBlocker::UnboundServerEffectIssuer(site),
    ))) = compile(&pair, &mut owner())
    else {
        panic!("expected the source-located unbound server issuer blocker")
    };
    assert_eq!(
        site.parts(),
        (
            super::super::walk::Operand::Expected,
            "EffectRef",
            None,
            "attempt"
        )
    );
}
