"""Independent Python API and generated-consumer checks for the CLI fixture."""
from __future__ import annotations

import json
import sys
import hashlib
import importlib
from importlib.metadata import version as package_version
from pathlib import Path

from morphir.ir.v3 import codec as v3_codec
from morphir.ir.v4 import codec as v4_codec
from morphir_tools.python import CompileFailure, IrVersion, SourceDocument, compile_sources, native_compiler

source, compiled, generated, version = (Path(sys.argv[1]), Path(sys.argv[2]), Path(sys.argv[3]), sys.argv[4])
info = native_compiler()
assert info.compiler_version == sys.argv[5], info
result = compile_sources(
    [SourceDocument(p.relative_to(source).as_posix(), p.read_text()) for p in sorted(source.rglob("*.py"))],
    package="acme/example", ir_version=IrVersion.V3 if version == "3" else IrVersion.V4,
)
if isinstance(result, CompileFailure):
    raise AssertionError(result.diagnostics)
codec = v3_codec if version == "3" else v4_codec
assert codec.decode_versioned_distribution(compiled.read_text()) == result.distribution
for file in generated.rglob("*.py"):
    compile(file.read_text(), str(file), "exec")
sys.path.insert(0, str(generated))
# Generated module paths follow the source package/module names. Find the module
# defining the concrete fixture functions without executing arbitrary test input.
rule_files = [p for p in generated.rglob("*.py") if "def choose(" in p.read_text()]
assert len(rule_files) == 1, rule_files
name = ".".join(rule_files[0].relative_to(generated).with_suffix("").parts)
rules = importlib.import_module(name)
assert rules.choose(True, 5, 7) == 5
assert rules.choose(False, 5, 7) == 7
assert rules.twice_identity(9) == 9
assert rules.large_value() == 9007199254740993
assert rules.pair(1.0, 2.0) == (1.0, 2.0)
native_module = importlib.import_module("morphir_python_native._native")
native_path = Path(native_module.__file__)
print(json.dumps({"python": sys.version, "nativeCompiler": str(info), "nativeModuleSha256": hashlib.sha256(native_path.read_bytes()).hexdigest(), "packages": {name: package_version(name) for name in ("morphir", "morphir-python", "morphir-python-native")}, "apiParity": True, "consumer": True}))
