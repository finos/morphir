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
