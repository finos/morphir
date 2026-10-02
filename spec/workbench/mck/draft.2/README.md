# Declared-value admission kit

Exact contract version: `0.1.0-draft.2`. This explicit kit contains 162 independent
cases: 64 unchanged draft.1 codec inputs/goldens with an explicit `decode-value`
operation, and 98 declared-value admission cases with `validate-value`.

The [draft.2 contract](../../draft.2/README.md) defines wire shapes, registry closure,
budgets, error codes and report admission. The shared Rust runner owns expectations
and qualification. An explicit implementation adapter is always required.
The sibling draft.1 `cases.json` is preserved unchanged and remains supported.
