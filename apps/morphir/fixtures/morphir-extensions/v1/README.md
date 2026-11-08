# avro and openapi qualification fixtures

`mise run test:cli-extension-model-line` generates with the published avro `0.4.0`
and openapi `0.5.0` extensions and compares the result with these files.

They are copied unchanged from finos/morphir-extensions at
`a73cda0d57a82e047b68483e142a7d21eb66abf3`, the commit of the tags
`extension/avro/v0.4.0` and `extension/openapi/v0.5.0` (Apache-2.0):

- `canonical-customer-v4.json` and `canonical-customer.avsc`, from
  `rust/crates/morphir-avro-extension/tests/`: the model and the golden of avro's
  own `generate_model_matches_generate_and_the_model_goldens` test.
- `typed-pricing.openapi-3.1.json`, `typed-pricing.quotes.Quote.schema.json` and
  `typed-pricing.quotes.Status.schema.json`, from
  `rust/crates/morphir-openapi-extension/tests/golden/`: the goldens of openapi's
  own test of the same kind. Their model is
  `apps/morphir-workbench/fixtures/typed-pricing.json`, the same bytes as the copy
  in that repository.
- `classic-schema-library-v3.json`, from
  `rust/crates/extension-guest-check/fixtures/`: the owner's IR 3 model, for IR 3
  on the CLI's legacy MEP `0.1` fallback and for the rows that hold a MEP `0.1`
  session with the guest.

The CLI sends no generate options, so the owners' goldens for other options (avro
`representation: idl` and openapi `version: 3.0`) are not used.
