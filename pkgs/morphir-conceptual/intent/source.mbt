///|
/// Vocabulary of the existing morphir-kb service. This library has no transitions.
pub(all) enum KbState {
  Backlog
  Refinement
  InProgress
  Released
  Cancelled
  Superseded
} derive(Eq, Debug)

///|
pub extend KbState with Eq::{equal, not_equal}

///|
pub extend KbState with @debug.Debug::{to_repr}

///|
pub(all) struct KbOrigin {
  bundle : Id
  short_id : Id
  slug : String
  state : KbState?
}

///|
pub(all) struct Fragment {
  anchor : Id
  text : String
}

///|
pub(all) struct Document {
  id : Id
  revision : Revision?
} derive(Eq, Debug)

///|
pub extend Document with Eq::{equal, not_equal}

///|
pub extend Document with @debug.Debug::{to_repr}

///|
pub(all) enum SourceResolution {
  Retained
  Unresolved(NonemptyText)
}

///|
/// Constructed M1 source slice. Digest verification belongs to source admission;
/// this revision-only API never claims to have verified document bytes.
pub(all) struct Source {
  id : Id
  document : Document
  locator : String
  resolution : SourceResolution
  fragments : Array[Fragment]
  descriptive : @ion.IonValue?
}

///|
pub(all) struct KbSnapshot {
  origin : KbOrigin
  document : Snapshot
  source_id : Id
  intent : Snapshot
  name : String
  locator : String
  fragment : Fragment
  descriptive : @ion.IonValue?
}

///|
pub(all) struct AdaptedSource {
  origin : KbOrigin
  source : Source
  intent : Entity
}

///|
/// Keep the caller's identity, revision and exact excerpt. Neither a KB state
/// nor an excerpt creates requirements, contracts, claims or observations.
pub fn adapt_kb_source(input : KbSnapshot) -> AdaptedSource raise InvalidInput {
  if input.source_id == input.intent.id {
    raise InvalidInput("Source and entity IDs must be distinct")
  }
  {
    origin: input.origin,
    source: {
      id: input.source_id,
      document: {
        id: input.document.id,
        revision: Some(input.document.revision),
      },
      locator: input.locator,
      resolution: Retained,
      fragments: [input.fragment],
      descriptive: input.descriptive,
    },
    intent: {
      identity: input.intent,
      name: input.name,
      source_refs: [
        { source_id: input.source_id, anchor: input.fragment.anchor, },
      ],
      content: Intent(input.fragment.text, None),
      descriptive: input.descriptive,
    },
  }
}
