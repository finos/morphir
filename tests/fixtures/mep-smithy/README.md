# Recorded MoonBit MEP sessions

Run `mise run test:mep-smithy -- --json` from the repo root. The gate builds
the native MoonBit guest. It then runs a native whitebox test of the CLI
host protocol core in `apps/morphir/extension.mbt`. The test uses the real
CLI parser, compile plan, frame encoder, and result checks. It sends those
frames to the real `apps/morphir-extension` process. It does not write a
second set of protocol messages by hand.

`compile-ion.md` records a Boolean source compile through MEP
`0.2.0-draft.1` with Ion model transport. The guest returns a model.
`missing-initialized.md` records a second run with one deliberate host
fault. The test removes `morphir.initialized` before it starts the guest.
The guest still returns a model. The Smithy state model finds the host
fault at entry 4. The gate first requires a raw validator exit of 1 and
`StateViolation` at that entry. It then checks both sessions with their
exact expected findings.

The host pipelines requests. The Markdown puts each reply after its
matching request, in guest processing order. Both directions use the
exact decoded bodies of the sent and received Content-Length frames.
The gate retains those frames, fresh transcripts, raw findings, checked
findings, and `result.json` in `.dev/mep-process/smithy/`. It compares each
fresh transcript with the file in this directory. A changed or missing
recording fails the gate.

This check covers the production host protocol core and the native guest.
Installed CLI dispatch, saved Wasm hosting, and process supervision have
their own checks. The gate does not replace them or the shared MCK. The
existing MCK library and adapter paths keep their conformance verdicts.
The Smithy CLI owns all protocol findings in this gate.

## Model source

`source.json` pins `finos/morphir` commit
`efa360608cf977d807695be33d60571e4f9c3e05` and the SHA-256 of each model
file and its README. This was upstream `main` when the gate was added.
The model describes `morphir.mep#MepSession`, MEP `0.2.0-draft.1`, and
legacy `0.1`. The five model files are copied without changes. The
upstream README is stored as `upstream-README.md`.

The local copy makes routine checks independent of upstream changes and
model downloads. Every gate run checks its file hashes. To compare it
with the pinned upstream bytes, run:

```sh
mise run test:mep-smithy -- --json --check-source
```

To update the model, select an upstream commit. Use `git show` at that
commit to replace the five files from `spec/mep/smithy/model/` and the
README from `spec/mep/smithy/README.md`. Set the commit and each file hash
in `source.json`. Run `--check-source`, then run the gate. Review all new
findings against the upstream gap table before changing expectations.
The validator stays pinned to `moonrockz/smithy-cli@0.6.0` until a separate
reviewed change updates it.

## Expected findings

Both sessions retain the `moonbitFrontendProfiles` capability. The model
refuses this extra member at entry 3 in the initialize reply. This is
gap `smithy-2qe.34.18`, which states that `ExtensionCapabilities` permits
extra members. See the pinned upstream README. Each transcript states
this gap and has a `jsonrpc-expect` fence. The matching `.expect.json`
file supplies the expectation when the gate adds the fence to a fresh
recording. No capability is removed to make the model pass.

The fault case also expects `StateViolation` at entry 4, related to entry
3. The passing case expects only the known model gap. A new finding, a
missing finding, or a different entry fails the check. Thus a passing
gate does not claim that the model has no gaps.

To refresh a session fixture after an intended wire change, run the gate
and inspect the new frames and transcript in `.dev/mep-process/smithy/`.
Copy the reviewed transcript to this directory. Do not edit individual
wire messages. Run the gate again to prove that the recording is stable.

## Command output

The mise task accepts `--json`, `--help`, `--self-test`, `--check-source`,
`--fixtures PATH`, and `--evidence PATH`. Help has no build or file effects.
The default output is a JSON result object. `--json` wraps the result in
`morphir/command-result` version `0.1.0`, with command `mep.smithy.check`,
`state`, `exitCode`, and `diagnostics`. Success has `result`. Failure has
`error.code` and `error.message`, with no `result`. Logs and child output
go to stderr. Stdout has one JSON document after all required writes.

A normal result has `modelRevision`, `validator`, `evidence`, `sessions`,
and `gapFindings`. Each session has its name, transcript SHA-256, and the
Smithy validator result. `--check-source` returns `modelRevision` and
`sourceChecked`. Help returns `render_help`. Self-test returns `checks`.
Argument errors exit 2. Expected gate refusals and other errors exit 1.
Child failures retain their positive status, or use 1 for a signal.
The command self-test checks JSON help, argument failure, missing input,
pin damage, and fixture damage. The fixture test uses a fresh recording
and checks that child logs do not enter the JSON failure result.

The existing native MEP process CI job runs the gate and its command
self-test. It retains `.dev/mep-process/` on success and failure. No new
job or runner is needed.
