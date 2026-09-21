# Installed package CLI acceptance baseline, 2026-09-21

These recordings capture real TypeScript adapter responses to the native runner's
requests. They supply fixed answers for the installed-CLI acceptance test without
requiring Bun at runtime. They do not replace live checks against both independent
implementations or prove a published release has passed qualification.

## Source revisions

- Native driver and package corpus: finos/morphir `a330e8efac6b8d75abcce35b3def454f871428e4`.
- TypeScript adapter: finos/morphir-typescript `4ae09cbd574c98aefacfd4696132001b770bb1bf`.
- The source build reported `0.4.0-beta.2`; it includes package execution added after
  that release. The published beta.2 binary does not support package execution.

Each `.ndjson` records the complete protocol exchange through the existing
`tools/record-mck-transcript.ts` proxy. Each matching `.json` is the native report
from that same run. Both exited 0 with every required case passing. No response
was synthesized from runner expectations. Existing native parity gates compare
these contracts with the retained TypeScript runner and both live adapters.

| Suite | Contract | Passing cases | Corpus hash |
| --- | --- | --- | --- |
| Integrity | `0.1.0-draft.1` | 80 | `sha256-72b6593c99af919076e59208b833771394d659838e28ee4c23554ee7f5590e23` |
| Resolution | `0.1.0-draft.2` | 78 | `sha256-8dfed22a389bd08e945b35213586b0709f2cf11f5426199bcec746007443b08b` |

The acceptance test compares every ordered report record and all metadata except
`driverVersion` and `startedAt`. Package reports have no per-record timing fields.
Recordings and reports are frozen evidence. Do not regenerate them to make a
failing comparison pass; a future capture must retain its own provenance.

## Capture procedure

At the revisions above, with submodules populated:

```sh
bun install --frozen-lockfile --cwd ecosystem/morphir-typescript
cargo build --locked --package morphir --bin morphir

target/debug/morphir mck package run --kit spec/package/mck \
  --adapter bun \
  --adapter-arg tools/record-mck-transcript.ts \
  --adapter-arg spec/mck/baseline/package/integrity.ndjson \
  --adapter-arg bun \
  --adapter-arg ecosystem/morphir-typescript/packages/mck/src/adapter.ts \
  --adapter-arg --suite --adapter-arg package \
  --report spec/mck/baseline/package/integrity.json

target/debug/morphir mck package run --kit spec/package/mck \
  --contract 0.1.0-draft.2 --adapter bun \
  --adapter-arg tools/record-mck-transcript.ts \
  --adapter-arg spec/mck/baseline/package/resolution.ndjson \
  --adapter-arg bun \
  --adapter-arg ecosystem/morphir-typescript/packages/mck/src/adapter.ts \
  --adapter-arg --suite --adapter-arg package \
  --adapter-arg --contract --adapter-arg 0.1.0-draft.2 \
  --report spec/mck/baseline/package/resolution.json
```

## File integrity

| File | SHA-256 |
| --- | --- |
| `integrity.json` | `74f292840936437eab995feda20445a6f09c7dc925748f7846d4ee98851158e5` |
| `integrity.ndjson` | `fc850101d52b416a5480e7b5af2766036d38d5cfecb66beb7ee47cd735cb6f42` |
| `resolution.json` | `401e668ef436f8fd829cb48505549f081c38be04745d8a7142c267b2384ef8c8` |
| `resolution.ndjson` | `1b81445957e1af6708aec7813c9c5a85445dab67bded815b9c2c075da7badc6f` |
