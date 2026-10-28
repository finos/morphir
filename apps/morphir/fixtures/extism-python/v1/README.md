# Python Extism qualification fixture

The two source modules are the loans fixture from finos/morphir-python at
`0d7e2eb62b4b1249129ab702a5240c41266813f6`, the source commit recorded in the
published `extension/python/v0.4.1` descriptor. They retain that repository's
Apache-2.0 licensing. `acme/rules.py` imports `acme/models.py`, so a scalar or
single-file compiler stub cannot satisfy this fixture.

The local `large_value` function is an additional precision regression. Its
integer exceeds JavaScript's exact-number range and must survive generation
without rounding.

The focused CLI suite compares native Python API compilation with the real
published WASM bundle for IR 3 and 4, generates Python, checks selected consumer
behavior, and recompiles without changing the IR. This proves only this bounded
subset and the exact host/CLI cells in the resulting receipt.
