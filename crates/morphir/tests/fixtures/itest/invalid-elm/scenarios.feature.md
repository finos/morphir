# Feature: Reject malformed single-file Elm

`@language:elm` `@frontend:elm-native` `@area:compile` `@kind:negative` `@suite:offline` `@workspace:inline`

The workspace holds only `Broken.elm`, from the fence below. The module is incomplete, so
compilation must fail.

```yaml itest
provider: rego
workspace: {kind: inline}
files:
  - path: Broken.elm
    content: |
      module Broken

      type alias Amount =
```

## Scenario: Reject malformed single-file Elm

`@section:.` `@steps:1`

Malformed Elm fails compilation without publishing usable IR. Rego verifies the diagnostics and
absent artifacts.

* When I run "morphir compile --input Broken.elm --extension morphir-elm-native --output installed --json" with a 30 second timeout
* And I capture ".morphir/out/compile.dest/morphir-ir.json" as exists named "ir"
* And I capture "installed/morphir-ir.json" as exists named "installed"
* And stdout is JSON
* Then the result should satisfy the policy rules "data.step_1_test.test_exit_code, data.step_1_test.test_compile_reports_failure, data.step_1_test.test_no_ir_result, data.step_1_test.test_error_diagnostic, data.step_1_test.test_no_canonical_ir, data.step_1_test.test_no_installed_ir":

  ```rego
  package step_1_test

  import rego.v1

  test_exit_code if {
      input.exitCode == 1
  }

  test_compile_reports_failure if {
      input.stdoutJson["success"] == false
  }

  test_no_ir_result if {
      input.stdoutJson["ir"] == null
  }

  test_error_diagnostic if {
      input.stdoutJson["diagnostics"][0]["level"] == "error"
  }

  test_no_canonical_ir if {
      input.artifacts["ir"].kind == "missing"
  }

  test_no_installed_ir if {
      input.artifacts["installed"].kind == "missing"
  }
  ```
