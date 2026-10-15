#!/usr/bin/env python3
"""Write mapping/builtin.mbt from the SDK binding inventory.

Only bindings whose semantics come from elm/core 1.0.5 map to Elm. Every other SDK reference stays qualified and
resolves through the finos/morphir-elm Elm package.
"""
import json
import pathlib
import re

ROOT = pathlib.Path(__file__).resolve().parents[3]
BINDINGS = ROOT / "pkgs/morphir-sdk/conformance/bindings.json"
OUTPUT = ROOT / "pkgs/morphir-elm/mapping/builtin.mbt"

# Elm modules that every Elm module imports by default.
DEFAULT_IMPORTS = {"Basics", "List", "Maybe", "Result", "String", "Char", "Tuple"}
ELM_MODULE = {
    "basics": "Basics", "list": "List", "maybe": "Maybe", "result": "Result", "string": "String",
    "char": "Char", "dict": "Dict", "set": "Set", "tuple": "Tuple",
}
OPERATORS = {
    "morphir/SDK:basics#add": "+", "morphir/SDK:basics#subtract": "-", "morphir/SDK:basics#multiply": "*",
    "morphir/SDK:basics#divide": "/", "morphir/SDK:basics#integer-divide": "//", "morphir/SDK:basics#power": "^",
    "morphir/SDK:basics#equal": "==", "morphir/SDK:basics#not-equal": "/=",
    "morphir/SDK:basics#less-than": "<", "morphir/SDK:basics#greater-than": ">",
    "morphir/SDK:basics#less-than-or-equal": "<=", "morphir/SDK:basics#greater-than-or-equal": ">=",
    "morphir/SDK:basics#and": "&&", "morphir/SDK:basics#or": "||", "morphir/SDK:basics#append": "++",
    "morphir/SDK:basics#compose-left": "<<", "morphir/SDK:basics#compose-right": ">>",
    "morphir/SDK:list#cons": "::",
}
# Types and constructors are not in the value inventory. Every name is fully qualified: the backend prints a
# default-import name bare only when no module or local name can capture it.
TYPES = {
    "morphir/SDK:basics#int": ("Basics.Int", None), "morphir/SDK:basics#float": ("Basics.Float", None),
    "morphir/SDK:basics#bool": ("Basics.Bool", None), "morphir/SDK:basics#order": ("Basics.Order", None),
    "morphir/SDK:basics#never": ("Basics.Never", None), "morphir/SDK:string#string": ("String.String", None),
    "morphir/SDK:char#char": ("Char.Char", None), "morphir/SDK:list#list": ("List.List", None),
    "morphir/SDK:maybe#maybe": ("Maybe.Maybe", None), "morphir/SDK:result#result": ("Result.Result", None),
    "morphir/SDK:dict#dict": ("Dict.Dict", "Dict"), "morphir/SDK:set#set": ("Set.Set", "Set"),
}
CONSTRUCTORS = {
    "morphir/SDK:maybe#just": "Maybe.Just", "morphir/SDK:maybe#nothing": "Maybe.Nothing",
    "morphir/SDK:result#ok": "Result.Ok", "morphir/SDK:result#err": "Result.Err",
    "morphir/SDK:basics#LT": "Basics.LT", "morphir/SDK:basics#EQ": "Basics.EQ", "morphir/SDK:basics#GT": "Basics.GT",
}


def canonical_name(text):
    """The v4 canonical form of a name, as migration decodes it from morphir-elm IR.

    morphir-elm's `Name.fromString` splits at camelCase boundaries and digit runs and lowers every word.
    `Name::from_words` then turns a run of two or more single letters into one upper-case initialism.
    """
    words = [w.lower() for part in text.split("-") for w in re.findall(r"[a-zA-Z][a-z]*|[0-9]+", part)]
    segments = []
    i = 0
    while i < len(words):
        start = i
        while i < len(words) and len(words[i]) == 1 and "a" <= words[i] <= "z":
            i += 1
        if i - start > 1:
            segments.append("".join(words[start:i]).upper())
        elif i > start:
            segments.append(words[start])
        else:
            segments.append(words[i])
            i += 1
    return "-".join(segments)


def canonical_key(key):
    package, rest = key.split(":")
    module, local = rest.split("#")
    path = lambda text: "/".join(canonical_name(segment) for segment in text.split("/"))
    return path(package) + ":" + path(module) + "#" + canonical_name(local)


def text(value):
    return "None" if value is None else "Some(" + json.dumps(value) + ")"


def fail(message):
    raise SystemExit("generate-builtin-mapping: " + message)


def main():
    values = json.loads(BINDINGS.read_text())["values"]
    entries = []
    for key, (name, imp) in sorted(TYPES.items()):
        entries.append((key, f"Type({json.dumps(name)}, {text(imp)})"))
    for key, name in sorted(CONSTRUCTORS.items()):
        entries.append((key, f"Function({json.dumps(name)}, None)"))
    for binding in sorted(values, key=lambda b: b["fqName"]):
        key = binding["fqName"]
        if key in OPERATORS:
            entries.append((key, f"Operator({json.dumps(OPERATORS[key])})"))
            continue
        if binding["semanticSource"] != "elm/core 1.0.5":
            continue
        sdk_module = key.split(":")[1].split("#")[0]
        if sdk_module not in ELM_MODULE:
            fail(f"{key} has semanticSource elm/core 1.0.5 but module {sdk_module!r} is not in ELM_MODULE")
        module = ELM_MODULE[sdk_module]
        name = module + "." + binding["elmName"]
        imp = None if module in DEFAULT_IMPORTS else module
        entries.append((key, f"Function({json.dumps(name)}, {text(imp)})"))
    entries = [(canonical_key(key), entry) for key, entry in entries]
    seen = set()
    for key, entry in entries:
        namespace = "type" if entry.startswith("Type(") else "value"
        if (namespace, key) in seen:
            fail(f"duplicate {namespace} key {key}")
        seen.add((namespace, key))
    lines = [
        "// GENERATED by pkgs/morphir-elm/scripts/generate-builtin-mapping.py. Do not edit.",
        "// Source: pkgs/morphir-sdk/conformance/bindings.json",
        "",
        "///|",
        "pub fn builtin_entries() -> Array[(String, MappingEntry)] {",
        "  [",
    ]
    lines += [f"    ({json.dumps(key)}, {value})," for key, value in entries]
    lines += ["  ]", "}", ""]
    OUTPUT.write_text("\n".join(lines))
    print(f"wrote {len(entries)} entries to {OUTPUT.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
