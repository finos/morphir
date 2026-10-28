# Diagnostic logging policy

`DiagnosticLevel` owns Morphir's public names: `trace`, `debug`, `info`, `warn`, `error`, `fatal` and `off`.
It maps them to Moon-Lander levels and filters through the framework's `min_level` or `null_logger`.
`level_from_config` reads an already layered Moon-Lander configuration, defaults to `warn`, and accepts a
previously validated command-line override. It performs no file discovery or environment-variable mapping.

`text_logger` is the synchronous host adapter. Its owner supplies a text writer and a UTC `LogTimestamp` clock;
the framework captures and formats records. Disabled or filtered records invoke neither callback. Hosts must
bind the writer to stderr so finite command results and protocol stdout retain their existing schemas.

Run `moon test pkgs/morphir-host/diagnostics --target <target>` on native, JS, WASI and Wasm GC to verify names,
selection, level filtering, disabled logging, timestamps and text output. CLI options, async console/file sessions
and lifecycle draining are integrated by the application host, outside this policy package.
