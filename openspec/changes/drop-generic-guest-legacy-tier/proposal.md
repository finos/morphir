# Proposal

## Why

The generic guest kit requires every guest to pass a tier that negotiates MEP
`0.1`. The maintainer decided on 9 November 2026 that MEP `0.1` is not
supported: the hosts being built, finos/morphir-dotnet and
finos/morphir-moonbit, support the `0.2` line. The .NET host does not offer
`0.1`, so no run through it can complete the kit. finos/morphir-dotnet#570
reports that the published Python `0.6.0` guest passes every model case of the
kit through the .NET worker, and that run still does not qualify the guest,
because the legacy tier did not run.

On 10 November 2026 the maintainer decided that the kit drops the legacy tier.

## What Changes

- **BREAKING** Remove the requirement "Required legacy JSON tier". The runner
  no longer offers MEP `0.1` and no longer calls `morphir.frontend.compile` or
  `morphir.backend.generate`.
- **BREAKING** The model tier becomes the one required session. A guest that
  does not claim MEP `0.2.0-draft.1` with a JSON `compileModel` and
  `generateModel` tuple for at least one IR version is not qualified. Guests
  that speak only `0.1` stop qualifying until they are rebuilt: Python `0.4.2`
  and the SDK fixture of finos/morphir-moonbit.
- The checks that ran only in the legacy tier move into that session: a
  malformed source, an unknown method, an unknown notification, an unchanged
  `describe` result and a request after shutdown.
- An IR version is tested when the guest claims it for its frontend and its
  backend, as before, and also claims the JSON tuple pair for it.
- The kit file `spec/mep/mck/guest-generic-json.json` does not change. It holds
  the package, the expected IR and the language sources, and none of them
  belongs to the legacy tier.
- The runner for the changed profile is the conformance runner in
  finos/morphir-dotnet. The Rust `morphir mck mep guest-run` is not changed.
  `spec/mep/mck/README.md` says that it runs the earlier plan and that its
  reports do not pass the changed check.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `mep/generic-guest-profile`: the legacy tier goes; one session on MEP
  `0.2.0-draft.1` carries every case; IR version selection needs the JSON
  tuple pair.

## Tracking

- This change follows `add-dotnet-wasm-extension-host` (#1148), whose task 4.3
  runs the kit against the .NET host and whose decision record 0004 moves the
  conformance runner to finos/morphir-dotnet. #1148 merged on 10 November 2026
  as `ac4ec5fc8`; the runner ownership prerequisite is now on `main`.
- The .NET work is tracked in finos/morphir-dotnet#563 and built in
  finos/morphir-dotnet#570.
- No bead exists yet. The shared Beads database rejects writes with a Dolt
  merge conflict, as `add-dotnet-wasm-extension-host` records. Create the bead
  and link it here after the conflict is resolved and before implementation
  starts.

## Impact

- `openspec/specs/mep/generic-guest-profile/spec.md`: two requirements removed,
  one added and five modified.
- `spec/mep/mck/README.md`: the section "Generic JSON Library profile".
- finos/morphir-dotnet: the runner's plan, comparisons and report check for
  this profile.
- `crates/morphir-mck`: no change. The Rust runner keeps the earlier plan until
  the Rust CLI is deleted (maintainer decision of 10 November 2026, recorded on
  #1146).
- Extension authors: a guest that answers only MEP `0.1` must be rebuilt for
  `0.2.0-draft.1` with JSON model tuples before it can qualify.
