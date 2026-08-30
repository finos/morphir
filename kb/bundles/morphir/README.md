# Morphir bundles

Knowledge bundles about Morphir itself: the CLI, the IR, and the ecosystem repositories.

| Bundle | Description |
| ------ | ----------- |
| [morphir-cli](morphir-cli/index.md) | The Rust morphir command line: its commands, behavior and design, as shipped from finos/morphir. |
| [morphir-ir](morphir-ir/index.md) | The Morphir IR: its data model, naming, canonical serialization and distribution formats. |

## Source discipline

Knowledge about the CLI derives from this repository (`crates/morphir`) and the morphir-rust workspace
(`ecosystem/morphir-rust`). Pin any external sources to a commit, per
[kb/AGENTS.md](../../AGENTS.md).

Knowledge about the IR derives from the specification and design drafts under `docs/spec/` and `docs/design/` and
from the schemas under `website/static/schemas/`. The IR is implemented in several ecosystem repositories, so cite
the specification rather than any one implementation.
