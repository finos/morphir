// Append inside the SAME native_original_unit_controls module only after
// independent review/port. It reuses actual check_data/reject_case/owners.
// Not a second setup, checker, adapter or live context implementation.
include!("include-guards.rs");

#[test]
fn complete_measurements_and_current_selection_cannot_be_replaced_by_partial_zeroes_or_claims() {
    for raw in NATIVE_GUARDS {
        reject_case(raw);
    }
}

// All actual typed preparation stays local so borrowed plans never escape
// their input/expectation/closure/expansion owners. Macro only factors test
// setup; production uses the actual shared compiler.
macro_rules! with_prepared_native_data {
    ($plan:ident, $actual:ident, $body:block) => {{
        let mut decode = decoder();
        let input = decode_input(INPUT, &mut decode).unwrap();
        let expected = decode_expected(EXPECTED, &mut decode).unwrap();
        let $actual = decode_observation(POSITIVE, &mut decode).unwrap();
        let index = ValidatedRunIndex::for_original(&input, 0).unwrap();
        let mut aliases = closure();
        let mut expanded = expansion();
        let $plan =
            compile_native_plan(&input, &expected, index, &mut aliases, &mut expanded).unwrap();
        $body
    }};
}

#[test]
fn same_comparison_owner_preserves_first_fault_and_spent_work_on_retry() {
    with_prepared_native_data!(plan, actual, {
        let mut owner = CompareOwner::new(CompareLimits::new(0, 100_000_000, 100_000).unwrap());
        let first = compare_declaration_data(&plan, &actual, &mut owner)
            .err()
            .expect("first required structural visit must refuse");
        assert_eq!(
            first,
            ObservationError::Resource(super::observation_check::CompareResource::StructuralVisits)
        );
        let before = owner.usage();
        let second = compare_declaration_data(&plan, &actual, &mut owner)
            .err()
            .expect("same owner is sticky");
        assert_eq!(second, first);
        assert_eq!(owner.usage(), before);
    });
}

#[test]
fn native_factual_comparison_charges_the_existing_check_and_byte_owners() {
    with_prepared_native_data!(plan, actual, {
        for (limits, expected) in [
            (
                CompareLimits::new(1_000_000, 100_000_000, 0).unwrap(),
                super::observation_check::CompareResource::Checks,
            ),
            (
                CompareLimits::new(1_000_000, 0, 100_000).unwrap(),
                super::observation_check::CompareResource::ComparisonBytes,
            ),
        ] {
            // Explicit independent unit attempts, not resetting an existing
            // failed selected run or manufacturing observation capacity.
            let mut owner = CompareOwner::new(limits);
            let first = compare_declaration_data(&plan, &actual, &mut owner)
                .err()
                .expect("selected actual comparison effect must precharge");
            assert_eq!(first, ObservationError::Resource(expected));
            let spent = owner.usage();
            assert_eq!(
                compare_declaration_data(&plan, &actual, &mut owner).err(),
                Some(first)
            );
            assert_eq!(owner.usage(), spent);
        }
    });
}

#[test]
fn typed_native_decoders_observe_the_existing_first_fault_before_new_operands() {
    let mut owner =
        Decoder::new(DecodeLimits::new(4_194_304, 16_777_216, 131_072, 1, 131_072).unwrap());
    let first = owner.decode::<super::Text<0, 8>>(r#""AB""#).err().unwrap();
    assert_eq!(first, DecodeError::Work(super::OperandResource::ByteVisits));
    let spent = owner.usage();
    assert_eq!(decode_input("{", &mut owner).err().as_ref(), Some(&first));
    assert_eq!(owner.usage(), spent);
    assert_eq!(
        decode_expected("{", &mut owner).err().as_ref(),
        Some(&first)
    );
    assert_eq!(owner.usage(), spent);
    assert_eq!(
        decode_observation("{", &mut owner).err().as_ref(),
        Some(&first)
    );
    assert_eq!(owner.usage(), spent);
}

#[test]
fn native_alias_refusal_precedes_recipe_expansion_on_the_existing_owners() {
    let mut decode = decoder();
    let input = decode_input(INPUT, &mut decode).unwrap();
    let expected = decode_expected(EXPECTED, &mut decode).unwrap();
    let index = ValidatedRunIndex::for_original(&input, 0).unwrap();
    let mut aliases =
        ClosureOwner::new(ClosureLimits::new(0, 1_000_000, 100_000_000, 100_000_000).unwrap());
    let mut expanded = expansion();
    let before = expanded.usage();
    let error = compile_native_plan(&input, &expected, index, &mut aliases, &mut expanded)
        .err()
        .unwrap();
    assert!(matches!(
        error,
        CompilationError::Closure(super::compile::CompileError::Owner(
            super::work::ClosureError::Resource(super::work::Resource::Definitions)
        ))
    ));
    assert_eq!(expanded.usage(), before);
}
