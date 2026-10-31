# Python Extism qualification fixture

The two source modules are the loans fixture from finos/morphir-python at
`0d7e2eb62b4b1249129ab702a5240c41266813f6`, the source commit recorded in the
published `extension/python/v0.4.1` descriptor. They retain that repository's
Apache-2.0 licensing. `acme/rules.py` imports `acme/models.py`, so a scalar or
single-file compiler stub cannot satisfy this fixture.

The local `large_value` function is an additional precision regression. Its
integer exceeds JavaScript's exact-number range and must survive generation
without rounding.

`single/rules.py` is one module with no imports, for the Python extension
`0.4.1`, which does not claim `multiDocument` and compiles one document for each
request. The two-module `acme` directory is its multi-document refusal.

`mise run test:cli-extism-python` compiles `acme` with the published `0.4.2`
module for IR 3 and 4 from the native and npm CLIs, generates Python, runs
`apps/morphir/scripts/extension-qualification-consumer.py` on the generated
files, and recompiles them without a change to the IR. This proves only this
bounded subset and the exact host and CLI cells in the resulting receipt.
