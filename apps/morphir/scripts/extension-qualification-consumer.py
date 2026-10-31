"""Consumer check of the Python that the Python extension generated.

Usage: python3 -I extension-qualification-consumer.py <generated directory>

The generated directory holds the package of the extism-python fixture
(`acme/models.py` and `acme/rules.py`). The check compiles every generated file,
imports the rules module and calls its functions. It needs Python 3.12 or
later, because the generated models use `type` statements.
"""
from __future__ import annotations

import importlib
import json
import sys
from pathlib import Path

assert sys.version_info >= (3, 12), f"Python 3.12 or later is required, not {sys.version}"
generated = Path(sys.argv[1]).resolve()
files = sorted(generated.rglob("*.py"))
assert files, f"{generated} holds no Python files"
for file in files:
    compile(file.read_text(), str(file), "exec")
sys.path.insert(0, str(generated))
rules = importlib.import_module("acme.rules")
assert rules.choose(True, 5, 7) == 5
assert rules.choose(False, 5, 7) == 7
assert rules.twice_identity(9) == 9
assert rules.apply_twice(lambda value: value + 1, 1) == 3
assert rules.large_value() == 9007199254740993
assert rules.pair(1.0, 2.0) == (1.0, 2.0)
print(json.dumps({"python": sys.version.split()[0], "files": [f.relative_to(generated).as_posix() for f in files], "consumer": True}))
