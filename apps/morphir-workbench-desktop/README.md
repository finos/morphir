# Morphir Workbench desktop

A Proton 0.3.4 native host for the shared
[MoonBit/Rabbita workbench](../morphir-workbench/README.md). Its own `moon.work`
keeps CEF acquisition out of the portable repository's default checks. The
frontend build copies the browser app and worker into `frontend/dist`; no UI is
forked for desktop.

## Develop

Install the repository's pinned MoonBit and Node toolchains, then:

```sh
moon install moonbit-community/proton_cli@0.3.4
cd apps/morphir-workbench-desktop
moon update
proton_cli cef setup
proton_cli dev
```

The CLI starts the shared browser build and development server before launching
the native window. `proton_cli build -- --release` compiles the host.

## Package

```sh
proton_cli package --dry-run
proton_cli package --release
```

This creates local unsigned artifacts under `_build/package`; it does not
publish a release. CLI, framework and CEF helper versions must match. Supported
Proton source-built platforms are macOS Apple Silicon, Linux x64 and Windows
x64. This slice's actual desktop verification is on macOS Apple Silicon.

The packaged frontend uses Proton's secure application asset origin and runs
the same worker-based local pipeline. Its private session bootstrap now uses
typed Proton commands, restricted to the bundled main window. Every command
checks Proton's native origin/page context; navigation revokes the binding and
window shutdown closes it. The UI labels this mode **Desktop local**.

This bootstrap offers no native jobs or filesystem access. The exact private
bridge version is `0.1.0-draft.1`; `workbench_session_open` takes that version as
a string, and `workbench_session_check` / `workbench_session_close` take the
issued session identity. Identities are not credentials: native caller context
is required on every call. The public Morphir native profile remains future
work, alongside isolated native workers and explicit workspace grants.
`?mode=standalone` keeps the browser worker path without negotiating this session.
Development HTTP entries also retain the worker path; they receive no native
command grant. The framework, contract package, CLI and helpers remain pinned
to Proton 0.3.4.

Run `mise run test:workbench-native-session` from the repository root to test
session admission/revocation without CEF. The dependency-free model lives in
`pkgs/morphir-workbench-native-session`; the normal portable CI test matrix
covers it on all four targets without loading the desktop module's prebuild.

To attach the packaged
window to the same-origin authenticated gateway, set
`MORPHIR_WORKBENCH_LAUNCH_URL` to its one-use
`http://127.0.0.1:PORT/launch?token=TOKEN` URL before launching the executable.
The native host accepts only that explicit loopback launch shape and retains
the normal asset origin when the variable is absent. The gateway exchanges the
token for the upstream HttpOnly cookie. Do not put the token in logs or saved
configuration. Enable `MORPHIR_WORKBENCH_JOBS=1` on the gateway for typed evaluation;
see the [job setup and acceptance](../morphir-workbench/README.md#authenticated-evaluation-jobs).
This HTTP attachment does not introduce native daemon IPC.
An explicit connected launch registers no private native session commands.

For a headless packaged-app smoke check, enable Proton's CDP port using
`PROTON_REMOTE_DEBUGGING_PORT` and `PROTON_HEADLESS=1`, then run the browser
package's `scripts/desktop-test.js <cdp-url>`. Keep that debugging port confined
to local development.
