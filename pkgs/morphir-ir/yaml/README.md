# Bounded Morphir YAML input

This portable package reads the normative [Morphir YAML profile](https://github.com/finos/morphir/blob/2b0cb1d64ccd0455aba3eaa2b143dbc7d276df70/docs/spec/ir/schemas/v4/yaml-profile.md)
on JS, native, Wasm and Wasm GC. It needs no host process or daemon.

`parse(source, limits~)` returns the duplicate-aware JSON-shaped value tree,
retaining numeric lexemes. `read_versioned(source, limits~)` uses the existing
version-specific IR decoder. `read(source, limits~)` also applies the shared
migration to current IR. Single files support versions 1 through 4 under that
decoder's support table. Quoted and block scalars stay strings, including dates.

`read_tree(files, limits~)` accepts a map of relative physical paths to text.
It assembles v4 and exactly v3.1.0 trees under their version-specific contracts.
JSON trees use the existing bounded JSON reader. YAML accepts `.yaml` and `.yml`.
The manifest selects one physical profile; ambiguous files, mixed profiles,
incorrect roles, stray package files and mismatched versions are refused.
Modules are sorted by logical path. The reader supports inline and listed nodes,
canonical filename escapes, `fileNames`, dependency specifications and Application
definitions. It ignores reserved `$meta` and unrelated non-tree extensions.

Default limits are finite and configurable:

| Resource | Default | Check |
| --- | --- | --- |
| Source bytes | 16 MiB | Before parsing; whole-tree total for trees |
| Events and scanner tokens | 400,000 each | Before the next pull or token insertion |
| Physical nodes | 100,000 | Before scalar placement or container allocation |
| Depth | 128 | Before scanner/parser stack growth and container placement |
| Scalar UTF-16 units | 4 Mi | Before each scanner buffer append, including folding buffers |
| Semantic assembly work | 100,000 | Nodes and text units before typed shorthand expansion; cumulative tree assembly |

Configured depth cannot exceed the portable hard ceiling of 512.
Diagnostic cursors and physical paths are also bounded to 4,096 UTF-16 units.
Trees accept at most 4,096 captured files. Adapters must bound filesystem traversal
and capture before supplying a map. The engine exposes the same capture bound as
`data.model_tree_file_limit`.

The physical grammar comes from the MIT-licensed MoonBit event parser, with
[pinned provenance and local changes](parser/PROVENANCE.md). The Morphir layer
resolves scalars itself and refuses anchors, aliases, tags, directives, merge
keys, duplicate members, multiple documents, non-string keys and forbidden
numeric forms. Typed float decoding also refuses nonfinite values and nonzero
underflow. Arbitrary-precision document numbers retain their lexemes.

Normalization does not preserve YAML presentation. Callers retain original bytes
separately through the shared model-document owner for exact downloads. This
package implements input, not a canonical YAML writer.
