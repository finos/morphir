# Acme orders v4

The plain JSON tree and expanded single-file baseline are copied byte for byte
from `spec/mck/bounded-generation/fixtures/acme-orders/v4` in finos/morphir at
`3f3157318af5fafe474a4e1b83e7e34812517f2f`. The plain tree's Git tree ID is
`4485162797c8bb8ce181f7c240c811445afcc562`.

The native CLI test copies the tree into two temporary roots. In the control
root it changes only the integer in the referenced `order.value.json` from 73
to 74. The fixed expected artifact is `order.txt` with one integer and a line
feed. The test guest gets its cursor, selected document IDs, and document
contents through MEP.

From the repository root with the pinned MoonBit toolchain, build the native
CLI and fixture guest, then run the two acceptance cases. Set the platform
to match the native build. This example uses an Apple Silicon Mac.

```sh
moon build --target native --jobs 1 \
  apps/morphir apps/morphir-extension/acceptance/bounded-guest

MORPHIR_MEP_BOUNDED_HOST="$PWD/_build/native/debug/build/finos/morphir/morphir.exe" \
MORPHIR_MEP_BOUNDED_GUEST="$PWD/_build/native/debug/build/finos/morphir-extension/acceptance/bounded-guest/bounded-guest.exe" \
MORPHIR_MEP_BOUNDED_REPOSITORY="$PWD" \
MORPHIR_MEP_PLATFORM=aarch64-apple-darwin \
moon test --target native --jobs 1 --no-parallelize \
  apps/morphir-extension/acceptance/bounded_generation_wbtest.mbt
```


The second case serves the same 73 and 74 oracles from a schema-1
`compile.json` and its sibling `compile.lock` and `compile.dest`.

To exercise the runtime review cases, use the same host, guest, repository, and
platform variables above. Set `MORPHIR_MEP_BOUNDED_REVIEW=1`, and pass the two
expected binary digests in `MORPHIR_MEP_BOUNDED_HOST_SHA256` and
`MORPHIR_MEP_BOUNDED_GUEST_SHA256`. Run
`apps/morphir-extension/acceptance/bounded_review_wbtest.mbt` with the same
serial native test options. It checks the real describe probe and records the
shutdown time, retained diagnostic bytes, exit status, output existence, and
scratch count for each case.
