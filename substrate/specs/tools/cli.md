# CLI

The `substrate` CLI parses, evaluates, and tests [user modules](../language.md#user-modules) written as markdown files.

## Commands

### `test <file>`

Runs all test cases embedded in a user module. Exits with code `1` if any test fails.

| Option                        | Default | Description                                  |
| ----------------------------- | ------- | -------------------------------------------- |
| `-d, --definition <names...>` | all     | Restrict to the named definitions only       |
| `-v, --verbose`               | false   | Show passing cases in addition to failures   |
| `-r, --reporter <format>`     | `text`  | Output format: `text` or `junit`             |
| `-o, --output <file>`         | stdout  | Write the report to a file instead of stdout |

The `text` reporter prints a summary line (`✓ N/N tests passed`) and, for failing cases, the definition name, inputs, expected value, and actual value. The `junit` reporter produces [JUnit XML](https://github.com/testmoapp/junitxml), with one `<testsuite>` per definition and one `<testcase>` per row, including a `<failure>` element for each failing case.

### `eval <file> <definition>`

Evaluates a single definition with the supplied inputs and prints the result.

| Option                   | Description                                                                                |
| ------------------------ | ------------------------------------------------------------------------------------------ |
| `-i, --input <pairs...>` | Input values as `key=value` pairs. Values are coerced to `number`, `boolean`, or `string`. |

Intermediate definitions declared earlier in the module are resolved automatically, so only the leaf inputs (those not defined in the module) need to be supplied.

### `list <file>`

Prints the module title, its declared inputs, and each definition with its test-case count.
