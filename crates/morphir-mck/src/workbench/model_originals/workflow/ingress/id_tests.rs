use super::*;

#[test]
fn case_id_validation_preserves_the_existing_utf16_identity_policy() {
    let input = include_str!("controls/input-token.json");
    let expected = include_str!("controls/expected-token.json");
    for (id, accepted) in [
        ("a".repeat(128), true),
        ("😀".repeat(64), true),
        ("".to_owned(), false),
        ("a".repeat(129), false),
        ("😀".repeat(65), false),
    ] {
        let id_json = serde_json::to_string(&id).unwrap();
        let raw =
            format!(r#"{{"cases":[{{"id":{id_json},"input":{input},"expected":{expected}}}]}}"#);
        let mut owner = Decoder::new(
            super::super::DecodeLimits::new(
                1_048_576, 67_108_864, 1_000_000, 67_108_864, 1_000_000,
            )
            .unwrap(),
        );
        match BoundCorpus::decode(&raw, &mut owner) {
            Ok(corpus) => {
                assert!(accepted);
                assert_eq!(corpus.cases()[0].id(), id);
            }
            Err(IngressError::CaseId) => assert!(!accepted),
            Err(other) => panic!("unexpected case identity error: {other:?}"),
        }
    }
}
