# Knowledge and Intent

The vocabulary of `kb/` — the knowledge base, and the intent recorded within it. This is a glossary, not a
specification: it says what each term means, not how anything is built. For the conventions, see
[AGENTS.md](./AGENTS.md). Bundle-level term catalogs are typed concepts (`Glossary`, `Data Dictionary`); this
file is the kb-root vocabulary and is not one of those concepts.

Morphir's own domain language (IR, distributions, bundles of business logic) is not covered here.

## Language

**Intent**:
A recorded decision about work the project means to do, or has done — a feature, a bug fix, an enhancement. Written
as prose, carries a lifecycle, and outlives the work itself as the record of why.
_Avoid_: ticket, issue, story, task

**Capability**:
Something the system does today, described in the present tense. Has no lifecycle — it is either true or stale.
_Avoid_: delivered feature, shipped work, functionality

**Design Note**:
The narrative account of a capability while it is still being worked out. It states the capability plainly, records
the research and the constraints adopted, lists what is unresolved, and maps the Intents that partition delivery. It
is revised as understanding improves, which is what separates it from a Decision Record.
_Avoid_: design doc, RFC, spec

**Register**:
How a document reads and who it is written for, selected by its `type`. There are three: *article* for guidance a
reader follows step by step, *white-paper* for content that argues a position, and *reference* for lookup material.
Intent, Design Note and Decision Record are all white-paper, so each owes rejected alternatives and an unresolved
section.
_Avoid_: format, style, genre

**Altitude**:
The height a document flies at over its subject. A high-altitude document shows a whole capability in one frame. A
low-altitude document covers one API, one mechanism, or one pinned version in full detail. Altitude says what a
document is responsible for, where Register says how it reads.

**Narrative Home**:
The one Design Note at capability altitude that owns a capability's story. Every other document serving that
capability must be reachable from it in one link. A knowledge base with no narrative homes is the failure this
vocabulary exists to prevent: every detail recorded, and nothing showing how the details arrange into a capability.

This is the closest thing here to a high-level design document, but the model is not a high-level and low-level
design pair. Those form a hierarchy where the lower tier decomposes the upper. This knowledge base is hub and spoke:
one Narrative Home, plus documents that earn separate existence by being independently reusable, independently
version-pinned, or owned by a different Register. Length and level of detail are not reasons to split.
_Avoid_: HLD, LLD, high-level design, low-level design, parent doc

**Decision Record**:
An architectural decision, recorded past-tense with the alternatives that were rejected and the condition under which
it should be revisited. Immutable: superseded by a later record rather than edited, so the reasoning available at the
time survives even after the conclusion changes.
_Avoid_: ADR (spell it out), design doc, RFC

**Decision State**:
Where a Decision Record sits: `Proposed`, `Accepted`, `Superseded`, `Withdrawn`. Recorded in the `state` field, the
same field name Intent uses — the two are told apart by `type`.
_Avoid_: status (means OKF document maturity, and is validated separately)

**Intent State**:
Where an Intent sits in its lifecycle: `Backlog`, `Refinement`, `InProgress`, `Released`, `Cancelled`, `Superseded`.
Recorded in the `state` field.
_Avoid_: status (means OKF document maturity — `draft`, `stable`, `deprecated` — and is validated separately)

**Backlog**:
An Intent that has been accepted as real work but not yet specified.

**Refinement**:
An Intent being specified — the design is under discussion and not yet settled.

**InProgress**:
An Intent whose design is settled and which is actively being built.

**Released**:
A terminal Intent State: the work shipped. User-visible Kinds require a link to the Capability produced, so the
knowledge base always learns what changed; internal Kinds may release without one.

**Cancelled**:
A terminal Intent State: the project decided not to do the work. Requires a reason.
_Avoid_: deprecated, rejected, closed

**Superseded**:
A terminal Intent State: the Intent was replaced by another. Requires a link to its successor.

**Kind**:
What sort of work an Intent describes. Split into two tiers. *User-visible*: `feature`, `bug`, `performance`,
`security`, `deprecation`, `removal`. *Internal*: `refactor`, `docs`, `test`, `build`, `spike`. The tier is derived
from the Kind, and decides whether the Intent belongs in release notes.
_Avoid_: type (means the OKF document type), category, label

**Breaking**:
A property of an Intent, not a Kind — a feature and a bug fix can each break compatibility. Recorded as a boolean, and
what drives a major version bump.

**Deprecation**:
The announcement that an existing Capability will be retired. It is *not* an Intent State — deprecating something
that shipped is itself new Intent, of Kind `deprecation`.

**Removal**:
The actual retirement of a Capability, distinct from announcing it. Usually a separate, later Intent than the
Deprecation that preceded it.

**Spike**:
An Intent whose outcome is knowledge rather than working software. Releasing one produces a Design Note rather than a
Capability.
_Avoid_: research task, investigation, proof of concept

**Inbox**:
GitHub Issues — where anyone may file, and where public discussion happens. An Inbox entry becomes Intent only when a
maintainer decides it is real work worth durable prose; most never do.

**System**:
The software whose Intent a knowledge base tracks — one per knowledge base. Identified by a Package URL, so the
vocabulary is the same whatever the ecosystem.

**Artifact**:
A published unit of a System, identified by a Package URL with a version. A Released Intent names the Artifacts it
shipped in, which is what makes "what changed in this release?" answerable.

**Capability Link**:
How an Intent names the Capability it produced: `bundle-label:/path.md`. Deliberately distinct from a Package URL —
one addresses a document in this knowledge base, the other a published artifact in the world.
