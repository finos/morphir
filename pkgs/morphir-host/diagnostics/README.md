# Diagnostic logging policy

`DiagnosticLevel` owns Morphir's public names: `trace`, `debug`, `info`, `warn`, `error`, `fatal` and `off`.
It maps them to Moon-Lander levels and filters through the framework's `min_level` or `null_logger`.
`level_from_config` reads an already layered Moon-Lander configuration, defaults to `warn`, and accepts a
previously validated command-line override. It performs no file discovery or environment-variable mapping.

`text_logger` is the synchronous host adapter. Its owner supplies a text writer and a UTC `LogTimestamp` clock;
the framework captures and formats records. Disabled or filtered records invoke neither callback. Hosts must
bind the writer to stderr so finite command results and protocol stdout retain their existing schemas.

`Settings::from_config` binds `logging.level`, `logging.file.enabled` and
`logging.file.format` from the shared configuration. File formats are `text` and
`json-lines`; the disabled state has no file-format value. A validated CLI level
overrides the configuration level. Telemetry options and files are separate.

`Settings::session` receives the workspace's granted `.morphir/logs` directory and
builds public Moon-Lander session settings. Its console uses stderr. Enabled files
use the `morphir-diagnostics` stem, daily and 10 MiB rolling, and newest-31 retention.
JSON Lines uses named `properties`, with last-wins values and complete
`duplicateProperties` histories provided by the framework. Level `off` constructs
no destinations. The runtime session owns the bounded queue, writes and draining;
building these settings performs no I/O.

`morphir-host.run_configuration` uses the shared format adapters and published
root conventions/profile provider to resolve run-wide services without scanning
project sources. The command's workspace loader retains ownership of its all-member
walk. Run-wide diagnostic settings preserve format, profile, environment and CLI
level precedence. The public sink qualification also checks this service setup.

`moon test pkgs/morphir-host/diagnostics/acceptance --target native,js` exercises
the published file sink on the real filesystem. It verifies typed properties,
duplicate history, metadata-name collisions, omission without repeats, draining,
retention and byte preservation of telemetry and unowned files.

Run `moon test pkgs/morphir-host/diagnostics --target <target>` on native, JS, WASI and Wasm GC to verify names,
selection, level filtering, disabled logging, timestamps and text output. CLI options, async console/file sessions
and lifecycle draining are integrated by the application host, outside this policy package.

Owned child launches use `platform.ProcessScope` to report the program through the
run's `morphir.host.process` logger. JavaScript supervision accepts the same local
observer callback; it does not add a field to child requests or results. Closing
the scope restores the enclosing observer and is idempotent. Native and Node
process adapters retain ownership of argv, output, deadlines and child cleanup.
