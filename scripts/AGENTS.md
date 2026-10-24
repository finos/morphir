# Script authoring guidance

These instructions apply to automation under `scripts/`. Follow the repository's
[task-script policy](../.github/AGENTS.md#task-scripts) for standalone MoonBit
scripts, pinned dependencies and mise integration. The root
[MoonBit dependency guidance](../AGENTS.md#moonbit-dependencies) lists preferred
package owners for all MoonBit code, including these scripts.

## Command-line arguments

- Use a command-line parsing library, such as `moonbitlang/core/argparse`, to
  declare commands, subcommands, options, flags and positional arguments.
- Do not write custom argument scanners, flag-matching loops or a parallel parser
  for help, defaults, required values, unknown options or conflicting arguments.
  Let the library handle argument syntax and diagnostics; validate domain values
  after parsing.
- Apply this rule to new scripts and when changing an existing script's argument
  interface. Preserve its supported arguments, help, exit codes and `--` behavior.
- A wrapper that forwards arguments unchanged to an external tool should pass the
  argument array directly. It does not need to parse the external tool's options.
- Keep focused behavior checks for the script's supported invocation, invalid
  arguments and failure propagation.

## JSON output

Follow the repository's [command-output contract](../AGENTS.md#command-output-for-automation).
Every script command supports opt-in `--json`, including scripts whose normal
result is already JSON. Preserve existing default output and JSON schemas.
Keep child progress and diagnostics separate from JSON results, and test
parseable success and failure output with the original exit-status behavior.
Use the existing pinned JSON library and qualification paths; do not add a new
output framework or CI job just to check a small command.
