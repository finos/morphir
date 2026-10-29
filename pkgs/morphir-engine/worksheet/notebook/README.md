# Worksheet notebooks

This pure package converts Scheme worksheets to Jupyter and .NET Interactive
notebooks through the published `moonrockz/notebooks` models. The CLI and
Workbench use the same conversion so a shared worksheet has the same cells on
each host.

For example, a worksheet containing `;; # Totals`, a definition, and a sum
becomes one Markdown cell followed by two Scheme code cells. The existing
Scheme reader supplies exact form and top-level comment ranges. Strings, inline
comments, nested comments and discarded datums do not create extra cells. A run
of whole-line `;;` comments becomes one Markdown cell, with one optional space
after each marker removed. Blank lines separate comment blocks.

`export_notebook(source, format, report?)` accepts a captured worksheet source
and optionally a report from that exact capture. It performs no evaluation or
I/O. A report from another source or revision is refused. Jupyter outputs retain
the observation preview as `text/plain` and the observation JSON as
`application/vnd.morphir.observation+json`; failed outcomes become Jupyter error
outputs. DIB saves source only and refuses a supplied report, so callers must
reject evaluated DIB requests before invoking evaluation or writing files.

The Jupyter document uses nbformat 4.5, deterministic cell IDs, the Scheme kernel
and language metadata, and `metadata.morphir` containing
`{profile: "morphir/worksheet-notebook", version: "0.1.0"}`. Each code cell also
names its language. DIB uses the `scheme` kernel and the same Morphir metadata. The published
codec runs in lossless mode at construction, writing and parsing. Leading blank
source lines remain in imported Scheme cells, and empty cells
retain their positions and skipped-cell indexes. DIB normalizes line endings to LF.
This profile is independent of the planned workspace and itest notebook profile.

`import_notebook(content, format)` returns worksheet text, the input cell count
and named skipped cells. Scheme code and Markdown retain their order. Markdown
lines become `;;` comments, and saved execution outputs are ignored. Foreign code
and raw cells produce skipped-cell records for the owning command to report as
warnings. Jupyter code language comes from cell metadata (`language`, Polyglot
Notebook, .NET Interactive or VS Code), falling back to notebook language
metadata. A notebook without a Scheme language declaration cannot silently turn
foreign code into Scheme. DIB uses its kernel registry and notebook registrations.

The conversion applies the existing worksheet source limits. Invalid notebooks
or Scheme syntax fail before a result is returned. The owning host adds input
paths and converts those failures to its documented JSON result and exit status;
this package writes no diagnostics to a process channel.

Run its tests on any supported target:

```sh
moon test --target native -p finos/morphir-engine/worksheet/notebook
moon test --target js -p finos/morphir-engine/worksheet/notebook
moon test --target wasm -p finos/morphir-engine/worksheet/notebook
moon test --target wasm-gc -p finos/morphir-engine/worksheet/notebook
```
