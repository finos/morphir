# application/configuration Specification

## Purpose

Defines how the Morphir CLI and Workbench find, merge, validate and report Morphir configuration, so that every host
computes the same effective configuration from the same files, environment and command line.

## Requirements

### Requirement: Configuration precedence

The CLI and Workbench SHALL merge configuration in this order, where a later layer wins: built-in defaults, system
file, global user file, workspace JSON file, workspace YAML file, workspace TOML file, explicitly selected file,
member file, active configuration profile files, user override file, `MORPHIR_` environment variables, and command-line values.

#### Scenario: Environment variable overrides the project file

- **WHEN** `morphir.toml` sets `workspace.out_dir = "build"` and `MORPHIR_WORKSPACE__OUT_DIR` is `dist`
- **THEN** the effective value of `workspace.out_dir` is `dist`

#### Scenario: Command-line value overrides the environment

- **WHEN** an environment variable and a command-line option set the same key to different values
- **THEN** the effective value is the command-line value

#### Scenario: User override file wins over the primary file

- **WHEN** `morphir.user.toml` next to `morphir.toml` sets a key that `morphir.toml` also sets
- **THEN** the effective value comes from `morphir.user.toml`

#### Scenario: TOML user override wins over YAML user override

- **WHEN** `morphir.user.yaml` and `morphir.user.toml` are both next to the primary file and set the same key
- **THEN** the effective value comes from `morphir.user.toml`

### Requirement: Format layers in one workspace

The primary files of one workspace directory SHALL all be merged, in three format layers where a later layer wins:
JSON (`.json`, `.json5`), then YAML (`.yaml`, `.yml`), then TOML. Keys that only a lower layer sets SHALL stay in
effect. User override files SHALL use the same order.

#### Scenario: TOML overrides JSON

- **WHEN** `morphir.json` sets `sourceDirectory` to `elm-src` and `morphir.toml` sets `project.source_directory = "src"`
- **THEN** the effective value of `project.source_directory` is `src` and its origin is `morphir.toml`

#### Scenario: TOML overrides YAML

- **WHEN** `morphir.yml` sets `workspace.out_dir: build` and `morphir.toml` sets `workspace.out_dir = "out"`
- **THEN** the effective value of `workspace.out_dir` is `out` and its origin is `morphir.toml`

#### Scenario: YAML overrides JSON

- **WHEN** `morphir.json` and `morphir.yaml` set `workspace.out_dir` to different values and no TOML file sets it
- **THEN** the effective value comes from `morphir.yaml`

#### Scenario: Key set only in JSON

- **WHEN** `morphir.json` sets `exposedModules` and neither `morphir.yaml` nor `morphir.toml` sets `project.exposed_modules`
- **THEN** the effective value of `project.exposed_modules` comes from `morphir.json`

#### Scenario: Warning for keys from JSON

- **WHEN** a workspace holds `morphir.json` and `morphir.toml`, and `morphir.json` sets keys that `morphir.toml` does not
- **THEN** the run reports one `config.json_keys_below_toml` warning that names `morphir.json` and those keys

### Requirement: Explicitly selected configuration file

`--config <path>` SHALL select a TOML, YAML, JSON or JSON5 configuration file. The selected file SHALL be merged
above the workspace primary files, so its values override `morphir.toml`. A discovered file that is selected SHALL be merged
once, at the selected layer. A missing or unreadable file SHALL be a usage error.

#### Scenario: Selected morphir.json wins

- **WHEN** `morphir.toml` sets `project.source_directory = "src"`, `morphir.json` sets `sourceDirectory` to
  `elm-src`, and the command line has `--config morphir.json`
- **THEN** the effective value of `project.source_directory` is `elm-src`, and the keys that only `morphir.toml` sets
  stay in effect

#### Scenario: Missing selected file

- **WHEN** the command line has `--config missing.json` and the file does not exist
- **THEN** the run fails with a usage error that names `missing.json` and exits with 2

### Requirement: Configuration script option

`--config-script <path>` SHALL run a Scheme configuration script, with the behavior that `--config` had before this
change. A `.scm` path given to `--config` SHALL be refused with a usage error that names `--config-script`.

#### Scenario: Script option

- **WHEN** `morphir run --config-script transforms.scm --backend scheme` runs
- **THEN** the script runs last, after the workspace and project scripts, as `--config transforms.scm` did before

#### Scenario: Old script usage

- **WHEN** `morphir run --config transforms.scm` runs
- **THEN** the run fails with a usage error that tells the user to use `--config-script` and exits with 2

### Requirement: Project file discovery

The CLI and Workbench SHALL parse primary configuration while walking up from the working directory. The first
directory whose merged primary documents contain a `workspace` section SHALL be the workspace root. A standalone
project SHALL NOT stop this search. Discovery SHALL check the nearest primary itself before its parents. With no
workspace within the boundary, it SHALL use the nearest project primary.

#### Scenario: Primary file in a parent directory

- **WHEN** the working directory is `/w/app/src` and only `/w/app/morphir.toml` exists
- **THEN** the workspace root is `/w/app`

#### Scenario: JSON file only

- **WHEN** the working directory is `/w/app/src` and only `/w/app/morphir.json` exists
- **THEN** the workspace root is `/w/app` and the configuration comes from `morphir.json`

#### Scenario: Standalone member file does not hide its workspace

- **WHEN** `/repo/app/morphir.toml` defines a project, `/repo/morphir.toml` declares a workspace, and the working directory is `/repo/app/src`
- **THEN** the selected workspace root is `/repo` and the project primary remains `/repo/app/morphir.toml`

#### Scenario: Nearest declared workspace stops the search

- **WHEN** `/repo/morphir.toml` and `/repo/nested/morphir.toml` both declare workspaces, and the working directory is `/repo/nested/src`
- **THEN** the selected workspace root is `/repo/nested` and the outer workspace is not read

#### Scenario: Standalone project fallback

- **WHEN** `/repo/app/morphir.toml` defines a project and no workspace exists within the boundary
- **THEN** the root is `/repo/app`

### Requirement: Primary configuration names

Primary names SHALL be `morphir.toml`, `.morphir/morphir.toml` and `.config/morphir/config.toml`, and the same names
with `.yaml`, `.yml`, `.json` or `.json5`. The supplemental `morphir-workspace.json` SHALL also identify a primary
location and participate in the JSON layer.

#### Scenario: Hidden layout remains discoverable

- **WHEN** only `/repo/.morphir/morphir.toml` exists and the working directory is `/repo/src`
- **THEN** discovery examines `/repo` as a primary location

### Requirement: Warning for YAML beside TOML

When one directory holds a YAML primary file (`.yaml` or `.yml`) and a TOML primary file, the run SHALL merge both
and report a warning diagnostic with the code `config.yaml_beside_toml` that names both files.

#### Scenario: Warning on by default

- **WHEN** one directory holds `morphir.yml` and `morphir.toml` and no setting suppresses the warning
- **THEN** the run merges both files, succeeds, and reports one `config.yaml_beside_toml` warning that names both files

#### Scenario: Warning in JSON mode

- **WHEN** the workspace runs `morphir project list --json` with the warning on
- **THEN** the warning is in the result's `diagnostics` and on standard error, and standard output holds only the
  JSON result

### Requirement: Suppressing configuration warnings

A configuration warning SHALL be suppressed when its code is given by `--suppress-warning <code>` (repeatable), by
`MORPHIR_DIAGNOSTICS__SUPPRESS` as a comma-separated list, or by `diagnostics.suppress` in a system or global user
file. A workspace, member, user override or selected file SHALL NOT suppress warnings. An unknown code SHALL give a
warning that names it.

#### Scenario: Suppressed by the flag

- **WHEN** a workspace with `morphir.yml` and `morphir.toml` runs with `--suppress-warning config.yaml_beside_toml`
- **THEN** no `config.yaml_beside_toml` warning is reported

#### Scenario: Suppressed by the environment

- **WHEN** `MORPHIR_DIAGNOSTICS__SUPPRESS` is `config.yaml_beside_toml,config.json_keys_below_toml`
- **THEN** neither warning is reported

#### Scenario: Suppressed in the global user file

- **WHEN** the global user file sets `diagnostics.suppress = ["config.json_keys_below_toml"]`
- **THEN** no `config.json_keys_below_toml` warning is reported for any workspace

#### Scenario: Workspace file cannot suppress

- **WHEN** only `morphir.toml` of the workspace sets `diagnostics.suppress = ["config.yaml_beside_toml"]`
- **THEN** the `config.yaml_beside_toml` warning is still reported

#### Scenario: Unknown code

- **WHEN** the command line has `--suppress-warning config.no_such_code`
- **THEN** the run reports a warning that names `config.no_such_code` and continues

### Requirement: Member configuration formats

Each workspace member SHALL find, layer and check its configuration files with the same rules as the workspace root:
the JSON, YAML and TOML layers, the ambiguity rule, the morphir-elm manifest fields and the configuration warnings.

#### Scenario: morphir-elm member

- **WHEN** a member directory holds only `morphir.json` with morphir-elm manifest fields
- **THEN** the member's project name, source directory and Elm frontend come from that file

#### Scenario: Member with JSON and TOML

- **WHEN** a member directory holds `morphir.json` and `morphir.toml` that set `project.source_directory` differently
- **THEN** the member's value comes from its `morphir.toml`

#### Scenario: Ambiguous member files

- **WHEN** a member directory holds both `morphir.yaml` and `morphir.yml`
- **THEN** the run fails with an ambiguous-configuration error that names both files

### Requirement: Ambiguous primary files

Two primary files of the same format layer in one workspace directory SHALL be refused as ambiguous. Files of
different layers in one directory SHALL NOT be ambiguous.

#### Scenario: Two TOML files

- **WHEN** one directory holds both `morphir.toml` and `.morphir/morphir.toml`
- **THEN** the run fails with an ambiguous-configuration error that names both files

#### Scenario: YAML and YML together

- **WHEN** one directory holds both `morphir.yaml` and `morphir.yml`
- **THEN** the run fails with an ambiguous-configuration error that names both files

#### Scenario: JSON and JSON5 together

- **WHEN** one directory holds both `morphir.json` and `morphir.json5`
- **THEN** the run fails with an ambiguous-configuration error that names both files

#### Scenario: One file per layer

- **WHEN** one directory holds `morphir.json`, `morphir.yaml` and `morphir.toml`
- **THEN** the run merges all three and reports no ambiguity

### Requirement: morphir-elm manifest fields

A JSON primary file SHALL accept the canonical configuration keys and the morphir-elm manifest fields. `name`,
`sourceDirectory` and `exposedModules` SHALL map to `project.name`, `project.source_directory` and
`project.exposed_modules`, and SHALL select the Elm frontend and the checkpoint defaults, as `morphir.json` does
today. A file that sets a manifest field and its canonical key SHALL be refused.

#### Scenario: morphir-elm project

- **WHEN** `morphir.json` holds `{"name": "My.Package", "sourceDirectory": "src", "exposedModules": ["Main"]}`
- **THEN** the project name is `My.Package`, the frontend language is `elm` and the backend defaults to `checkpoint`

#### Scenario: Canonical keys in JSON5

- **WHEN** `morphir.json5` holds `{ workspace: { out_dir: 'build', }, }` with a `//` comment line above it
- **THEN** the effective value of `workspace.out_dir` is `build`

#### Scenario: Field and key together

- **WHEN** `morphir.json` sets both `sourceDirectory` and `project.source_directory`
- **THEN** the run fails with an error that names both

#### Scenario: Unsupported manifest field

- **WHEN** `morphir.json` has a non-empty `dependencies` list
- **THEN** the run gives a warning that `dependencies` is not supported, as it does today

### Requirement: morphir-workspace.json

`morphir-workspace.json` SHALL be a JSON configuration file of the JSON layer, parsed as JSON5 with the canonical
keys. In the JSON layer it SHALL be merged below the other JSON primary file of the same directory, so `morphir.json`
wins over it. It SHALL NOT be ambiguous with `morphir.json` or `morphir.json5`.

#### Scenario: Workspace file only

- **WHEN** the working directory is `/w/app/src` and only `/w/app/morphir-workspace.json` exists, setting
  `workspace.members` to `["billing"]`
- **THEN** the workspace root is `/w/app` and its members are `billing`

#### Scenario: Workspace file and project manifest

- **WHEN** `morphir-workspace.json` and `morphir.json` in one directory set `workspace.out_dir` differently
- **THEN** the effective value comes from `morphir.json`

### Requirement: Supported configuration formats

Configuration files SHALL be TOML, YAML or JSON, chosen by the file extension (`.toml`, `.yaml`, `.yml`, `.json`,
`.json5`). Files ending in `.json` and `.json5` SHALL both be parsed as JSON5. Any other extension SHALL be refused
with an unsupported-format error that names the file.

#### Scenario: YAML primary file

- **WHEN** the workspace primary file is `morphir.yaml` and it sets `workspace.out_dir: build`
- **THEN** the effective value of `workspace.out_dir` is `build` and its origin is `morphir.yaml`

#### Scenario: Unsupported extension

- **WHEN** the command line has `--config settings.ini`
- **THEN** the run fails with an unsupported-format error that names `settings.ini` and exits with 2

#### Scenario: JSON5 syntax in morphir.json

- **WHEN** `morphir.json` has a `//` comment, an unquoted key and a trailing comma
- **THEN** the file is read and its values are merged

#### Scenario: Invalid JSON

- **WHEN** `morphir.json` is not valid JSON5
- **THEN** the run fails with an error that names `morphir.json` and the position of the problem, and exits with 2

### Requirement: TOML is the written format

TOML SHALL be the default Morphir configuration format. Commands that create configuration SHALL write
`morphir.toml`, and commands that change configuration SHALL edit the workspace TOML primary file, keeping its
formatting and comments. They SHALL NOT write YAML or JSON configuration.

#### Scenario: New workspace

- **WHEN** `morphir workspace init` runs in an empty directory
- **THEN** it writes `morphir.toml` and no YAML or JSON configuration file

#### Scenario: Project added to a TOML workspace

- **WHEN** `morphir project add billing` runs in a workspace whose primary file is `morphir.toml`
- **THEN** `morphir.toml` lists the new member, its other content and comments are unchanged, and the new project
  gets `billing/morphir.toml`

### Requirement: Writes to JSON and YAML workspaces

When a command must change a workspace that has JSON or YAML primary files and no TOML primary file, it SHALL create
`morphir.toml` in the same directory with the change and leave the JSON and YAML files unchanged. Each key written to
`morphir.toml` SHALL hold its full new effective value, so values from the lower layers are not lost.

#### Scenario: JSON workspace

- **WHEN** `morphir project add billing` runs in a workspace whose only primary file is `morphir.json`
- **THEN** a new `morphir.toml` next to `morphir.json` lists the member, `morphir.json` is unchanged, and the
  effective configuration has the values of both files

#### Scenario: YAML workspace

- **WHEN** `morphir project add billing` runs in a workspace whose only primary file is `morphir.yml`, which lists the
  member `ledger`
- **THEN** a new `morphir.toml` next to `morphir.yml` sets `workspace.members` to `ledger` and `billing`, and
  `morphir.yml` is unchanged

#### Scenario: Root project declared in a lower format

- **WHEN** `morphir project remove .` runs and a JSON, JSON5, YAML or YML workspace primary declares the root project,
  including a declaration also overridden by TOML
- **THEN** the command refuses with an error naming the lower primary and explaining that its project declaration
  must be removed there, without creating, changing or deleting files
- **AND** JSON mode reports the existing structured command failure and exits with 2

#### Scenario: Root project declared only in TOML

- **WHEN** `morphir project remove .` runs and only TOML declares the root project, while lower formats may supply
  workspace settings
- **THEN** the command removes the TOML project table, keeps source files and lower primary files unchanged, and
  retains the effective workspace settings

### Requirement: Environment variable mapping

A variable whose name starts with `MORPHIR_`, except the reserved `MORPHIR_HOME` and `MORPHIR_PROFILES`, SHALL set the configuration key made from the
rest of the name in lower case, with `__` separating the key path segments. A name with an empty segment SHALL be
refused.

#### Scenario: Nested key

- **WHEN** `MORPHIR_IR__FORMAT_VERSION` is `4`
- **THEN** the effective value of `ir.format_version` is `4`

#### Scenario: Empty segment

- **WHEN** `MORPHIR_IR____FORMAT` is set
- **THEN** the run fails with an error that names the variable

### Requirement: Value provenance

Each effective configuration value SHALL record the layer and, for a file, the path that supplied it. Commands that
report configuration SHALL show this origin.

#### Scenario: Origin of an overridden value

- **WHEN** `ir.format` is set in `morphir.toml` and in `MORPHIR_IR__FORMAT`
- **THEN** the recorded origin of `ir.format` is the environment variable `MORPHIR_IR__FORMAT`

### Requirement: Isolated discovery

A Morphir MoonBit run SHALL accept an explicit discovery boundary. With a boundary, discovery SHALL NOT read a primary file above the
boundary directory, and SHALL NOT read system or global user files when isolation is requested. (bead:
morphir-o6vm.10)

This adoption SHALL qualify these controls in the MoonBit CLI independently of the separate Rust CLI itest driver.
The Rust driver work remains tracked by `morphir-o6vm.10` and is not a release prerequisite or completed by this change.

#### Scenario: Project under a temporary root

- **WHEN** a scenario project at `/tmp/run-1/project` runs with the boundary `/tmp/run-1/project` and `/tmp/morphir.toml` exists
- **THEN** the effective configuration does not contain values from `/tmp/morphir.toml`

#### Scenario: Isolated run ignores global files

- **WHEN** a run requests isolation and the global user file sets `workspace.out_dir`
- **THEN** the effective value of `workspace.out_dir` comes from the defaults or the project, not from the global file

### Requirement: Same configuration on every host

The CLI on native, js, wasm and wasm-gc, and the Workbench, SHALL compute the same effective configuration and
provenance from the same file contents, environment and command-line values.

#### Scenario: Native and Wasm runs agree

- **WHEN** the same workspace files and environment are given to the native CLI and to the wasm-gc CLI
- **THEN** both report the same effective values and origins

### Requirement: Configuration profiles are enabled without implicit defaults

The CLI and Workbench SHALL enable Moon-Lander configuration profiles. Profile selection SHALL remain separate
from frontend `--profile`. No implicit default profile SHALL be active. Environment-specific files and local
override files SHALL remain disabled by this adoption.

#### Scenario: No profile activation

- **WHEN** no profile selection, include, active list or default list is given
- **THEN** no profile file is requested and ordinary configuration keeps its existing values

#### Scenario: Frontend profile stays separate

- **WHEN** `project add` or `workspace init` uses frontend `--profile`
- **THEN** that value keeps its existing frontend meaning and does not activate a configuration profile

### Requirement: Profile activation sources

Configuration profile selection SHALL use, in order, explicit `--profiles` or `--no-profiles`, present
`MORPHIR_PROFILES`, base `profiles.active`, base `profiles.default`, then the Moon-Lander policy fallback.
An explicit list SHALL replace lower selection lists. An absent variable SHALL be unspecified; a present empty
or whitespace-only variable SHALL disable profiles.

#### Scenario: CLI replaces environment activation

- **WHEN** `MORPHIR_PROFILES=postgres` and the run selects `--profiles metrics`
- **THEN** metrics is selected instead of postgres, before includes and group expansion

#### Scenario: Empty environment selector disables

- **WHEN** the base file defaults to development and `MORPHIR_PROFILES` is present but empty
- **THEN** development and includes are inactive and no profile file loads

### Requirement: Profile arguments use the framework grammar

`--profiles <a,b>` SHALL be repeatable in argument order, split commas and trim ASCII whitespace. Names SHALL
follow Moon-Lander's validated 1–64-character lowercase name grammar. Empty elements and a conflict with
`--no-profiles` SHALL be usage errors before discovery or service construction. These controls SHALL support
`--json`, and help SHALL perform no profile I/O.

#### Scenario: Ordered repeated profile options

- **WHEN** a run has `--profiles postgres,metrics --profiles tracing`
- **THEN** the selected roots are postgres, metrics and tracing in that order

#### Scenario: Invalid or conflicting selection

- **WHEN** a run has `--profiles postgres,,metrics`, `--profiles=`, or both `--profiles metrics` and `--no-profiles`
- **THEN** it fails with exit code 2 before reading profile files or constructing services

#### Scenario: JSON help has no discovery

- **WHEN** a command requests `--help --json --profiles metrics`
- **THEN** it returns its documented JSON help result without reading base or profile files

### Requirement: Profile controls belong to the discovered base

Reserved `profiles.active`, `profiles.default`, `profiles.include` and `profiles.groups` controls SHALL come only
from the merged discovered workspace primary documents, or project primaries with no workspace. Each control
SHALL retain its supplying file's origin. Later layers SHALL NOT add controls. A selected file that was already
one of those primaries SHALL retain its control authority while its ordinary values load once as the selected overlay.

#### Scenario: Controls merge through base formats

- **WHEN** workspace JSON sets profile defaults and TOML replaces those defaults and adds a group
- **THEN** the effective controls use the declared format order and retain the TOML origins

#### Scenario: Non-base selected file cannot define controls

- **WHEN** profile processing is enabled and not explicitly disabled and a selected file outside the discovered base contains `profiles.active`
- **THEN** the run fails with a typed control-location error naming that file

#### Scenario: Selecting the discovered base preserves authority

- **WHEN** discovered `morphir.toml` defines profiles and `--config morphir.toml` selects that same file
- **THEN** its controls remain authoritative, its ordinary values load once, and it has one ordinary source report

### Requirement: Profile controls remain reserved and typed

Enabled profile controls SHALL use Moon-Lander's literal name lists and group map. Invalid types, unknown controls,
secret references and controls in member, system/global, selected non-base, profile, user or environment-mapped
layers SHALL fail before filters can hide them. Controls SHALL NOT appear as ordinary effective values or leaf
provenance. Explicit disabled processing SHALL strip controls without interpreting them.

#### Scenario: Member cannot change activation

- **WHEN** profile processing is enabled and not explicitly disabled and a member primary or user override sets `profiles.active`
- **THEN** the run fails with its file and control key before executing the command

#### Scenario: Disable invalid controls

- **WHEN** `--no-profiles` is given and a syntactically valid base contains a type-invalid profile control
- **THEN** controls are not interpreted, no profiles load, and ordinary configuration still loads

### Requirement: Includes and groups use framework resolution

Profile resolution SHALL use Moon-Lander's includes, depth-first group expansion, last-occurrence deduplication,
whole-group replacement and graph bounds. Includes SHALL precede selected roots and remain when an explicit list
replaces defaults. Disabled processing SHALL suppress includes too. Invalid inactive cycles and excessive graphs
SHALL fail with their control origins; resolution SHALL NOT truncate the graph.

#### Scenario: Explicit later root keeps precedence

- **WHEN** includes select metrics, production expands to postgres and metrics, and explicit roots are production then postgres
- **THEN** the active order is production, metrics, postgres

#### Scenario: Inactive cycle fails

- **WHEN** an inactive group graph contains `a -> b -> a`
- **THEN** resolution fails with that cycle and the origin of its definition

### Requirement: Profile files follow format layers and active order

Each active profile SHALL load its adjacent `morphir.profile.<name>.<ext>` or layout-equivalent files in JSON,
YAML, then TOML groups. Within each active name, workspace files SHALL precede member files. Later names SHALL
win under existing merge rules. Two candidates in one profile/location/group SHALL be ambiguous. Profile files
SHALL NOT identify a root or change workspace/member selection.

#### Scenario: Format precedence inside one profile

- **WHEN** metrics JSON, YAML and TOML files set a key
- **THEN** metrics TOML wins that key and keys present only in lower formats remain

#### Scenario: Later workspace profile wins over an earlier member profile

- **WHEN** active profiles are postgres then metrics, a member postgres file sets a key, and the workspace metrics file replaces it
- **THEN** the workspace metrics value wins unless the member metrics file or a later stage replaces it

#### Scenario: Profile YAML alternatives are ambiguous

- **WHEN** both `morphir.profile.metrics.yaml` and `morphir.profile.metrics.yml` exist at an eligible location
- **THEN** the run fails with both paths

#### Scenario: Inactive file is not parsed

- **WHEN** only metrics is active and a postgres profile file has invalid syntax
- **THEN** the postgres file is not requested or parsed

### Requirement: Profiles remain portable and isolated

Active profile files SHALL stay within the discovery boundary or browser mount and SHALL remain eligible in
isolated mode. Missing files SHALL produce not-found reports while the profile remains active. Inaccessible files
SHALL fail visibly. Equal files, variables and options SHALL give equal resolution, values and origins on native,
js, wasm, wasm-gc and the Workbench, without adding fields to existing worker protocols.

#### Scenario: Isolated profile under a temporary root

- **WHEN** isolated discovery selects metrics inside a temporary boundary and an ancestor holds a metrics profile
- **THEN** only eligible profile files within the boundary load

#### Scenario: Marker profile without a file

- **WHEN** metrics is active and no metrics file exists
- **THEN** metrics remains active with not-found source reports
