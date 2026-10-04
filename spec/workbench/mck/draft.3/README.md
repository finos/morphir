# Workbench invocation admission kit

This explicit kit selects test contract `0.1.0-draft.3`. Its 242 fixed cases contain
64 value-decode cases, 98 declared-value admission cases and 80 public-entry
invocation admission cases. Expected projections and stable rejection codes are
parent-owned and independently authored; adapters never receive goldens.

See the [normative draft.3 contract](../../draft.3/README.md) for wire shapes,
manifest closure, per-call value budgets, projection semantics and narrow Ion
extension evidence. Historical draft.1 and draft.2 kits remain unchanged.

```sh
morphir --no-banner mck workbench run \
  --kit spec/workbench/mck/draft.3 --adapter /path/to/adapter \
  --report .dev/workbench-invocations.json
morphir --no-banner mck workbench check \
  --kit spec/workbench/mck/draft.3 --report .dev/workbench-invocations.json
```
