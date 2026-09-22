# Scoped local Library update

Run from the repository root:

```sh
mise run test:examples -- --filter package/local-library-update
```

The scenario updates eligibility from 1.2.0 to 1.3.0 and its child from 1.0.0 to
1.1.0. It keeps the sibling at 1.0.0, writes a new full lock, restores all four
Libraries, and generates and compiles the updated provider in a consumer project.
The original lock and the independent expected output are compared byte for byte.

The fixture and expected lock come from
[`spec/package/mck/fixtures/mvp-scoped-update`](../../../spec/package/mck/fixtures/mvp-scoped-update).
Signing keys are public test data. The supported profile is
`local-library-mvp:0.1.0-draft.1`, with one caller-controlled local registry and
fresh authorization. The example proves generated provider consumption, not
cross-package linking or execution of the generated program.

Use `--target PACKAGE` to select an eligible version or `--target PACKAGE@VERSION`
for an exact stable version. Repeat the flag for multiple targets. Targets must
be non-root packages in the previous lock. Packages outside the old target
closure remain pinned. A conflicting request fails without writing a new lock.
