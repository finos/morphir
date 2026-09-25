# Feature: Compile and install types from one Elm file

`@language:elm` `@frontend:elm-native` `@config:none` `@area:compile` `@area:install` `@ir:v3` `@kind:positive` `@suite:offline` `@workspace:directory`

The project source is the adjacent [`Example.elm`](Example.elm) file. It defines a public `Amount`
record and a public `Kind` custom type. The driver copies this directory into an isolated workspace
before it runs the commands below. It does not copy `installed/`, so the output of a manual run does
not become an input of the next test.

```yaml itest
provider: rego
workspace: {kind: directory, path: ".", exclude: [installed]}
```

## Scenario: Compile and install types from one Elm file

`@section:.` `@steps:2`

The native Elm frontend compiles a single file without project configuration, writes classic v3 IR
and a task result, and installs a copy when requested. Rego checks the outputs; this proves type
compilation, not native Elm function lowering.

* When I run "morphir compile --input Example.elm --extension morphir-elm-native --package-name examples/single-file --json" with a 30 second timeout

This command compiles the public `Amount` and `Kind` types. It does not install a copy.

* And I capture ".morphir/out/compile.dest/morphir-ir.json" as json named "ir"
* And I capture ".morphir/out/compile.json" as json named "task"
* And I capture "installed/morphir-ir.json" as exists named "installed"
* And stdout is JSON
* Then the result should satisfy the policy rules "data.step_1_test.test_exit_code, data.step_1_test.test_compile_reports_success, data.step_1_test.test_ir_format_version, data.step_1_test.test_ir_is_library, data.step_1_test.test_package_name, data.step_1_test.test_module_name, data.step_1_test.test_amount_type_name, data.step_1_test.test_amount_is_public, data.step_1_test.test_kind_type_name, data.step_1_test.test_kind_is_public, data.step_1_test.test_amount_is_alias, data.step_1_test.test_amount_record_fields, data.step_1_test.test_kind_is_custom_type, data.step_1_test.test_simple_constructor, data.step_1_test.test_detailed_constructor, data.step_1_test.test_task_ir_version, data.step_1_test.test_no_implicit_install":

  ```rego
  package step_1_test

  import rego.v1

  test_exit_code if {
      input.exitCode == 0
  }

  test_compile_reports_success if {
      input.stdoutJson["success"] == true
  }

  test_ir_format_version if {
      input.artifacts["ir"].kind == "json"
      input.artifacts["ir"].value["formatVersion"] == 3
  }

  test_ir_is_library if {
      input.artifacts["ir"].kind == "json"
      input.artifacts["ir"].value["distribution"][0] == "Library"
  }

  test_package_name if {
      input.artifacts["ir"].kind == "json"
      input.artifacts["ir"].value["distribution"][1] == [["examples"],["single","file"]]
  }

  test_module_name if {
      input.artifacts["ir"].kind == "json"
      input.artifacts["ir"].value["distribution"][3]["modules"][0][0] == [["example"]]
  }

  test_amount_type_name if {
      input.artifacts["ir"].kind == "json"
      input.artifacts["ir"].value["distribution"][3]["modules"][0][1]["value"]["types"][0][0] == ["amount"]
  }

  test_amount_is_public if {
      input.artifacts["ir"].kind == "json"
      input.artifacts["ir"].value["distribution"][3]["modules"][0][1]["value"]["types"][0][1]["access"] == "Public"
  }

  test_kind_type_name if {
      input.artifacts["ir"].kind == "json"
      input.artifacts["ir"].value["distribution"][3]["modules"][0][1]["value"]["types"][1][0] == ["kind"]
  }

  test_kind_is_public if {
      input.artifacts["ir"].kind == "json"
      input.artifacts["ir"].value["distribution"][3]["modules"][0][1]["value"]["types"][1][1]["access"] == "Public"
  }

  test_amount_is_alias if {
      input.artifacts["ir"].kind == "json"
      input.artifacts["ir"].value["distribution"][3]["modules"][0][1]["value"]["types"][0][1]["value"]["value"][0] == "TypeAliasDefinition"
  }

  test_amount_record_fields if {
      input.artifacts["ir"].kind == "json"
      input.artifacts["ir"].value["distribution"][3]["modules"][0][1]["value"]["types"][0][1]["value"]["value"][2] == ["Record",{},[{"name":["value"],"tpe":["Reference",{},[[["morphir"],["s","d","k"]],[["basics"]],["int"]],[]]}]]
  }

  test_kind_is_custom_type if {
      input.artifacts["ir"].kind == "json"
      input.artifacts["ir"].value["distribution"][3]["modules"][0][1]["value"]["types"][1][1]["value"]["value"][0] == "CustomTypeDefinition"
  }

  test_simple_constructor if {
      input.artifacts["ir"].kind == "json"
      input.artifacts["ir"].value["distribution"][3]["modules"][0][1]["value"]["types"][1][1]["value"]["value"][2]["value"][0] == [["simple"],[]]
  }

  test_detailed_constructor if {
      input.artifacts["ir"].kind == "json"
      input.artifacts["ir"].value["distribution"][3]["modules"][0][1]["value"]["types"][1][1]["value"]["value"][2]["value"][1][0] == ["detailed"]
  }

  test_task_ir_version if {
      input.artifacts["task"].kind == "json"
      input.artifacts["task"].value["ir"]["version"] == "v3"
  }

  test_no_implicit_install if {
      input.artifacts["installed"].kind == "missing"
  }
  ```

* When I run "morphir compile --input Example.elm --extension morphir-elm-native --package-name examples/single-file --output installed --json" with a 30 second timeout

This command installs v3 IR in `installed/morphir-ir.json` and keeps the canonical output.

* And I capture ".morphir/out/compile.dest/morphir-ir.json" as exists named "ir"
* And I capture "installed/morphir-ir.json" as json named "installed"
* And stdout is JSON
* Then the result should satisfy the policy rules "data.step_2_test.test_exit_code, data.step_2_test.test_compile_reports_success, data.step_2_test.test_canonical_ir_preserved, data.step_2_test.test_installed_ir_format_version, data.step_2_test.test_installed_package_name, data.step_2_test.test_installed_module_name":

  ```rego
  package step_2_test

  import rego.v1

  test_exit_code if {
      input.exitCode == 0
  }

  test_compile_reports_success if {
      input.stdoutJson["success"] == true
  }

  test_canonical_ir_preserved if {
      input.artifacts["ir"].kind != "missing"
  }

  test_installed_ir_format_version if {
      input.artifacts["installed"].kind == "json"
      input.artifacts["installed"].value["formatVersion"] == 3
  }

  test_installed_package_name if {
      input.artifacts["installed"].kind == "json"
      input.artifacts["installed"].value["distribution"][1] == [["examples"],["single","file"]]
  }

  test_installed_module_name if {
      input.artifacts["installed"].kind == "json"
      input.artifacts["installed"].value["distribution"][3]["modules"][0][0] == [["example"]]
  }
  ```
